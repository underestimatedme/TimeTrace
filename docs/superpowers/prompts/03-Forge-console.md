# 子任务 03 · Forge 刻迹运营后台（全新）

> 先读 `00-总纲.md`，本文件只讲 Forge 端特有的部分。

---

## 你负责什么

在 Forge 里**从零新建**刻迹（TimeTrace）的运营 / 管理控制台。
这是三个仓库里唯一的 greenfield —— Forge 目前**没有任何刻迹代码**。

数据全部来自 Valley 的 `/admin/timetrace/*` 接口（由子任务 `02-` 负责实现）。

---

## 工程现状

```
仓库    /opt/coding/planb/github/Forge
分支    从 main 新建，建议 codex/timetrace-console
```

技术栈（**严格沿用，不要引入新框架**）：

```
@refinedev/core      5.0.12
@refinedev/antd      6.0.3
@refinedev/react-router 2.0.4
antd                 5.29.3
react / react-dom    19.2.7
react-router         7.18.2
axios                1.18.0
lucide-react         1.17.0
vite                 8.0.16   typescript 6.0.3
```

```
src/App.tsx              Refine 根组件，dataProvider 映射表在这里
src/resources.ts         资源与菜单定义
src/menuIcons.tsx        侧边栏图标映射
src/providers/
  http.ts                axios 实例 + API_URL
  valleyDataProvider.ts  makeValleyDataProvider(basePath, resourcePaths)
  authProvider.ts / accessControlProvider.ts / identity.ts / upload.ts
src/pages/
  continenttrail/  hairtrace/  ieltsbuddy/  momobird/  platform/  resource/  system/
  LoginPage.tsx
test/                    node --test（--experimental-strip-types）
```

**参照 `src/pages/continenttrail/`** —— 它是「一个 Valley App 的运营后台」最完整的
现成范例（概览 / 用户 / 业务对象 / 内容 / 审计五类页面齐全）。

---

## 接口契约

`makeValleyDataProvider` 已经处理了 Valley 的信封：

```
列表：{ code: "OK", data: { list: [...], total: N } }
单条：{ code: "OK", data: {...} }
```

它把 Refine 的分页 / 排序 / 过滤翻译成查询参数：
`page` / `pageSize` / `orderBy` / `order` + 扁平化的 filter 字段。

你要做的：

```ts
// src/providers/...  或在 App.tsx 里
const timetraceDataProvider = makeValleyDataProvider("/admin/timetrace");
```

然后在 `App.tsx` 的 dataProvider 映射表里加一项，在 `resources.ts` 里加一组
`TIMETRACE_RESOURCES`，照 `CONTINENTTRAIL_RESOURCES` 的写法：

```ts
export const TIMETRACE_RESOURCES: ResourceProps[] = [
  { name: "timetrace", meta: { label: "刻迹" } },
  { name: "timetrace-dashboard", list: "/timetrace",
    meta: { label: "运营概览", parent: "timetrace", dataProviderName: "timetrace" } },
  // users / projects / tasks / plans / runners / remote-jobs / quota / reports / feedback …
];
```

**接口清单与 `02-Valley-backend.md` 对齐，开工前先跟后端确认最终形状。**
后端没好之前可以用固定 fixture 开发，但 fixture 必须严格按约定的 JSON 形状，
**包括 `null` 出现的位置**。

---

## 页面规划（与后端资源一一对应）

| 页面 | 内容 |
| --- | --- |
| 运营概览 | 用户数、活跃项目、执行中 Plan、额度告警、近 7 日趋势 |
| 用户管理 | 列表 + 详情：账号、设备、绑定的 Runner |
| 项目 / 任务 / Plan | 三级下钻，Plan 详情展示工具、策略、依赖、验收条件与状态 |
| Runner 管理 | 在线状态、能力清单（inventory）、租约健康度 |
| 远程作业 | Job / Attempt / Event 时间轴，用于排障 |
| 额度 | 各工具周限额、消耗、共享池状态、告警 |
| 报告 | 日报列表与详情（**注意 null 处理，见下**） |
| 反馈 | 用户反馈列表 + 处理状态流转（这是少数几个写操作之一） |

---

## 两条不能违反的规则

### 1. `null` 不是 0

后端 `phase-facts-v2` 会返回 `null`（完整说明见 `00-总纲.md`）：

```jsonc
{
  "human_seconds": null,          // 该轨道有未知区间 → 不可测量
  "ai_seconds": 3600,
  "waiting_seconds": null,
  "estimated_value_minor": null,  // 目前恒为 null，没有金额测量来源
  "actual_spend_minor": null
}
```

后台是**运营看数据做决策**的地方，这里把未知显示成 0 的危害比 App 里更大。

- `null` → 渲染成「未测量」「数据不足」之类的明确文案（antd 里用 `<Text type="secondary">`）
- **不得** `?? 0`、不得参与求和 / 平均 / 百分比
- 图表遇到 `null` 要断线或留空，**不要连成 0 值的谷底** ——
  那会让运营看到一个根本不存在的「产出暴跌」
- 样本不足时不显示总分

### 2. 后台是只读为主

刻迹的核心价值是「执行事实可信」。运营后台**不得**提供修改用户执行事实、
验收结果、额度记录的入口 —— 这些是审计证据。

只开放确实需要的写操作（如反馈状态流转）。如果你觉得某个地方运营需要改数据，
**先问，不要直接做**。

---

## 视觉

Forge 用 antd，**不要**把刻迹 App 的玻璃风格照搬进来 —— 后台要跟 Forge 其他
模块保持一致，用 antd 默认体系。

从 `design/` 需要继承的只有**概念与命名**：
「项目 / 任务 / Plan」三级、「我 / AI / 等待」三轨、「结果待确认」这个状态措辞、
工具额度四层级。术语要和 App 端完全一致，否则运营和用户对不上话。

---

## 必须跑的验证命令

```bash
cd /opt/coding/planb/github/Forge

npm install
npx tsc -b                 # 类型检查
npm run build              # 构建
npm run dev                # 本地起服务实际点一遍
node --no-warnings --experimental-strip-types --test test/timetrace-*.test.ts
```

测试文件命名照 `test/momobird-*.test.ts` 的风格，
并在 `package.json` 里加一条 `test:timetrace` 脚本。

**实际打开浏览器点一遍主要页面**，尤其验证：
`null` 字段显示为「未测量」而不是 0；图表在 `null` 处断开。

---

## 完成标准

- [ ] `timetrace` dataProvider + 资源 + 菜单接入，侧边栏出现「刻迹」分组
- [ ] 上表页面全部可用，三级下钻通畅
- [ ] `null` 全链路正确渲染（列表、详情、图表），无 `?? 0`
- [ ] 写操作范围克制，无篡改执行事实 / 验收 / 额度的入口
- [ ] 术语与 App 端一致（三级模型、三轨、「结果待确认」、四层级额度）
- [ ] `npx tsc -b`、`npm run build`、`node --test` 全绿并贴出真实输出
- [ ] 浏览器实测截图或操作记录
- [ ] 变更说明 + 遗留问题清单
