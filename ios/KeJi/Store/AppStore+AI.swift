import Foundation

extension AppStore {
    func startAIExecution(_ taskId: String) {
        guard let task = task(taskId) else { return }
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
        let at = Date()
        withTask(taskId, at: at) { $0.status = .paused }
        for idx in aiExecutions.indices where aiExecutions[idx].taskId == taskId && aiExecutions[idx].status == .running {
            aiExecutions[idx].status = .waitingInput
            aiExecutions[idx].updatedAt = at
            markDirty(.aiExecutions, aiExecutions[idx].id)
        }
        commit()
    }

    func cancelAIExecution(_ taskId: String) {
        let at = Date()
        withTask(taskId, at: at) { $0.status = .cancelled }
        for idx in aiExecutions.indices where aiExecutions[idx].taskId == taskId {
            aiExecutions[idx].status = .cancelled
            aiExecutions[idx].endedAt = at
            aiExecutions[idx].updatedAt = at
            markDirty(.aiExecutions, aiExecutions[idx].id)
        }
        closeOpenSessions(at: at) { $0.taskId == taskId }
        commit()
    }

    func authorizeAI(_ taskId: String) {
        let at = Date()
        withTask(taskId, at: at) { $0.status = .aiRunning }
        for idx in aiExecutions.indices where aiExecutions[idx].taskId == taskId {
            aiExecutions[idx].status = .running
            aiExecutions[idx].updatedAt = at
            markDirty(.aiExecutions, aiExecutions[idx].id)
        }
        commit()
    }

    /// Completes the task, closes the waiting_human session and books an estimated 8-minute review.
    func completeAIReview(_ taskId: String) {
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
        let hasRunningAI = aiExecutions.contains { $0.status == .running }
        guard hasRunningAI || activeFocus != nil else { return }

        var spawned: [TimeSession] = []
        for idx in aiExecutions.indices where aiExecutions[idx].status == .running {
            var ae = aiExecutions[idx]
            let active = ae.activeSeconds + 1
            let stepIdx = min(active / 30, AppStore.aiSteps.count - 1)
            let shouldFinish = active > 120 && active % 60 == 0

            ae.activeSeconds = active
            ae.elapsedSeconds = active
            ae.tokenInput += Int.random(in: 0..<50)
            ae.estimatedCost += 0.001

            if shouldFinish {
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
                    markDirty(.aiExecutions, ae.id) // push progress at step boundaries only
                }
            }
            aiExecutions[idx] = ae
        }

        for idx in timeSessions.indices {
            let ts = timeSessions[idx]
            if ts.endedAt == nil && (ts.type == .aiActive || ts.type == .waitingHuman) {
                timeSessions[idx].durationSeconds += 1
            }
        }
        if let focus = activeFocus {
            let elapsed = secondsSince(focus.startedAt, at: reference) + focus.accumulatedSeconds
            for idx in timeSessions.indices
            where timeSessions[idx].taskId == focus.taskId && timeSessions[idx].endedAt == nil
                && timeSessions[idx].type == .humanFocus {
                timeSessions[idx].durationSeconds = elapsed
            }
        }
        for s in spawned { appendSession(s) }
        commit()
    }

    /// Root view calls this every second.
    func tick() { tickAIExecutions(at: Date()) }
}
