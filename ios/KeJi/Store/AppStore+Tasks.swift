import Foundation

extension AppStore {
    /// `addTask`: id/createdAt are assigned here; status defaults to `.inbox`.
    @discardableResult
    func addTask(_ input: TaskItem) -> String {
        var task = input
        let at = Date()
        task.id = AppStore.generateId()
        task.createdAt = at
        task.updatedAt = at
        tasks.append(task)
        markDirty(.tasks, task.id)
        commit()
        return task.id
    }

    func updateTask(_ id: String, _ updates: (inout TaskItem) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        updates(&tasks[idx])
        tasks[idx].updatedAt = Date()
        markDirty(.tasks, id)
        commit()
    }

    /// Cascades to the task's sessions and executions (prototype semantics) and tombstones all of them.
    func deleteTask(_ id: String) {
        tasks.removeAll { $0.id == id }
        let sessions = timeSessions.filter { $0.taskId == id }
        let execs = aiExecutions.filter { $0.taskId == id }
        timeSessions.removeAll { $0.taskId == id }
        aiExecutions.removeAll { $0.taskId == id }
        if activeFocus?.taskId == id {
            activeFocus = nil
            markActiveFocusDirty()
        }
        markDeleted(.tasks, id)
        sessions.forEach { markDeleted(.timeSessions, $0.id) }
        execs.forEach { markDeleted(.aiExecutions, $0.id) }
        commit()
    }

    func setTaskStatus(_ id: String, _ status: TaskStatus) {
        guard let task = task(id) else { return }
        if status == .completed, task.status == .waitingHuman {
            completeAIReview(id)
            return
        }
        if status == .completed, activeFocus?.taskId == id {
            completeFocus()
            return
        }
        if TaskStatus.terminal.contains(status) {
            let endedAt = Date()
            if activeFocus?.taskId == id { pauseFocus() }
            closeOpenSessions(at: endedAt) { $0.taskId == id }
            for idx in aiExecutions.indices where aiExecutions[idx].taskId == id && aiExecutions[idx].endedAt == nil {
                aiExecutions[idx].status = status == .completed ? .completed : (status == .failed ? .failed : .cancelled)
                aiExecutions[idx].endedAt = endedAt
                aiExecutions[idx].updatedAt = endedAt
                markDirty(.aiExecutions, aiExecutions[idx].id)
            }
        }
        let at = Date()
        updateTask(id) { t in
            t.status = status
            if status == .completed { t.completedAt = at }
            else { t.completedAt = nil }
        }
    }

    func addTimeSession(_ input: TimeSession) {
        var session = input
        session.id = AppStore.generateId()
        session.updatedAt = Date()
        timeSessions.append(session)
        markDirty(.timeSessions, session.id)
        commit()
    }

    func updateSettings(_ updates: (inout UserSettings) -> Void) {
        updates(&settings)
        settings.updatedAt = Date()
        markSettingsDirty()
        commit()
    }

    // MARK: internal helpers shared by focus/AI reducers

    func withTask(_ id: String, at: Date, _ updates: (inout TaskItem) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        updates(&tasks[idx])
        tasks[idx].updatedAt = at
        markDirty(.tasks, id)
    }

    func newSession(taskId: String, type: TimeSessionType, executor: String, startedAt: Date, endedAt: Date? = nil,
                    durationSeconds: Int = 0, source: TimeSessionSource, confidence: Confidence,
                    note: String? = nil) -> TimeSession {
        TimeSession(id: AppStore.generateId(), taskId: taskId, type: type, executor: executor, startedAt: startedAt,
                    endedAt: endedAt, durationSeconds: durationSeconds, source: source, confidence: confidence,
                    note: note, updatedAt: startedAt)
    }

    func appendSession(_ session: TimeSession) {
        timeSessions.append(session)
        markDirty(.timeSessions, session.id)
    }

    /// `closeOpenSession`: closes sessions matching `predicate` that have no `endedAt`.
    func closeOpenSessions(at endedAt: Date, durationOverride: Int? = nil, note: String? = nil,
                           where predicate: (TimeSession) -> Bool) {
        for idx in timeSessions.indices where predicate(timeSessions[idx]) && timeSessions[idx].endedAt == nil {
            var s = timeSessions[idx]
            s.endedAt = endedAt
            let fallback = s.durationSeconds != 0 ? s.durationSeconds : secondsSince(s.startedAt, at: endedAt)
            s.durationSeconds = durationOverride ?? fallback
            if let note, !note.isEmpty { s.note = note }
            s.updatedAt = endedAt
            timeSessions[idx] = s
            markDirty(.timeSessions, s.id)
        }
    }
}
