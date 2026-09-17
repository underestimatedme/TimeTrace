import Foundation
import CryptoKit

extension AppStore {
    @discardableResult
    func refreshPlans(taskID: String) async -> Bool {
        if let ongoing = planRefreshes[taskID] { return await ongoing.value }
        guard workspaceClient != nil else { return true }
        guard !(dirty[.tasks]?.contains(taskID) ?? false) else { return false }
        let refresh = Task { await fetchPlans(taskID: taskID) }
        planRefreshes[taskID] = refresh
        let result = await refresh.value
        planRefreshes[taskID] = nil
        return result
    }

    private func fetchPlans(taskID: String) async -> Bool {
        guard let workspaceClient else { return false }
        refreshingPlanTasks.insert(taskID)
        defer { refreshingPlanTasks.remove(taskID) }
        do {
            var remote = try await workspaceClient.plans(taskID: taskID)
            if remote.isEmpty, let draft = plans.first(where: { $0.taskId == taskID && $0.id.hasPrefix("draft-") }) {
                remote = [try await workspaceClient.createPlan(taskID: taskID, draft: draft)]
            }
            let incoming = remote.map { item in
                // An older GET must not overwrite a newer action receipt.
                if let current = plan(item.id), confirmedPlanRevisions[item.id] == current.revision,
                   current.revision > item.revision { return current }
                return item
            }
            plans.removeAll { $0.taskId == taskID }
            plans.append(contentsOf: incoming)
            for item in incoming {
                confirmedPlanRevisions[item.id] = item.revision
                if planErrors[item.id]?.hasPrefix("缓存中的验收") == true { planErrors[item.id] = nil }
            }
            planErrors[taskID] = nil
            commit()
            return true
        } catch { recordPlanError(error, id: taskID); return false }
    }

    @discardableResult
    func refreshAllPlans() async -> Bool {
        var success = true
        for taskID in tasks.map(\.id) {
            if !(await refreshPlans(taskID: taskID)) { success = false }
        }
        return success
    }

    func prepareTaskPlan(_ taskID: String) async -> PlanItem? {
        do { try await preparePlanDispatch?() }
        catch {
            recordPlanError(error, id: taskID)
            return nil
        }
        guard await refreshPlans(taskID: taskID) else { return nil }
        return plans(forTask: taskID).first { !$0.id.hasPrefix("draft-") }
    }

    func loadPlanRunners(for id: String) async {
        if let reason = planDispatchUnavailableReason(id) { planErrors[id] = reason; return }
        guard let workspaceClient else { planErrors[id] = "离线：连接服务后才能派发。"; return }
        do { planRunners = try await workspaceClient.runners() }
        catch { recordPlanError(error, id: id) }
    }

    func refreshPlanJob(_ id: String) async {
        guard let workspaceClient, let plan = plan(id) else { return }
        if let existing = planJobs[id] {
            do {
                let job = try await workspaceClient.job(id: existing.id)
                planJobs[id] = job
                commit()
            } catch { recordPlanError(error, id: id) }
        }
        await refreshPlans(taskID: plan.taskId)
    }

    @discardableResult
    func dispatchPlan(_ id: String, runnerID: String, workspaceID: String, toolID: String) async -> Bool {
        if let reason = planDispatchUnavailableReason(id) { planErrors[id] = reason; return false }
        guard !planBusy.contains(id), let initial = plan(id), canDispatchPlan(initial, allPlans: plans),
              !id.hasPrefix("draft-") else { return false }
        guard let workspaceClient else { planErrors[id] = "离线：连接服务后才能派发。"; return false }
        planBusy.insert(id)
        defer { planBusy.remove(id) }
        do {
            try await preparePlanDispatch?()
            if let reason = planDispatchUnavailableReason(id) { throw APIError(code: 42200, message: reason) }
            guard let current = plan(id), canDispatchPlan(current, allPlans: plans),
                  let task = task(current.taskId), !(dirty[.tasks]?.contains(task.id) ?? false),
                  !runnerID.isEmpty, !workspaceID.isEmpty, !toolID.isEmpty else {
                throw APIError(code: 42200, message: "请刷新 Plan 并选择可用电脑、工作区及工具。")
            }
            let identity = [id, String(current.revision), runnerID, workspaceID, toolID].joined(separator: "|")
            let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            var instructions = [current.title]
            if !task.description.isEmpty { instructions.append(task.description) }
            if !current.criteria.isEmpty { instructions.append("验收项：\n" + current.criteria.map { "- " + $0 }.joined(separator: "\n")) }
            let request = RemoteJobRequest(taskId: task.id, runnerId: runnerID, workspaceId: workspaceID,
                toolProfileId: toolID, prompt: instructions.joined(separator: "\n\n"),
                idempotencyKey: "ios-" + key, expectedTaskRevision: Int64(task.updatedAt.timeIntervalSince1970 * 1000), planId: id)
            let job = try await workspaceClient.dispatch(request)
            planJobs[id] = job
            planErrors[id] = nil
            commit()
            await refreshPlans(taskID: current.taskId)
            return true
        } catch {
            recordPlanError(error, id: id)
            if let api = error as? APIError, (40900..<41000).contains(api.code) {
                await refreshPlans(taskID: initial.taskId)
            }
            return false
        }
    }

    @discardableResult
    func cancelPlan(_ id: String, expectedRevision: Int) async -> Bool {
        await mutatePlan(id, expectedRevision: expectedRevision, retry: false)
    }

    @discardableResult
    func retryPlan(_ id: String, expectedRevision: Int) async -> Bool {
        guard plan(id)?.status == .failed else { return false }
        return await mutatePlan(id, expectedRevision: expectedRevision, retry: true)
    }

    /// 分派策略由服务端确认后才生效；运行中锁定，额外付费恒为 0。
    @discardableResult
    func setPlanExecutionMode(_ id: String, mode: PlanExecutionMode) async -> Bool {
        guard let current = plan(id), canEditExecutionPolicy(current), current.executionPolicy.mode != mode.rawValue else { return false }
        guard !planBusy.contains(id), let workspaceClient else {
            planErrors[id] = "离线或请求进行中，请稍后重试。"; return false
        }
        planBusy.insert(id)
        defer { planBusy.remove(id) }
        var policy = current.executionPolicy
        policy.mode = mode.rawValue
        policy.maxAdditionalSpendMinor = 0
        do {
            applyPlan(try await workspaceClient.updatePlanPolicy(id: id, expectedRevision: current.revision, policy: policy))
            planErrors[id] = nil
            return true
        } catch { recordPlanError(error, id: id); return false }
    }

    private func mutatePlan(_ id: String, expectedRevision: Int, retry: Bool) async -> Bool {
        guard !planBusy.contains(id), let workspaceClient else {
            planErrors[id] = "离线或请求进行中，请稍后重试。"; return false
        }
        planBusy.insert(id)
        defer { planBusy.remove(id) }
        do {
            let receipt = try await (retry
                ? workspaceClient.retryPlan(id: id, expectedRevision: expectedRevision)
                : workspaceClient.cancelPlan(id: id, expectedRevision: expectedRevision))
            applyPlan(receipt)
            planErrors[id] = retry ? nil : "取消请求已提交，当前状态：\(receipt.status.label)。"
            await refreshPlanProjection?()
            return true
        } catch { recordPlanError(error, id: id); return false }
    }

    func plan(_ id: String) -> PlanItem? {
        if let exact = plans.first(where: { $0.id == id }) { return exact }
        if id.hasPrefix("draft-") { return plans.first { $0.taskId == String(id.dropFirst(6)) } }
        return nil
    }

    /// The view owns task cancellation; all fetching and polling stays in the store.
    func monitorPlan(_ id: String) async {
        while !Task.isCancelled {
            guard let current = plan(id) else { return }
            await refreshPlanJob(current.id)
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
        }
    }

    /// Plans for a task, ordered by priority then creation (deterministic).
    func plans(forTask taskId: String) -> [PlanItem] {
        plans.filter { $0.taskId == taskId }.sorted { ($0.priority, $0.createdAt) < ($1.priority, $1.createdAt) }
    }

    @discardableResult
    func acceptPlan(_ id: String, expectedRevision: Int, evidenceIDs: [String],
                    criteria: [CriterionResultBody]) async -> Bool {
        guard !planBusy.contains(id), let plan = plan(id) else { return false }
        guard plan.status == .awaitingReview, plan.revision == expectedRevision,
              criteria.count == plan.criteria.count,
              Set(criteria.map(\.index)) == Set(plan.criteria.indices),
              criteria.allSatisfy(\.accepted) else {
            planErrors[id] = "请重新检查当前版本及全部验收项。"
            return false
        }
        guard let workspaceClient else {
            planErrors[id] = "离线：仅保存草稿，连接服务后才能验收。"
            return false
        }
        planBusy.insert(id)
        defer { planBusy.remove(id) }
        do {
            let receipt = try await workspaceClient.acceptPlan(id: id, expectedRevision: expectedRevision,
                                                              evidenceIDs: evidenceIDs, criteria: criteria)
            applyPlan(receipt)
            planErrors[id] = nil
            await refreshPlanProjection?()
            return receipt.status == .accepted
        } catch {
            recordPlanError(error, id: id)
            return false
        }
    }

    func applyPlan(_ plan: PlanItem) {
        confirmedPlanRevisions[plan.id] = plan.revision
        if let index = plans.firstIndex(where: { $0.id == plan.id }) { plans[index] = plan }
        else { plans.append(plan) }
        commit()
    }

    func planDispatchUnavailableReason(_ id: String) -> String? {
        guard let plan = plan(id), let task = task(plan.taskId) else { return "任务不可用，请刷新后重试。" }
        guard task.executorType == .ai || task.executorType == .collaboration else {
            return "人工或外部任务不能派发给 AI。服务暂不支持人工 Plan 的待验收流程；请继续记录人工任务，待该流程开放后再验收。"
        }
        return nil
    }

    func recordPlanError(_ error: Error, id: String) {
        if let api = error as? APIError, (40900..<41000).contains(api.code) {
            if let current = api.currentPlan { applyPlan(current) }
            planErrors[id] = "版本冲突：已显示服务端当前状态，请刷新并重新审核后再提交。"
        } else {
            if let api = error as? APIError, api.code == 40300 {
                planErrors[id] = "请先登录账号，再刷新以创建或操作 Plan。"
            } else { planErrors[id] = error.localizedDescription }
        }
    }
}
