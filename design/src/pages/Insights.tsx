import { useState } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, LineChart, Line, CartesianGrid, Legend,
  AreaChart, Area,
} from 'recharts'
import { AppLayout, PageLayout } from '@/components/layout/Layout'
import { Card } from '@/components/ui/Card'
import { SectionTitle, MetricCard } from '@/components/ui/Common'
import { useStore } from '@/store/useStore'
import {
  aggregateDailyStats, generateInsights, getTimeLeverage, getPlanAccuracy,
} from '@/lib/stats'
import { formatDuration, formatLeverage, formatPercent } from '@/lib/format'
import { cn } from '@/lib/utils'

type Tab = 'today' | 'week' | 'trend'

const COLORS = [
  'var(--color-accent)',
  'var(--color-ai)',
  'var(--color-warning)',
  'var(--color-success)',
  'var(--color-danger)',
]
const GRID = 'var(--color-border)'
const AXIS = 'var(--color-text-muted)'

export function InsightsPage() {
  const { dailyStats, timeSessions, tasks, aiExecutions, experiments } = useStore()
  const [tab, setTab] = useState<Tab>('today')

  const todayStats = dailyStats[dailyStats.length - 1]
  const weekStats = aggregateDailyStats(dailyStats, 7)
  const stats = tab === 'today' ? todayStats : weekStats

  const leverage = getTimeLeverage(stats?.humanSeconds || 0, stats?.aiActiveSeconds || 0)
  const planAccuracy = getPlanAccuracy(stats?.plannedMinutes || 0, stats?.actualHumanMinutes || 0)

  const chartData = dailyStats.map((d) => ({
    date: d.date.slice(5),
    human: Math.round(d.humanSeconds / 60),
    ai: Math.round(d.aiActiveSeconds / 60),
    waiting: Math.round(d.waitingSeconds / 60),
    deepWork: Math.round(d.deepWorkSeconds / 60),
    planned: d.plannedMinutes,
    actual: d.actualHumanMinutes,
  }))

  const distribution = [
    { name: '人工专注', value: stats?.humanSeconds || 0 },
    { name: 'AI 活跃', value: stats?.aiActiveSeconds || 0 },
    { name: '等待', value: stats?.waitingSeconds || 0 },
    { name: '深度工作', value: stats?.deepWorkSeconds || 0 },
    { name: '返工', value: stats?.reworkSeconds || 0 },
  ].filter((d) => d.value > 0)

  const insights = generateInsights(timeSessions, tasks, dailyStats, aiExecutions)

  return (
    <AppLayout>
      <PageLayout>
        <h1 className="text-xl font-medium text-text mb-4">洞察</h1>

        <div className="flex gap-2 mb-6">
          {([
            { key: 'today' as Tab, label: '今日' },
            { key: 'week' as Tab, label: '本周' },
            { key: 'trend' as Tab, label: '趋势' },
          ]).map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={cn(
                'px-4 py-1.5 rounded-full text-xs transition-colors',
                tab === t.key ? 'bg-accent/20 text-accent' : 'bg-bg-card text-text-secondary'
              )}
            >
              {t.label}
            </button>
          ))}
        </div>

        {tab !== 'trend' && stats && (
          <>
            <div className="grid grid-cols-2 gap-2 mb-6">
              <MetricCard label="人工投入" value={formatDuration(stats.humanSeconds)} />
              <MetricCard label="AI 活跃" value={formatDuration(stats.aiActiveSeconds)} />
              <MetricCard label="等待时间" value={formatDuration(stats.waitingSeconds)} />
              <MetricCard label="深度工作" value={formatDuration(stats.deepWorkSeconds)} />
              <MetricCard label="中断次数" value={`${stats.interruptionCount}`} />
              <MetricCard label="完成任务" value={`${stats.completedTasks}`} />
              <MetricCard label="时间杠杆" value={formatLeverage(leverage)} />
              <MetricCard label="计划准确率" value={formatPercent(planAccuracy)} />
            </div>

            <SectionTitle>时间分类分布</SectionTitle>
            <Card className="mb-6 h-48">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie data={distribution} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={40} outerRadius={70}>
                    {distribution.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v) => formatDuration(Number(v))} />
                </PieChart>
              </ResponsiveContainer>
            </Card>
          </>
        )}

        {(tab === 'week' || tab === 'trend') && (
          <>
            <SectionTitle>人工 vs AI 时间对比</SectionTitle>
            <Card className="mb-6 h-52">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke={GRID} />
                  <XAxis dataKey="date" tick={{ fill: AXIS, fontSize: 10 }} />
                  <YAxis tick={{ fill: AXIS, fontSize: 10 }} />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="human" name="人工(分)" fill="var(--color-accent)" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="ai" name="AI(分)" fill="var(--color-ai)" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </Card>

            <SectionTitle>计划 vs 实际时间</SectionTitle>
            <Card className="mb-6 h-52">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke={GRID} />
                  <XAxis dataKey="date" tick={{ fill: AXIS, fontSize: 10 }} />
                  <YAxis tick={{ fill: AXIS, fontSize: 10 }} />
                  <Tooltip />
                  <Legend />
                  <Line type="monotone" dataKey="planned" name="计划(分)" stroke="var(--color-warning)" strokeWidth={2} dot={false} />
                  <Line type="monotone" dataKey="actual" name="实际(分)" stroke="var(--color-accent)" strokeWidth={2} dot={false} />
                </LineChart>
              </ResponsiveContainer>
            </Card>

            <SectionTitle>等待时间趋势</SectionTitle>
            <Card className="mb-6 h-48">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke={GRID} />
                  <XAxis dataKey="date" tick={{ fill: AXIS, fontSize: 10 }} />
                  <YAxis tick={{ fill: AXIS, fontSize: 10 }} />
                  <Tooltip />
                  <Area type="monotone" dataKey="waiting" name="等待(分)" fill="var(--color-warning)" stroke="var(--color-warning)" fillOpacity={0.3} />
                </AreaChart>
              </ResponsiveContainer>
            </Card>

            <SectionTitle>深度工作趋势</SectionTitle>
            <Card className="mb-6 h-48">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke={GRID} />
                  <XAxis dataKey="date" tick={{ fill: AXIS, fontSize: 10 }} />
                  <YAxis tick={{ fill: AXIS, fontSize: 10 }} />
                  <Tooltip />
                  <Line type="monotone" dataKey="deepWork" name="深度工作(分)" stroke="var(--color-success)" strokeWidth={2} />
                </LineChart>
              </ResponsiveContainer>
            </Card>
          </>
        )}

        <SectionTitle>AI 洞察建议</SectionTitle>
        <div className="space-y-3 mb-6">
          {insights.map((insight, i) => (
            <Card key={i} className="border-accent/10">
              <p className="text-sm text-text-secondary leading-relaxed">{insight}</p>
            </Card>
          ))}
        </div>

        <SectionTitle>效率实验</SectionTitle>
        <div className="space-y-3">
          {experiments.map((exp) => (
            <Card key={exp.id}>
              <div className="flex items-start justify-between mb-2">
                <h3 className="text-sm font-medium text-text">{exp.title}</h3>
                <span className={cn(
                  'text-xs px-2 py-0.5 rounded-full',
                  exp.status === 'active' ? 'bg-success/20 text-success' :
                  exp.status === 'planned' ? 'bg-accent/20 text-accent' : 'bg-text-muted/20 text-text-muted'
                )}>
                  {exp.status === 'active' ? '进行中' : exp.status === 'planned' ? '计划中' : '已完成'}
                </span>
              </div>
              <p className="text-xs text-text-muted mb-2">{exp.description}</p>
              <div className="flex gap-4 text-xs">
                <span className="text-text-secondary">实验前: {exp.beforeMetric}</span>
                {exp.afterMetric && <span className="text-success">实验后: {exp.afterMetric}</span>}
              </div>
            </Card>
          ))}
        </div>
      </PageLayout>
    </AppLayout>
  )
}
