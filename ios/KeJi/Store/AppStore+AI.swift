import Foundation

extension AppStore {
    func failRemoteAIExecution(_ taskId: String, provider: AIProvider, message: String) {
        let at = Date()
        withTask(taskId, at: at) { $0.status = .failed }
        let execution = AIExecution(
            id: AppStore.generateId(), taskId: taskId, provider: provider, model: "本机 \(provider.label)",
            status: .failed, startedAt: at, endedAt: at, activeSeconds: 0, elapsedSeconds: 0,
            waitingHumanSeconds: 0, tokenInput: 0, tokenOutput: 0, estimatedCost: 0,
            toolCallCount: 0, filesChanged: 0, errorMessage: message,
            logs: [AIExecutionLog(time: timeLabel(at), message: "远程派发失败")], updatedAt: at)
        aiExecutions.append(execution)
        markDirty(.aiExecutions, execution.id)
        commit()
    }

    func startRemoteAIExecution(_ taskId: String, job: RemoteJob, provider: AIProvider) {
        guard let task = task(taskId), !TaskStatus.terminal.contains(task.status) else { return }
        let at = Date()
        withTask(taskId, at: at) { $0.status = .aiQueued }
        let execution = AIExecution(
            id: AppStore.generateId(), taskId: taskId, provider: provider, model: "本机 \(provider.label)",
            status: .queued, startedAt: at, activeSeconds: 0, elapsedSeconds: 0, waitingHumanSeconds: 0,
            tokenInput: 0, tokenOutput: 0, estimatedCost: 0, toolCallCount: 0, filesChanged: 0,
            remoteJobId: job.id, logs: [AIExecutionLog(time: timeLabel(at), message: "已提交至 Valley，等待电脑领取")],
            currentStep: job.status.label, updatedAt: at)
        aiExecutions.append(execution)
        markDirty(.aiExecutions, execution.id)
        commit()
    }

    func applyRemoteJob(_ job: RemoteJob) {
        guard let idx = aiExecutions.lastIndex(where: { $0.remoteJobId == job.id }) else { return }
        let oldStatus = aiExecutions[idx].currentStep
        aiExecutions[idx].currentStep = job.status.label
        aiExecutions[idx].resultSummary = job.resultSummary
        aiExecutions[idx].updatedAt = job.updatedAt
        switch job.status {
        case .queued, .leased:
            aiExecutions[idx].status = .queued
            withTask(job.taskId, at: job.updatedAt) { $0.status = .aiQueued }
        case .running:
            aiExecutions[idx].status = .running
            withTask(job.taskId, at: job.updatedAt) { $0.status = .aiRunning }
        case .waitingLocalAuth:
            aiExecutions[idx].status = .waitingAuth
            withTask(job.taskId, at: job.updatedAt) { $0.status = .paused }
        case .waitingInput, .waitingQuota:
            aiExecutions[idx].status = .waitingInput
            withTask(job.taskId, at: job.updatedAt) { $0.status = .paused }
        case .awaitingReview:
            aiExecutions[idx].status = .completed
            aiExecutions[idx].endedAt = job.updatedAt
            withTask(job.taskId, at: job.updatedAt) { task in
                task.status = .waitingHuman
                task.resultSummary = job.resultSummary
            }
        case .failed, .expired:
            aiExecutions[idx].status = .failed
            aiExecutions[idx].endedAt = job.updatedAt
            withTask(job.taskId, at: job.updatedAt) { $0.status = .failed }
        case .cancelled:
            aiExecutions[idx].status = .cancelled
            aiExecutions[idx].endedAt = job.updatedAt
            withTask(job.taskId, at: job.updatedAt) { $0.status = .cancelled }
        }
        if oldStatus != aiExecutions[idx].currentStep {
            aiExecutions[idx].logs.append(AIExecutionLog(time: timeLabel(job.updatedAt), message: job.status.label))
        }
        markDirty(.aiExecutions, aiExecutions[idx].id)
        commit()
    }

    func startAIExecution(_ taskId: String) {
        guard let task = task(taskId) else { return }
        guard !TaskStatus.terminal.contains(task.status), task.status != .waitingHuman else { return }
        if let existing = aiExecutions.last(where: { $0.taskId == taskId }),
           [.running, .waitingInput, .waitingAuth].contains(existing.status) {
            if existing.status != .running { authorizeAI(taskId) }
            return
        }
        if activeFocus?.taskId == taskId { pauseFocus(reason: "等待 AI") }
        let at = Date()
        let provider = task.aiProvider ?? .claude
        let execution = AIExecution(
            id: AppStore.generateId(), taskId: taskId, provider: provider,
            model: provider == .codex ? "gpt-4o" : "claude-sonnet-4",
            status: .running, startedAt: at, activeSeconds: 0, elapsedSeconds: 0, waitingHumanSeconds: 0,
            tokenInput: 0, tokenOutput: 0, estimatedCost: 0, toolCallCount: 0, filesChanged: 0,
            logs: [AIExecutionLog(time: timeLabel(at), message: "开始执行")],
            currentStep: AppStore.aiSteps[0], updatedAt: at)
        withTask(taskId, at: at) { $0.status = .aiRunning }
        aiExecutions.append(execution)
        markDirty(.aiExecutions, execution.id)
        appendSession(newSession(taskId: taskId, type: .aiActive, executor: provider.rawValue, startedAt: at,
                                 source: .simulated, confidence: .exact))
        commit()
    }

    func pauseAIExecution(_ taskId: String) {
        guard aiExecutions.contains(where: { $0.taskId == taskId && $0.status == .running }) else { return }
        let at = Date()
        withTask(taskId, at: at) { $0.status = .paused }
        for idx in aiExecutions.indices where aiExecutions[idx].taskId == taskId && aiExecutions[idx].status == .running {
            aiExecutions[idx].status = .waitingInput
            aiExecutions[idx].updatedAt = at
            markDirty(.aiExecutions, aiExecutions[idx].id)
        }
        closeOpenSessions(at: at) { $0.taskId == taskId && $0.type == .aiActive }
        commit()
    }

    func cancelAIExecution(_ taskId: String) {
        guard let task = task(taskId), !TaskStatus.terminal.contains(task.status) else { return }
        let at = Date()
        withTask(taskId, at: at) { $0.status = .cancelled }
        for idx in aiExecutions.indices where aiExecutions[idx].taskId == taskId && aiExecutions[idx].endedAt == nil {
            aiExecutions[idx].status = .cancelled
            aiExecutions[idx].endedAt = at
            aiExecutions[idx].updatedAt = at
            markDirty(.aiExecutions, aiExecutions[idx].id)
        }
        closeOpenSessions(at: at) { $0.taskId == taskId }
        commit()
    }

    func authorizeAI(_ taskId: String) {
        guard let task = task(taskId), !TaskStatus.terminal.contains(task.status),
              let idx = aiExecutions.lastIndex(where: {
                  $0.taskId == taskId && [.waitingInput, .waitingAuth].contains($0.status)
              }) else { return }
        let at = Date()
        withTask(taskId, at: at) { $0.status = .aiRunning }
        aiExecutions[idx].status = .running
        aiExecutions[idx].updatedAt = at
        markDirty(.aiExecutions, aiExecutions[idx].id)
        if !timeSessions.contains(where: { $0.taskId == taskId && $0.type == .aiActive && $0.endedAt == nil }) {
            appendSession(newSession(taskId: taskId, type: .aiActive, executor: aiExecutions[idx].provider.rawValue,
                                     startedAt: at, source: .simulated, confidence: .exact))
        }
        commit()
    }

    /// Completes the task, closes the waiting_human session and books an estimated 8-minute review.
    func completeAIReview(_ taskId: String) {
        guard task(taskId)?.status == .waitingHuman else { return }
        let at = Date()
        withTask(taskId, at: at) { t in
            t.status = .completed
            t.completedAt = at
        }
        closeOpenSessions(at: at) { $0.taskId == taskId && $0.type == .waitingHuman }
        appendSession(newSession(taskId: taskId, type: .humanReview, executor: TimeSession.humanExecutor,
                                 startedAt: at, endedAt: at, durationSeconds: 480, source: .manual,
                                 confidence: .estimated))
        commit()
    }

    /// One-second simulation step (App.tsx runs it on a 1s interval).
    /// 30s per step; finishes when active > 120 && active % 60 == 0 → task becomes waiting_human.
    func tickAIExecutions(at date: Date? = nil) {
        let reference = date ?? Date()
        now = reference
        let hasRunningAI = aiExecutions.contains { $0.status == .running && $0.remoteJobId == nil }
        let hasWaiting = timeSessions.contains { $0.type == .waitingHuman && $0.endedAt == nil }
        guard hasRunningAI || activeFocus != nil || hasWaiting else { return }

        var spawned: [TimeSession] = []
        var finishedTasks: Set<String> = []
        let runningTasks = Set(aiExecutions.filter { $0.status == .running && $0.remoteJobId == nil }.map(\.taskId))
        for idx in aiExecutions.indices where aiExecutions[idx].status == .running && aiExecutions[idx].remoteJobId == nil {
            var ae = aiExecutions[idx]
            let active = ae.activeSeconds + 1
            let stepIdx = min(active / 30, AppStore.aiSteps.count - 1)
            let shouldFinish = active > 120 && active % 60 == 0

            ae.activeSeconds = active
            ae.elapsedSeconds = active
            ae.tokenInput += Int.random(in: 0..<50)
            ae.estimatedCost += 0.001

            if shouldFinish {
                finishedTasks.insert(ae.taskId)
                withTask(ae.taskId, at: reference) { $0.status = .waitingHuman }
                spawned.append(newSession(taskId: ae.taskId, type: .waitingHuman, executor: TimeSession.humanExecutor,
                                          startedAt: reference, source: .inferred, confidence: .estimated))
                ae.status = .completed
                ae.endedAt = reference
                ae.resultSummary = "执行完成，等待审核"
                ae.logs.append(AIExecutionLog(time: timeLabel(reference), message: AppStore.aiSteps[stepIdx]))
                ae.updatedAt = reference
                markDirty(.aiExecutions, ae.id)
            } else {
                ae.tokenOutput += Int.random(in: 0..<20)
                ae.toolCallCount += active % 15 == 0 ? 1 : 0
                ae.currentStep = AppStore.aiSteps[stepIdx]
                if active % 30 == 0 {
                    ae.logs.append(AIExecutionLog(time: timeLabel(reference), message: AppStore.aiSteps[stepIdx]))
                    ae.updatedAt = reference
                    markDirty(.aiExecutions, ae.id)
                }
            }
            aiExecutions[idx] = ae
            aiExecutions[idx].updatedAt = reference
            markDirty(.aiExecutions, ae.id)
        }

        for idx in timeSessions.indices {
            let ts = timeSessions[idx]
            if ts.endedAt == nil && (ts.type == .waitingHuman || (ts.type == .aiActive && runningTasks.contains(ts.taskId))) {
                timeSessions[idx].durationSeconds += 1
                timeSessions[idx].updatedAt = reference
                markDirty(.timeSessions, ts.id)
            }
        }
        if let focus = activeFocus {
            let elapsed = secondsSince(focus.startedAt, at: reference) + focus.accumulatedSeconds
            for idx in timeSessions.indices
            where timeSessions[idx].taskId == focus.taskId && timeSessions[idx].endedAt == nil
                && timeSessions[idx].type == .humanFocus {
                timeSessions[idx].durationSeconds = elapsed
                timeSessions[idx].updatedAt = reference
                markDirty(.timeSessions, timeSessions[idx].id)
            }
        }
        closeOpenSessions(at: reference) { $0.type == .aiActive && finishedTasks.contains($0.taskId) }
        for s in spawned { appendSession(s) }
        commit()
    }

    /// Root view calls this every second.
    func tick() { tickAIExecutions(at: Date()) }
}
