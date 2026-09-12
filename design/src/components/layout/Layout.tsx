import { NavLink } from 'react-router-dom'
import { Calendar, ListTodo, GitBranch, BarChart3, User } from 'lucide-react'
import { cn } from '@/lib/utils'

const navItems = [
  { to: '/today', icon: Calendar, label: '今日' },
  { to: '/tasks', icon: ListTodo, label: '任务' },
  { to: '/timeline', icon: GitBranch, label: '时间流' },
  { to: '/insights', icon: BarChart3, label: '洞察' },
  { to: '/profile', icon: User, label: '我的' },
]

export function BottomNav() {
  return (
    <nav className="fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-[430px] bg-bg-elevated/95 backdrop-blur-md border-t border-border z-50">
      <div className="flex items-stretch pb-[env(safe-area-inset-bottom)]">
        {navItems.map(({ to, icon: Icon, label }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              cn(
                'flex flex-1 flex-col items-center justify-center gap-0.5 py-2 min-w-0 transition-colors',
                isActive ? 'text-accent' : 'text-text-muted'
              )
            }
          >
            <Icon size={20} strokeWidth={1.5} className="shrink-0" />
            <span className="text-[10px] leading-none truncate max-w-full px-0.5">{label}</span>
          </NavLink>
        ))}
      </div>
    </nav>
  )
}

export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="app-shell flex flex-col">
      <main className="flex-1 scroll-area pb-20 px-4 pt-safe">
        {children}
      </main>
      <BottomNav />
    </div>
  )
}

export function PageLayout({ children, noPadding }: { children: React.ReactNode; noPadding?: boolean }) {
  return (
    <div className={cn('animate-fade-in', !noPadding && 'pt-4')}>
      {children}
    </div>
  )
}
