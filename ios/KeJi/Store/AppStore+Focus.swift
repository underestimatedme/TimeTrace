import Foundation

extension AppStore {
    func startFocus(_ taskId: String) {
        let at = Date()
        activeFocus = ActiveFocus(taskId: taskId, startedAt: at, accumulatedSeconds: 0)
        withTask(taskId, at: at) { $0.status = .humanRunning }
        appendSession(newSession(taskId: taskId, type: .humanFocus, executor: TimeSession.humanExecutor,
                                 startedAt: at, source: .timer, confidence: .exact))
        markActiveFocusDirty()
        commit()
    }

    /// Closes the open focus session with the elapsed time; with a `reason` also logs an interruption.
    func pauseFocus(reason: String? = nil) {
        guard let focus = activeFocus else { return }
        let at = Date()
        let elapsed = secondsSince(focus.startedAt, at: at) + focus.accumulatedSeconds
        closeOpenSessions(at: at, durationOverride: elapsed) { $0.taskId == focus.taskId && $0.type == .humanFocus }
        if let reason, !reason.isEmpty {
            appendSession(newSession(taskId: focus.taskId, type: .interruption, executor: TimeSession.humanExecutor,
                                     startedAt: at, endedAt: at, durationSeconds: 0, source: .manual,
                                     confidence: .exact, note: reason))
        }
        withTask(focus.taskId, at: at) { $0.status = .paused }
        activeFocus = nil
        markActiveFocusDirty()
        commit()
    }

    func resumeFocus() {
        guard var focus = activeFocus else { return }
        let at = Date()
        focus.startedAt = at
        activeFocus = focus
        withTask(focus.taskId, at: at) { $0.status = .humanRunning }
        appendSession(newSession(taskId: focus.taskId, type: .humanFocus, executor: TimeSession.humanExecutor,
                                 startedAt: at, source: .timer, confidence: .exact))
        markActiveFocusDirty()
        commit()
    }

    func completeFocus(note: String? = nil) {
        guard let focus = activeFocus else { return }
        let at = Date()
        let elapsed = secondsSince(focus.startedAt, at: at) + focus.accumulatedSeconds
        withTask(focus.taskId, at: at) { t in
            t.status = .completed
            t.completedAt = at
        }
        closeOpenSessions(at: at, durationOverride: elapsed, note: note) {
            $0.taskId == focus.taskId && $0.type == .humanFocus
        }
        activeFocus = nil
        markActiveFocusDirty()
        commit()
    }

    func markInterruption(reason: String) {
        guard let focus = activeFocus else { return }
        let at = Date()
        appendSession(newSession(taskId: focus.taskId, type: .interruption, executor: TimeSession.humanExecutor,
                                 startedAt: at, endedAt: at, durationSeconds: 0, source: .manual,
                                 confidence: .exact, note: reason))
        commit()
    }
}
