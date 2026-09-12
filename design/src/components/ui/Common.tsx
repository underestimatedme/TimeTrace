import { cn } from '@/lib/utils'

export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon?: React.ReactNode
  title: string
  description?: string
  action?: React.ReactNode
}) {
  return (
    <div className="flex flex-col items-center justify-center py-12 px-6 text-center">
      {icon && <div className="text-3xl mb-4 opacity-50">{icon}</div>}
      <h3 className="text-sm font-medium text-text mb-1">{title}</h3>
      {description && <p className="text-xs text-text-muted mb-4">{description}</p>}
      {action}
    </div>
  )
}

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string
  subtitle?: string
  action?: React.ReactNode
}) {
  return (
    <div className="flex items-start justify-between mb-6">
      <div>
        <h1 className="text-xl font-medium text-text">{title}</h1>
        {subtitle && <p className="text-sm text-text-secondary mt-0.5">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

export function SectionTitle({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <h2 className={cn('text-xs font-medium text-text-secondary uppercase tracking-wider mb-3', className)}>
      {children}
    </h2>
  )
}

export function ProgressBar({ value, className }: { value: number; className?: string }) {
  return (
    <div className={cn('h-1 bg-bg-elevated rounded-full overflow-hidden', className)}>
      <div
        className="h-full bg-accent rounded-full transition-all duration-500"
        style={{ width: `${Math.min(100, Math.max(0, value))}%` }}
      />
    </div>
  )
}

export function MetricCard({
  label,
  value,
  sub,
  className,
}: {
  label: string
  value: string
  sub?: string
  className?: string
}) {
  return (
    <div className={cn('bg-bg-card rounded-xl border border-border p-3', className)}>
      <p className="text-xs text-text-muted mb-1">{label}</p>
      <p className="text-lg font-medium text-text font-mono">{value}</p>
      {sub && <p className="text-xs text-text-secondary mt-0.5">{sub}</p>}
    </div>
  )
}
