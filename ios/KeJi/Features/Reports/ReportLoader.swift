import Foundation
import Observation

struct ReportContext: Hashable {
    let date: String
    let zone: String

    init(date: String, zone: String) { self.date = date; self.zone = zone }
    init(now: Date, timeZone: TimeZone) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        date = formatter.string(from: now)
        zone = timeZone.identifier
    }
}

/// Owns the snapshot identity and request generation. A new day/zone can load
/// while an older request is in flight; that older result cannot change it.
@Observable @MainActor
final class ReportLoader {
    private(set) var context: ReportContext?
    private(set) var report: DailyReport?
    private(set) var loading = false
    private(set) var error: String?
    private var generation = 0

    func currentReport(for context: ReportContext) -> DailyReport? {
        guard self.context == context, report?.localDate == context.date,
              report?.breakdown?.zone == context.zone else { return nil }
        return report
    }

    func presentation(for context: ReportContext, sessions: [TimeSession], taskIds: Set<String>? = nil) -> ReportPresentation {
        if let facts = currentReport(for: context)?.breakdown?.facts {
            return ReportPresentation(facts: facts, taskIds: taskIds)
        }
        let local = sessions.filter { taskIds == nil || taskIds!.contains($0.taskId) }
        return ReportPresentation(sessions: local, day: context.date, timeZone: TimeZone(identifier: context.zone) ?? .current)
    }

    func load(context: ReportContext, fetch: () async throws -> DailyReport) async {
        generation += 1
        let request = generation
        if self.context != context { report = nil }
        self.context = context
        loading = true; error = nil
        defer { if request == generation { loading = false } }
        do {
            let loaded = try await fetch()
            guard request == generation else { return }
            guard loaded.localDate == context.date,
                  loaded.isEmpty || loaded.breakdown?.zone == context.zone else {
                throw ReportLoadError.mismatchedContext
            }
            report = loaded.isEmpty ? nil : loaded
        } catch {
            guard request == generation else { return }
            self.error = "报告未更新：\(error.localizedDescription)；当前显示当日草稿。"
        }
    }
}

private enum ReportLoadError: LocalizedError {
    case mismatchedContext
    var errorDescription: String? { "报告日期或时区不匹配" }
}
