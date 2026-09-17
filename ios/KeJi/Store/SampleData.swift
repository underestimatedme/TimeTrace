import Foundation

/// Port of design/src/data/mockData.ts. Dates are relative to `now`.
enum SampleData {
    struct Bundle {
        var state: StateSnapshot
        var dailyStats: [DailyStats]
    }

    static func createEmptyData(now: Date = Date()) -> Bundle {
        var state = StateSnapshot()
        state.settings = UserSettings.defaults(now: now)
        state.aiTools = AIToolConnection.defaults
        return Bundle(state: state, dailyStats: [])
    }

    /// A representative account-quota snapshot for offline/sample builds: one
    /// pool available (short + weekly fresh) and one weekly window that has gone
    /// stale (shows 待核验, never 100%).
    static func sampleAccountQuota(now: Date = Date()) -> AccountQuota {
        func win(_ pool: String, _ scope: String, used: Double?, fresh: Bool) -> QuotaWindow {
            QuotaWindow(poolId: pool, scope: scope, kind: "codex", usedPercent: used, resetAt: nil,
                        observedAt: fresh ? now.addingTimeInterval(-300) : now.addingTimeInterval(-7200),
                        expiresAt: fresh ? now.addingTimeInterval(3600) : now.addingTimeInterval(-3600),
                        source: "runner", confidence: "exact")
        }
        return AccountQuota(pools: [
            AccountQuotaPool(poolId: "pool-codex", availability: "available",
                             windows: [win("pool-codex", "short", used: 20, fresh: true),
                                       win("pool-codex", "weekly", used: 45, fresh: true)]),
            AccountQuotaPool(poolId: "pool-claude", availability: "unknown",
                             windows: [win("pool-claude", "weekly", used: 100, fresh: false)]),
        ], observedAt: now)
    }

    /// Deterministic workspace for the I2 UI flow test: project `keji`, task
    /// `quota`, and plans `plan.01/02/03` where plan.03 depends on 01 and 02.
    static func createWorkspaceFixture(now: Date = Date()) -> Bundle {
        var state = StateSnapshot()
        state.settings = UserSettings.defaults(now: now)
        state.aiTools = AIToolConnection.defaults
        state.projects = [Project(id: "keji", name: "刻迹", description: "AI 工作台", icon: "⏳",
                                  color: "#5b9bd5", status: .active, createdAt: now, updatedAt: now)]
        state.tasks = [TaskItem(id: "quota", projectId: "keji", goalId: nil, title: "统一额度窗口",
                                description: "", executorType: .ai, aiProvider: nil, collaborationMode: nil,
                                status: .planned, priority: .high, estimatedMinutes: 45, dueDate: nil,
                                scheduledStart: nil, scheduledEnd: nil, createdAt: now, completedAt: nil,
                                resultSummary: nil, updatedAt: now)]
        func plan(_ id: String, _ title: String, _ deps: [String]) -> PlanItem {
            PlanItem(id: id, taskId: "quota", revision: 1, title: title, priority: 2, status: .ready,
                     criteria: ["满足验收项"], dependsOn: deps, estimatedHumanMinutes: 10, estimatedAiMinutes: 30,
                     workWeight: 1, risk: 2, executionPolicy: .balanced, createdAt: now, updatedAt: now)
        }
        state.plans = [plan("01", "采样契约", []),
                       plan("02", "三态判定", []),
                       plan("03", "领取门禁", ["01", "02"])]
        state.schemaVersion = 2
        return Bundle(state: state, dailyStats: [])
    }

    static func createSampleData(now: Date = Date()) -> Bundle {
        let cal = Format.calendar
        let human = TimeSession.humanExecutor

        /// `d.setHours(d.getHours() - h, d.getMinutes() - m)`
        func hoursAgo(_ h: Int, _ m: Int = 0) -> Date { now.addingTimeInterval(-Double(h * 3600 + m * 60)) }
        /// today at h:m:00
        func todayAt(_ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        }
        /// subDays(now, n) at h:m:00 (negative n = future)
        func daysAgo(_ n: Int, _ h: Int = 10, _ m: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -n, to: now) ?? now
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        }
        let today = Format.dayKey(now)
        let upd = daysAgo(0, 8)

        func project(_ id: String, _ name: String, _ desc: String, _ icon: String, _ color: String, _ created: Date) -> Project {
            Project(id: id, name: name, description: desc, icon: icon, color: color, status: .active, createdAt: created, updatedAt: upd)
        }
        let projects = [
            project("p1", "刻迹 App", "AI 时代个人事务与时间管理系统", "⏳", "#d4845a", daysAgo(30)),
            project("p2", "日常工作", "日常工作事务", "💼", "#6b8cae", daysAgo(60)),
            project("p3", "健身计划", "身体健康管理", "🏃", "#5a8a6a", daysAgo(45)),
            project("p4", "个人成长", "阅读与学习", "📚", "#8a7a4a", daysAgo(90)),
        ]

        func goal(_ id: String, _ pid: String, _ title: String, _ desc: String, _ target: Date, _ progress: Double) -> Goal {
            Goal(id: id, projectId: pid, title: title, description: desc, targetDate: target, progress: progress, status: .active, updatedAt: upd)
        }
        let goals = [
            goal("g1", "p1", "在 30 天内完成刻迹 MVP", "完成核心功能原型", daysAgo(-20), 65),
            goal("g2", "p1", "设计完整视觉系统", "建立品牌视觉语言", daysAgo(-10), 80),
            goal("g3", "p2", "Q2 项目交付", "按时完成季度目标", daysAgo(-45), 40),
            goal("g4", "p3", "每周运动 4 次", "保持健康体魄", daysAgo(-60), 75),
            goal("g5", "p4", "每月阅读 2 本书", "持续学习成长", daysAgo(-15), 50),
        ]

        func task(_ id: String, _ pid: String, _ gid: String?, _ title: String, _ desc: String, _ exec: ExecutorType,
                  provider: AIProvider? = nil, mode: CollaborationMode? = nil, _ status: TaskStatus, _ priority: TaskPriority,
                  _ minutes: Int, due: String? = nil, start: Date? = nil, end: Date? = nil, created: Date,
                  completed: Date? = nil, summary: String? = nil) -> TaskItem {
            TaskItem(id: id, projectId: pid, goalId: gid, title: title, description: desc, executorType: exec,
                     aiProvider: provider, collaborationMode: mode, status: status, priority: priority,
                     estimatedMinutes: minutes, dueDate: due, scheduledStart: start, scheduledEnd: end,
                     createdAt: created, completedAt: completed, resultSummary: summary, updatedAt: upd)
        }
        let tasks = [
            task("t1", "p1", "g1", "整理刻迹产品需求", "梳理核心功能与数据模型", .human, .completed, .high, 60, due: today, start: todayAt(9, 0), end: todayAt(10, 0), created: daysAgo(2, 9), completed: todayAt(9, 55), summary: "完成 PRD 初稿"),
            task("t2", "p1", "g2", "设计今日首页", "设计核心首页交互与布局", .human, .humanRunning, .high, 90, due: today, start: todayAt(10, 30), end: todayAt(12, 0), created: daysAgo(1, 14)),
            task("t3", "p1", "g1", "Claude 生成数据模型", "生成 TypeScript 类型定义", .ai, provider: .claude, mode: .aiIndependent, .aiRunning, .high, 30, due: today, start: todayAt(9, 18), created: daysAgo(1, 9, 18)),
            task("t4", "p1", "g1", "Codex 补充单元测试", "为数据层补充测试", .ai, provider: .codex, mode: .aiFirstReview, .waitingHuman, .medium, 45, due: today, start: todayAt(16, 0), created: daysAgo(1, 10), summary: "生成 12 个测试用例，全部通过"),
            task("t5", "p1", "g1", "审核 AI 生成代码", "审核 Claude 输出的数据模型", .collaboration, provider: .claude, mode: .aiFirstReview, .waitingHuman, .high, 20, due: today, start: todayAt(10, 30), created: daysAgo(1, 9, 31)),
            task("t6", "p1", "g2", "完成登录页面", "实现登录注册 UI", .collaboration, provider: .claude, mode: .humanFirstAI, .planned, .medium, 120, due: Format.dayKey(daysAgo(-2)), start: todayAt(14, 0), created: daysAgo(3)),
            task("t7", "p4", "g5", "阅读 30 分钟", "阅读《深度工作》", .human, .ready, .low, 30, due: today, start: todayAt(20, 0), created: daysAgo(1)),
            task("t8", "p3", "g4", "午间健身", "力量训练 45 分钟", .human, .planned, .medium, 45, due: today, start: todayAt(12, 30), end: todayAt(13, 15), created: daysAgo(5)),
            task("t9", "p2", "g3", "回复工作邮件", "处理收件箱", .human, .completed, .medium, 30, due: today, start: todayAt(8, 30), created: daysAgo(1, 8), completed: todayAt(8, 52)),
            task("t10", "p1", "g1", "复盘今日时间", "回顾时间分配", .human, .inbox, .low, 15, due: today, start: todayAt(21, 0), created: daysAgo(0)),
            task("t11", "p2", "g3", "产品需求整理", "整理下周需求", .human, .ready, .high, 60, due: today, start: todayAt(11, 0), created: daysAgo(2)),
            task("t12", "p1", "g1", "ChatGPT 生成文案", "生成产品介绍文案", .ai, provider: .chatgpt, .completed, .low, 15, created: daysAgo(3), completed: daysAgo(3, 15), summary: "生成 3 版文案"),
            task("t13", "p1", "g1", "数据库设计审核", "审核数据库 schema", .collaboration, provider: .claude, .completed, .high, 45, created: daysAgo(4), completed: daysAgo(4, 11)),
            task("t14", "p2", "g3", "周报撰写", "撰写本周工作周报", .human, .failed, .medium, 30, due: Format.dayKey(daysAgo(1)), created: daysAgo(2)),
            task("t15", "p1", "g1", "Gemini 分析竞品", "分析竞品功能", .ai, provider: .gemini, .cancelled, .low, 20, created: daysAgo(5)),
            task("t16", "p1", "g2", "设计底部导航", "设计 5 项底部导航", .human, .completed, .high, 60, created: daysAgo(2), completed: daysAgo(2, 16)),
            task("t17", "p3", "g4", "晨跑 5 公里", "有氧训练", .human, .completed, .medium, 35, created: daysAgo(1, 7), completed: daysAgo(1, 7, 35)),
            task("t18", "p2", "g3", "等待设计稿确认", "等待设计师反馈", .external, .waitingExternal, .medium, 0, created: daysAgo(1)),
            task("t19", "p1", "g1", "实现状态管理", "Zustand store 实现", .collaboration, provider: .codex, mode: .alternating, .paused, .high, 90, created: daysAgo(1)),
            task("t20", "p4", "g5", "写学习笔记", "整理本周阅读笔记", .human, .inbox, .low, 25, created: daysAgo(0)),
        ]

        func session(_ id: String, _ tid: String, _ type: TimeSessionType, _ exec: String, _ start: Date, _ end: Date?,
                     _ duration: Int, _ source: TimeSessionSource, _ conf: Confidence, note: String? = nil) -> TimeSession {
            TimeSession(id: id, taskId: tid, type: type, executor: exec, startedAt: start, endedAt: end,
                        durationSeconds: duration, source: source, confidence: conf, note: note, updatedAt: upd)
        }
        let timeSessions = [
            session("ts1", "t1", .humanFocus, human, todayAt(9, 0), todayAt(9, 55), 3300, .timer, .exact),
            session("ts2", "t3", .aiActive, "claude", todayAt(9, 18), todayAt(9, 35), 1020, .simulated, .exact),
            session("ts3", "t3", .waitingHuman, human, todayAt(9, 35), todayAt(9, 52), 1020, .inferred, .estimated),
            session("ts4", "t5", .humanReview, human, todayAt(9, 52), todayAt(10, 5), 780, .timer, .exact),
            session("ts5", "t2", .humanFocus, human, hoursAgo(0, 42), nil, 2520, .timer, .exact, note: "进行中"),
            session("ts6", "t3", .aiActive, "claude", hoursAgo(0, 8), nil, 480, .simulated, .exact),
            session("ts7", "t4", .aiActive, "codex", todayAt(10, 3), todayAt(10, 15), 720, .simulated, .exact),
            session("ts8", "t4", .waitingHuman, human, todayAt(10, 15), nil, 1080, .inferred, .estimated),
            session("ts9", "t9", .humanFocus, human, todayAt(8, 30), todayAt(8, 52), 1320, .timer, .exact),
            session("ts10", "t17", .humanFocus, human, daysAgo(1, 7), daysAgo(1, 7, 35), 2100, .timer, .exact),
            session("ts11", "t8", .humanFocus, human, daysAgo(1, 12, 30), daysAgo(1, 13, 15), 2700, .timer, .exact),
            session("ts12", "t13", .humanReview, human, daysAgo(4, 10, 30), daysAgo(4, 11), 1800, .timer, .exact),
            session("ts13", "t13", .aiActive, "claude", daysAgo(4, 9, 30), daysAgo(4, 10, 15), 2700, .simulated, .exact),
            session("ts14", "t2", .interruption, human, todayAt(10, 20), todayAt(10, 25), 300, .manual, .exact, note: "收到消息"),
            session("ts15", "t19", .rework, human, daysAgo(1, 15), daysAgo(1, 15, 30), 1800, .manual, .estimated),
            session("ts16", "t12", .aiActive, "chatgpt", daysAgo(3, 14), daysAgo(3, 14, 12), 720, .simulated, .exact),
            session("ts17", "t16", .humanFocus, human, daysAgo(2, 15), daysAgo(2, 16), 3600, .timer, .exact),
            session("ts18", "t18", .waitingExternal, TimeSession.externalExecutor, daysAgo(1, 10), nil, 86400, .inferred, .estimated),
            session("ts19", "t6", .aiActive, "claude", daysAgo(2, 14), daysAgo(2, 14, 45), 2700, .simulated, .exact),
            session("ts20", "t6", .humanFocus, human, daysAgo(2, 13), daysAgo(2, 13, 40), 2400, .timer, .exact),
            session("ts21", "t1", .humanFocus, human, daysAgo(2, 9), daysAgo(2, 10), 3600, .timer, .exact),
            session("ts22", "t3", .aiActive, "claude", daysAgo(2, 10, 5), daysAgo(2, 10, 30), 1500, .simulated, .exact),
            session("ts23", "t11", .humanFocus, human, daysAgo(3, 11), daysAgo(3, 12), 3600, .timer, .exact),
            session("ts24", "t7", .humanFocus, human, daysAgo(3, 20), daysAgo(3, 20, 30), 1800, .timer, .exact),
            session("ts25", "t4", .aiActive, "codex", daysAgo(4, 16), daysAgo(4, 16, 20), 1200, .simulated, .exact),
            session("ts26", "t5", .waitingAI, "claude", daysAgo(5, 9), daysAgo(5, 9, 15), 900, .inferred, .estimated),
            session("ts27", "t2", .humanFocus, human, daysAgo(5, 14), daysAgo(5, 15, 30), 5400, .timer, .exact),
            session("ts28", "t9", .humanFocus, human, daysAgo(6, 8, 30), daysAgo(6, 9), 1800, .timer, .exact),
            session("ts29", "t17", .humanFocus, human, daysAgo(6, 7), daysAgo(6, 7, 35), 2100, .timer, .exact),
            session("ts30", "t8", .humanFocus, human, daysAgo(6, 12, 30), daysAgo(6, 13, 10), 2400, .timer, .exact),
        ]

        func log(_ t: String, _ m: String) -> AIExecutionLog { AIExecutionLog(time: t, message: m) }
        func exec(_ id: String, _ tid: String, _ provider: AIProvider, _ model: String, _ status: AIExecutionStatus,
                  _ start: Date, _ end: Date?, _ active: Int, waiting: Int = 0, _ tin: Int, _ tout: Int, _ cost: Double,
                  _ tools: Int, _ files: Int, summary: String? = nil, error: String? = nil, step: String? = nil,
                  _ logs: [AIExecutionLog]) -> AIExecution {
            AIExecution(id: id, taskId: tid, provider: provider, model: model, status: status, startedAt: start,
                        endedAt: end, activeSeconds: active, elapsedSeconds: active, waitingHumanSeconds: waiting,
                        tokenInput: tin, tokenOutput: tout, estimatedCost: cost, toolCallCount: tools,
                        filesChanged: files, resultSummary: summary, errorMessage: error, logs: logs,
                        currentStep: step, updatedAt: upd)
        }
        let aiExecutions = [
            exec("ai1", "t3", .claude, "claude-sonnet-4", .running, hoursAgo(0, 8), nil, 480, 12400, 3200, 0.18, 8, 3,
                 step: "修改 Task 类型定义",
                 [log(Format.time(hoursAgo(0, 8)), "读取项目结构"), log(Format.time(hoursAgo(0, 6)), "分析数据模型"),
                  log(Format.time(hoursAgo(0, 4)), "修改 Task 类型")]),
            exec("ai2", "t4", .codex, "gpt-4o", .completed, todayAt(10, 3), todayAt(10, 15), 720, 8600, 4100, 0.24, 12, 5,
                 summary: "生成 12 个测试用例，全部通过",
                 [log("10:03", "分析现有代码"), log("10:05", "生成测试用例"), log("10:09", "运行测试"),
                  log("10:11", "测试失败，修复类型错误"), log("10:13", "测试通过")]),
            exec("ai3", "t13", .claude, "claude-sonnet-4", .completed, daysAgo(4, 9, 30), daysAgo(4, 10, 15), 2700, 15200, 6800, 0.32, 6, 2,
                 summary: "数据库 schema 设计完成",
                 [log("09:30", "分析需求"), log("09:45", "生成 schema"), log("10:10", "完成")]),
            exec("ai4", "t12", .chatgpt, "gpt-4o", .completed, daysAgo(3, 14), daysAgo(3, 14, 12), 720, 3200, 2800, 0.08, 0, 0,
                 summary: "生成 3 版产品介绍文案", [log("14:00", "生成文案"), log("14:10", "完成")]),
            exec("ai5", "t6", .claude, "claude-sonnet-4", .completed, daysAgo(2, 14), daysAgo(2, 14, 45), 2700, 9800, 5200, 0.22, 10, 4,
                 summary: "登录页面组件生成完成",
                 [log("14:00", "生成组件"), log("14:30", "样式调整"), log("14:45", "完成")]),
            exec("ai6", "t14", .codex, "gpt-4o", .failed, daysAgo(2, 16), daysAgo(2, 16, 10), 600, 4200, 800, 0.06, 3, 0,
                 error: "上下文不足，无法生成完整周报", [log("16:00", "尝试生成"), log("16:08", "失败：上下文不足")]),
            exec("ai7", "t19", .codex, "gpt-4o", .cancelled, daysAgo(1, 14), daysAgo(1, 14, 20), 1200, waiting: 300, 6800, 2400, 0.14, 5, 2,
                 [log("14:00", "开始实现"), log("14:15", "用户取消")]),
            exec("ai8", "t15", .gemini, "gemini-2.0", .cancelled, daysAgo(5, 11), daysAgo(5, 11, 5), 300, 2100, 600, 0.02, 1, 0,
                 [log("11:00", "开始分析"), log("11:05", "已取消")]),
        ]

        let dailyStats: [DailyStats] = (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: -(6 - i), to: now) ?? now
            return DailyStats(date: Format.dayKey(day),
                              humanSeconds: 7200 + i * 600 + Int.random(in: 0..<1800),
                              aiActiveSeconds: 5400 + i * 400 + Int.random(in: 0..<1200),
                              waitingSeconds: 1200 + Int.random(in: 0..<1800),
                              deepWorkSeconds: 3600 + i * 300,
                              interruptionCount: 2 + Int.random(in: 0..<4),
                              reworkSeconds: 600 + Int.random(in: 0..<900),
                              completedTasks: 3 + Int.random(in: 0..<4),
                              plannedMinutes: 360 + i * 20,
                              actualHumanMinutes: 140 + i * 15 + Int.random(in: 0..<30))
        }

        let experiments = [
            EfficiencyExperiment(id: "e1", title: "明天上午 9:00–11:00 开启免打扰模式", description: "减少中断，提升深度工作时间",
                                 startDate: daysAgo(-1), durationDays: 7, status: .active, beforeMetric: "深度工作 1.2h/天",
                                 afterMetric: "深度工作 1.8h/天", effective: true, updatedAt: upd),
            EfficiencyExperiment(id: "e2", title: "每天固定两次 AI 审核时段", description: "10:30 和 16:00 集中审核 AI 输出",
                                 startDate: daysAgo(3), durationDays: 14, status: .active, beforeMetric: "平均等待 42 分钟",
                                 afterMetric: "平均等待 18 分钟", effective: true, updatedAt: upd),
            EfficiencyExperiment(id: "e3", title: "开发任务预估 ×1.4", description: "根据历史数据调整预估",
                                 startDate: daysAgo(-7), durationDays: 14, status: .planned, beforeMetric: "计划准确率 58%",
                                 afterMetric: nil, effective: nil, updatedAt: upd),
        ]

        let settings = UserSettings(name: "刻迹用户", weeklyTimeGoalHours: 40, workStartHour: 9, workEndHour: 18,
                                    defaultFocusMinutes: 45, streakDays: 12, theme: .light, updatedAt: upd)
        let aiTools = [
            AIToolConnection(provider: .claude, name: "Claude Code", connected: true, lastSync: hoursAgo(0, 1)),
            AIToolConnection(provider: .codex, name: "Codex CLI", connected: true, lastSync: hoursAgo(0, 2)),
            AIToolConnection(provider: .chatgpt, name: "ChatGPT", connected: false),
            AIToolConnection(provider: .gemini, name: "Gemini", connected: false),
        ]
        let focus = ActiveFocus(taskId: "t2", startedAt: hoursAgo(0, 42), accumulatedSeconds: 2520)

        let state = StateSnapshot(projects: projects, goals: goals, tasks: tasks, timeSessions: timeSessions,
                                  aiExecutions: aiExecutions, experiments: experiments, settings: settings,
                                  aiTools: aiTools, activeFocus: focus)
        return Bundle(state: state, dailyStats: dailyStats)
    }
}
