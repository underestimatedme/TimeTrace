import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { ArrowLeft, ArrowUpRight, Check, ChevronRight, Circle, Clock3, Download, FolderOpen, GitBranch, LayoutDashboard, ListChecks, Pause, Play, Radio, Sparkles, X, BarChart3 } from 'lucide-react'
import logo from '../../logo.png'
import { initialPlans, pages, tools } from './data'
import type { Page, Plan } from './data'
import './review.css'

const icons = [LayoutDashboard, FolderOpen, GitBranch, Sparkles, BarChart3]
const captions: Record<Page, string[]> = {
  today: ['版本目标始终可见', '人工审核与 AI 执行各有位置', '点击推荐工作，查看 Plan 分派'],
  projects: ['点击项目，逐层进入任务与 Plan', '每个 Plan 都有独立验收条件', '目标进度按已验收范围计算'],
  timeline: ['切换项目与执行轨道', '等待区间不计入 AI 活跃时间', '未来安排与历史事件分开呈现'],
  ai: ['可切换零付费自动续跑', '模拟到期，查看正常与周限额分支', '公共信号只能触发个人额度核验'],
  reports: ['评分可展开查看依据', '验收会更新已验收 Plan 数量', '导出一份带证据的演示日报'],
}

function Tag({ children, tone = '' }: { children: ReactNode; tone?: string }) { return <span className={`rv-tag ${tone}`}>{children}</span> }
function Section({ title, action, onClick }: { title: string; action?: string; onClick?: () => void }) { return <div className="rv-section"><h2>{title}</h2>{action && <button onClick={onClick}>{action}<ChevronRight size={13} /></button>}</div> }
function Modal({ title, children, close }: { title: string; children: ReactNode; close: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { ref.current?.showModal() }, [])
  return <dialog className="rv-modal" ref={ref} onCancel={close}><div className="rv-modal-head"><span>刻迹 / {title}</span><button aria-label="关闭详情" onClick={close}><X size={20} /></button></div>{children}</dialog>
}

export function WorkspaceReview() {
  const [page, setPage] = useState<Page>('today')
  const [level, setLevel] = useState(0)
  const [project, setProject] = useState('刻迹')
  const [selected, setSelected] = useState<string | null>(null)
  const [plans, setPlans] = useState(initialPlans)
  const [autoResume, setAutoResume] = useState(true)
  const [weekBlocked, setWeekBlocked] = useState(false)
  const [restored, setRestored] = useState(false)
  const [filter, setFilter] = useState('全部项目')
  const [lane, setLane] = useState('全部')
  const [notice, setNotice] = useState('')
  const [policy, setPolicy] = useState('均衡')
  const [chosen, setChosen] = useState('Codex')
  const [info, setInfo] = useState<'score' | 'evidence' | 'profile' | null>(null)
  const active = pages.find(p => p.id === page)!
  const plan = plans.find(p => p.id === selected)
  const accepted = plans.filter(p => p.status === '已验收').length
  const nextReview = plans.find(p => p.status === '待验收')
  useEffect(() => { if (!notice) return; const timer = setTimeout(() => setNotice(''), 5000); return () => clearTimeout(timer) }, [notice])
  function navigate(next: Page) { setPage(next); setLevel(0); document.querySelector('.rv-phone')?.scrollTo({ top: 0 }) }
  function openPlan(p: Plan) { setSelected(p.id); setChosen(p.tool) }
  function updatePlan(status: Plan['status']) {
    const quotaBlocked = status === '执行中' && chosen === 'Claude Code' && (!restored || weekBlocked)
    setPlans(items => items.map(p => p.id === selected ? { ...p, status: quotaBlocked ? '等待额度' : status, tool: chosen } : p))
    setSelected(null)
    setNotice(quotaBlocked ? '指定工具额度不足，已进入等待，不会转为付费执行' : status === '已验收' ? '验收已记录，项目进度与日报已更新' : '演示队列已更新，可在项目中查看')
  }
  function simulateReset() {
    if (weekBlocked) { setRestored(false); setNotice('短时额度已恢复，但周额度耗尽，继续等待'); return }
    setRestored(true)
    if (!autoResume) { setNotice('额度已恢复；自动续跑关闭，等待手动继续'); return }
    setPlans(items => items.map(p => p.status === '等待额度' ? { ...p, status: '执行中' } : p))
    setNotice('已核验订阅额度：原 Claude 会话继续执行，无额外付费')
  }
  function exportReport() {
    const report = `# 刻迹开发日报 · 2026-09-14\n\n演示数据，不代表真实开发成果。\n\n目标：本周交付 v1.2\n已验收 Plan：${accepted}/3\n\n${plans.map(p => `- ${p.title}：${p.status}（${p.tool}）`).join('\n')}\n\n证据示例：quota-window.spec，3 项验收条件；仅供交互评审。\n新增付费：¥0（模拟）\n生产力分为示意数据，真实评分需历史样本。\n`
    const url = URL.createObjectURL(new Blob([report], { type: 'text/markdown;charset=utf-8' }))
    const a = document.createElement('a'); a.href = url; a.download = 'keji-demo-changelog-2026-09-14.md'; a.click(); URL.revokeObjectURL(url)
    setNotice('演示日报已导出')
  }
  return <div className="rv-board">
    <aside className="rv-intro"><a className="rv-brand" href="/review"><img src={logo} alt="刻迹 Logo" /><b>刻迹<span>KEJI · DESIGN REVIEW</span></b></a><div className="rv-edition">PRODUCT EXPLORATION / 02</div><h1>{active.title}</h1><p>个人与 AI 的<br />多项目工作台</p><div className="rv-rail">{pages.map((p, i) => <button key={p.id} className={p.id === page ? 'active' : ''} onClick={() => navigate(p.id)}><span>0{i + 1}</span>{p.label}<ArrowUpRight size={16} /></button>)}</div><footer>SEPTEMBER 2026<br />iOS INTERACTIVE PROTOTYPE</footer></aside>
    <div className="rv-phone">
      <div className="rv-status"><b>14:08</b><span>◖◖ ▰</span></div>
      <div className="rv-demo"><span className="rv-dot" />交互设计稿 · 全部为演示数据</div>
      <header className="rv-header"><div><p>{active.eyebrow}</p><h1>{page === 'today' ? '今天，一起推进。' : active.label}</h1></div><button className="rv-avatar" aria-label="账号与运行环境" onClick={() => setInfo('profile')}>J</button></header>
      <main className="rv-content">
      {page === 'today' && <>
        <button className="rv-goal" onClick={() => { navigate('projects'); setProject('刻迹'); setLevel(1) }}><div className="rv-row"><span className="rv-eyebrow">本周的重点</span><Tag tone="amber">周五交付</Tag></div><h2>刻迹 v1.2<span>让多个 AI 有序协作</span></h2><div className="rv-goal-foot"><span>目标范围 · {accepted}/3 Plan 已验收</span><ArrowUpRight size={20} /></div><div className="rv-progress"><i style={{ width: `${accepted / 3 * 100}%` }} /></div></button>
        <div className="rv-mini-tools">{tools.slice(0, 3).map(t => <button key={t.name} onClick={() => navigate('ai')}><span className={`rv-tool-dot ${t.color}`}>{t.glyph}</span><b>{t.name === 'Claude Code' ? 'Claude' : t.name}</b><small>{t.name === 'Claude Code' ? restored ? '额度已恢复' : '22m 后核验' : `${t.remaining}% 剩余`}</small></button>)}</div>
        <Section title="你现在最值得做的事" />
        <button className="rv-action-card" onClick={() => { if (nextReview) openPlan(nextReview); else { navigate('projects'); setProject('刻迹'); setLevel(2) } }}><div className="rv-row"><Tag tone="blue">{nextReview ? '需要你' : '下一步'}</Tag><span className="rv-muted">{nextReview ? '预计 10 分钟' : `${accepted}/3 已验收`}</span></div><h3>{nextReview ? `验收：${nextReview.title}` : '查看下一步安排'}</h3><p>{nextReview ? '解锁后续界面联调，推进本周版本目标。' : '已完成当前验收，查看依赖和 AI 执行进展。'}</p><div className="rv-row rv-card-bottom"><span>刻迹 / 多 AI 额度管理</span><span className="rv-round-arrow"><ArrowUpRight size={18} /></span></div></button>
        <Section title="AI 工作动态" action="时间线" onClick={() => navigate('timeline')} />
        <button className="rv-work-row" onClick={() => openPlan(plans[1])}><span className="rv-tool-dot amber">✳</span><div><b>额度卡片与倒计时</b><p>Claude Code · {plans[1].status}</p></div><Tag tone="amber">{plans[1].status === '执行中' ? '续跑中' : '14:30'}</Tag></button>
        <button className="rv-work-row" onClick={() => { navigate('projects'); setProject('Valley'); setLevel(1) }}><span className="rv-tool-dot blue">C</span><div><b>整理 API 验证结果</b><p>Valley · Codex · Mac mini</p></div><Radio size={17} className="rv-blue-text" /></button>
        <div className="rv-note"><Clock3 size={16} /><p>AI 等待额度时，你可以先完成验收。<br /><span>今天的节奏，由交付目标决定。</span></p></div>
      </>}
      {page === 'projects' && <>
        {level === 0 ? <><div className="rv-row rv-overview"><span>3 个进行中项目</span><Tag>本周</Tag></div>{[{ name: '刻迹', version: 'v1.2', detail: '多 AI 工作台与额度管理', date: '周五 · 9 月 18 日', color: 'amber', count: `${accepted}/3 Plan 已验收` }, { name: 'Valley', version: 'v2.4', detail: '远程执行稳定性优化', date: '周四 · 9 月 17 日', color: 'blue', count: '1 个任务执行中' }, { name: '个人网站', version: 'v1.1', detail: '开发故事与项目展示', date: '下周 · 9 月 23 日', color: 'violet', count: '尚未安排今日工作' }].map((p, i) => <button className="rv-project" key={p.name} onClick={() => { setProject(p.name); setLevel(1) }}><div className="rv-row"><span className={`rv-project-icon ${p.color}`}><FolderOpen size={22} /></span><Tag>{p.version}</Tag></div><h2>{p.name}</h2><p>{p.detail}</p><div className="rv-row"><small>{p.date}</small><ChevronRight size={17} /></div><div className="rv-project-line" /><small>0{i + 1} / {p.count}</small></button>)}</> : <>
          <button className="rv-back" onClick={() => setLevel(level - 1)}><ArrowLeft size={15} />{level === 1 ? '全部项目' : project}</button>
          <div className="rv-detail-title"><span className="rv-eyebrow">{project} / {level === 1 ? '版本目标' : '任务'}</span><h2>{level === 1 ? project === '刻迹' ? '本周交付 v1.2' : `${project}本周交付` : '多 AI 额度管理'}</h2><p>{level === 1 ? '范围明确，每一步都有验收依据。' : '统一展示各工具账号的可用额度与恢复时间。'}</p></div>
          {project !== '刻迹' ? <div className="rv-empty"><FolderOpen /><h3>项目概览示例</h3><p>当前原型的完整交互集中在刻迹项目。</p><button className="rv-primary" onClick={() => { setProject('刻迹'); setLevel(1) }}>查看刻迹完整流程</button></div> : level === 1 ? <><div className="rv-summary"><div><b>{accepted}<small>/ 3</small></b><span>已验收 Plan</span></div><div><b>4 <small>天</small></b><span>距离目标</span></div></div><Section title="目标范围" /><button className="rv-task" onClick={() => setLevel(2)}><div className="rv-row"><Tag tone="amber">P1</Tag><span>优先分 86 · 示例</span></div><h3>多 AI 额度管理</h3><p>3 个 Plan · {accepted} 个已验收</p><ChevronRight size={18} /></button><div className="rv-note"><ListChecks size={19} /><p>验收条件<br /><span>额度准确展示；限额后可以安全续跑；新增付费为零。</span></p></div></> : <><div className="rv-row"><Tag tone="amber">P1 · 目标关键路径</Tag><button className="rv-text-button" onClick={() => setInfo('score')}>评分依据 ↗</button></div><Section title="执行计划" />{plans.map((p, i) => <button className="rv-plan" onClick={() => openPlan(p)} key={p.id}><span className="rv-plan-index">{p.status === '已验收' ? <Check size={17} /> : `0${i + 1}`}</span><div><h3>{p.title}</h3><p>{p.tool} · 预计 {p.minutes}m</p><Tag tone={p.status === '已验收' ? 'green' : p.status === '等待额度' ? 'amber' : 'blue'}>{p.status}</Tag></div><ChevronRight size={15} /></button>)}<div className="rv-note"><GitBranch size={17} /><p>Plan 03 等待前两项验收。<br /><span>优先级不会越过依赖关系。</span></p></div></>}
        </>}
      </>}
      {page === 'timeline' && <>
        <div className="rv-row"><h2>9 月 14 日 <small>周一</small></h2><select aria-label="筛选项目" value={filter} onChange={e => setFilter(e.target.value)}>{['全部项目', '刻迹', 'Valley'].map(v => <option key={v}>{v}</option>)}</select></div>
        <div className="rv-segments">{['全部', '我', 'AI'].map(v => <button key={v} className={lane === v ? 'active' : ''} onClick={() => setLane(v)}>{v}</button>)}</div>
        <div className="rv-lane-head"><span>时间</span>{lane !== 'AI' && <b>我</b>}{lane !== '我' && <b>AI 工作</b>}</div>
        <div className={`rv-timeline ${lane === '全部' ? '' : 'single'}`}>
          {['13:00', '13:30', '14:00', '14:30', '15:00'].map((t, i) => <div className="rv-time-row" key={t} style={{ top: i * 102 }}><span>{t}</span></div>)}
          {lane !== 'AI' && <div className="rv-human-lane"><button className="rv-time-block human" style={{ top: 0, height: 86 }} onClick={() => setNotice('演示记录：13:00–13:25，需求梳理，人工投入 25m')}><b>梳理版本范围</b><small>我 · 25m</small></button><button className="rv-time-block future" style={{ top: 265, height: 78 }} onClick={() => openPlan(plans[0])}><b>验收模型</b><small>我 · 计划 10m</small></button></div>}
          {lane !== '我' && <div className="rv-ai-lane">{filter !== 'Valley' && <><button className="rv-time-block blue" style={{ top: 0, height: 100 }} onClick={() => openPlan(plans[0])}><b>额度数据模型</b><small>Codex · 刻迹</small><span>运行 35m → 待验收</span></button><button className={`rv-time-block ${restored && !weekBlocked && autoResume ? 'amber' : 'waiting'}`} style={{ top: 117, height: 164 }} onClick={() => navigate('ai')}><b>额度卡片</b><small>Claude · 刻迹</small><span>{restored && !weekBlocked && autoResume ? '已恢复 · 原会话续跑' : '等待额度恢复'}</span><span>预计 14:30 核验</span></button></>}{filter !== '刻迹' && <button className="rv-time-block violet future" style={{ top: 321, height: 93 }} onClick={() => setNotice('Valley / API 验证 · 演示安排在独立 Mac mini 执行')}><b>API 验证</b><small>Codex · Valley</small><span>另一台电脑 · 计划</span></button>}</div>}
          <div className="rv-now" style={{ top: 231 }}><span>14:08</span><i /></div>
        </div><div className="rv-legend"><span><i className="human" />人工</span><span><i className="blue" />AI 执行</span><span><i className="waiting" />等待</span><span><i className="future" />计划</span></div><p className="rv-footnote">固定演示时间 · 已投入 25m 人工 / 35m AI，分别统计。</p>
      </>}
      {page === 'ai' && <>
        <div className="rv-resume"><div><span className="rv-eyebrow">额度恢复后</span><h2>自动接着做</h2><p>原会话续跑 · 不额外付费</p></div><button role="switch" aria-label="额度恢复后自动续跑" aria-checked={autoResume} className={`rv-switch ${autoResume ? 'on' : ''}`} onClick={() => setAutoResume(!autoResume)}><span /></button></div>
        <Section title="我的 AI 账号" />{tools.map(t => <article className="rv-quota" key={t.name}><div className="rv-row"><div className="rv-quota-name"><span className={`rv-tool-dot ${t.color}`}>{t.glyph}</span><div><h3>{t.name}</h3><small>个人账号 · {t.capability}</small></div></div><Tag tone={t.color}>{t.name === 'Claude Code' && restored ? '已核验' : t.status}</Tag></div><div className="rv-quota-meter"><b>{t.name === 'Claude Code' && restored ? '100' : t.remaining ?? '—'}<small>{t.remaining === null ? '' : '%'}</small></b><span>{t.name === 'Claude Code' && restored ? '短时额度已恢复' : t.reset}</span></div><div className={`rv-progress ${t.color}`}><i style={{ width: `${t.name === 'Claude Code' && restored ? 100 : t.remaining ?? 0}%` }} /></div><p>{t.name === 'Claude Code' && weekBlocked ? '周额度已耗尽 · 本周窗口仍阻塞执行' : t.name === 'Claude Code' && restored ? '短时剩余 100% · 周剩余 28%' : t.detail}</p><small className="rv-muted">{t.remaining === null ? '尚未同步' : '演示样本 · 14:07 更新'}</small></article>)}
        <Section title="公共重置信号" /><a className="rv-signal" href="https://betteropc.com/ai-products/reset-signals" target="_blank" rel="noreferrer"><div className="rv-row"><Tag>BetterOPC</Tag><ArrowUpRight size={16} /></div><h3>公共重置与活动动态</h3><p>查看原始信号；账号额度另行核验。</p><small>原型未接入实时数据</small></a>
        <details className="rv-simulation"><summary>Review：模拟额度恢复</summary><label><input type="checkbox" checked={weekBlocked} onChange={e => { setWeekBlocked(e.target.checked); setRestored(false); setPlans(p => p.map(item => item.id === '02' ? { ...item, status: '等待额度' } : item)) }} />周额度也已耗尽</label><button className="rv-primary" onClick={simulateReset}>模拟到期并核验</button></details>
      </>}
      {page === 'reports' && <>
        <div className="rv-row rv-report-date"><h2>今天的开发报告</h2><button aria-label="导出演示日报" className="rv-icon-button" onClick={exportReport}><Download size={19} /></button></div><p className="rv-muted">2026.09.14 · Asia/Dubai · 草稿</p>
        <button className="rv-score" onClick={() => setInfo('score')}><div><span className="rv-eyebrow">生产力 · 示例评分</span><b>82<small>/100</small></b><p>重点目标有推进，质量优先。</p></div><div className="rv-score-ring"><ArrowUpRight size={28} /></div></button>
        <div className="rv-summary"><div><b>{accepted}<small>/ 3</small></b><span>刻迹已验收 Plan</span></div><div><b>¥0</b><span>新增付费 · 演示</span></div></div>
        <Section title="刻迹 · v1.2" /><div className="rv-changelog"><span className="rv-eyebrow">CHANGELOG</span>{plans.map(p => <button key={p.id} onClick={() => openPlan(p)}><span className={`rv-log-mark ${p.status === '已验收' ? 'green' : ''}`}>{p.status === '已验收' ? <Check size={14} /> : <Circle size={12} />}</span><div><h3>{p.title}</h3><p>{p.status} · {p.tool}</p></div><ChevronRight size={15} /></button>)}<button className="rv-evidence" onClick={() => setInfo('evidence')}><GitBranch size={15} />查看提交与验证证据<ArrowUpRight size={14} /></button></div>
        <Section title="明日建议" /><div className="rv-note"><Sparkles size={18} /><p>先完成额度卡片验收，再进行恢复测试。<br /><span>如果周额度不足，保留原会话并先推进可用工具的独立任务。</span></p></div><p className="rv-footnote">评分与时间为设计示意。已验收 Plan 数量随本次交互更新；刷新页面重置。</p>
      </>}
      </main>
      <nav className="rv-bottom" aria-label="主导航">{pages.map((p, i) => { const Icon = icons[i]; return <button key={p.id} className={p.id === page ? 'active' : ''} aria-current={p.id === page ? 'page' : undefined} onClick={() => navigate(p.id)}><Icon size={21} strokeWidth={1.6} /><span>{p.label}</span></button> })}</nav>
      {notice && <div className="rv-toast" role="status">{notice}</div>}
    </div>
    <aside className="rv-annotations"><span className="rv-eyebrow">DESIGN NOTES</span><h2>{active.label}<span> / 0{pages.findIndex(p => p.id === page) + 1}</span></h2><p>{active.description}</p><ol>{captions[page].map(c => <li key={c}>{c}</li>)}</ol><div className="rv-palette"><i /><i /><i /></div><small>深海蓝 · 时间琥珀 · AI 冰蓝<br />沿用最新 Logo 的色彩关系</small><div className="rv-review-note"><b>本轮 review 重点</b><p>导航是否顺手？目标与 Plan 是否清晰？额度恢复后，你是否知道系统会做什么？</p></div><a href="/legacy">查看上一版设计 ↗</a></aside>
    {plan && <Modal title="Plan 详情" close={() => setSelected(null)}><div className="rv-modal-body"><span className="rv-eyebrow">刻迹 / 多 AI 额度管理 / PLAN {plan.id}</span><h2>{plan.title}</h2><div className="rv-row"><Tag tone="amber">{plan.priority}</Tag><Tag>{plan.status}</Tag><span className="rv-muted">预计 {plan.minutes}m</span></div><Section title="验收条件" /><ul className="rv-checklist">{plan.criteria.map(c => <li key={c}><ListChecks size={16} />{c}</li>)}</ul><Section title="交给谁完成" /><div className="rv-segments">{['均衡', '速度优先', '节省额度', '手动'].map(v => <button className={policy === v ? 'active' : ''} key={v} onClick={() => { setPolicy(v); if (v !== '手动') setChosen(plan.status !== '待执行' ? plan.tool : 'Codex') }}>{v}</button>)}</div><label className="rv-select-label">执行工具<select value={chosen} disabled={plan.status !== '待执行'} onChange={e => { setChosen(e.target.value); setPolicy('手动') }}><option>Codex</option><option>Claude Code</option></select></label><div className="rv-reason"><Sparkles size={17} /><p>{plan.status !== '待执行' ? '已有执行上下文，保持原工具与会话。' : policy === '速度优先' ? '演示推荐 Codex：当前可执行，减少等待。' : policy === '节省额度' ? '演示推荐 Codex：使用现有订阅额度，不产生新增付费。' : policy === '手动' ? `已手动指定 ${chosen}，启动前仍检查额度和依赖。` : '演示推荐 Codex：有可用额度，适合先完成当前验证工作。'}<span>推荐规则示例 · 尚无真实历史样本</span></p></div><Section title="执行约束" /><p className="rv-muted">零额外付费 · 本机凭据 · 同 Plan 单次执行</p>{plan.id === '03' && <p className="rv-warning">依赖：Plan 01、02 均通过验收后才可派发。</p>}
        <button className="rv-primary" disabled={plan.status === '已验收' || (plan.status === '等待额度' && (!restored || weekBlocked)) || (plan.id === '03' && plans.slice(0, 2).some(p => p.status !== '已验收'))} onClick={() => updatePlan(plan.status === '待验收' ? '已验收' : plan.status === '执行中' ? '待验收' : '执行中')}>{plan.status === '待验收' ? <Check size={17} /> : plan.status === '等待额度' ? <Pause size={17} /> : <Play size={17} />}{plan.status === '待验收' ? '确认验收通过' : plan.status === '已验收' ? '已验收' : plan.status === '等待额度' ? restored && !weekBlocked ? '手动继续原会话' : '等待额度恢复' : plan.status === '执行中' ? '模拟执行完成，进入验收' : '按此安排执行'}</button><p className="rv-footnote">所有操作仅更新当前设计稿，不调用真实 AI。</p></div></Modal>}
    {info && <Modal title={info === 'score' ? '评分依据' : info === 'profile' ? '账号与环境' : '成果证据'} close={() => setInfo(null)}><div className="rv-modal-body"><h2>{info === 'score' ? '三种分数，三种用途。' : info === 'profile' ? '你的工作环境' : '每项成果，都有出处。'}</h2>{info === 'score' ? <><p>以下是建议的初始规则，示例数值不代表真实生产力。</p><Section title="先做什么 · 任务优先分" /><p>目标贡献 35% + 截止紧迫度 30% + 解锁价值 20% + 等待时长 15%。P0–P3 人工优先级在前，组内按分数排序。</p><Section title="交给谁 · AI 适配" /><p>能力、可用额度、等待时间、上下文复用及历史验收表现。样本不足明确标注，不比较不同厂商的额度百分比。</p><Section title="产出怎样 · 生产力" /><p>目标贡献 45% + 验收质量 30% + 计划兑现 15% + 资源效率 10%。不按代码行数和 Token 数奖励。</p><p className="rv-warning">当前 82 分是静态布局示例，真实评分需足够数据覆盖率。</p></> : info === 'profile' ? <><p>Joey · 个人工作台</p><div className="rv-note">MacBook Pro / 刻迹仓库<br />Mac mini / Valley 仓库</div><p>电脑、账号和额度分别显示状态。原型连接均为示例，没有读取本机凭据。</p></> : <><Tag tone="blue">演示证据</Tag><Section title="额度数据模型" /><p>验证文件：quota-window.spec<br />验收：短时/周窗口、未知状态、重复采样<br />状态：{plans[0].status}</p><p>实际产品将关联真实 commit、PR 和测试报告。此处未生成虚构的 Git 链接。</p></>}</div></Modal>}
  </div>
}
