import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useStore } from '@/store/useStore'
import { applyTheme } from '@/lib/themes'
import { AppearancePage } from '@/pages/Appearance'
import { SplashPage } from '@/pages/Splash'
import { OnboardingPage } from '@/pages/Onboarding'
import { TodayPage } from '@/pages/Today'
import { TasksPage } from '@/pages/Tasks'
import { TimelinePage } from '@/pages/Timeline'
import { InsightsPage } from '@/pages/Insights'
import { ProfilePage } from '@/pages/Profile'
import { TaskCreatePage } from '@/pages/TaskCreate'
import { TaskDetailPage } from '@/pages/TaskDetail'
import { FocusPage } from '@/pages/Focus'
import { AIExecutionPage } from '@/pages/AIExecution'
import { ProjectsPage, ProjectDetailPage, GoalDetailPage } from '@/pages/Projects'
import { AIToolsPage } from '@/pages/AITools'

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const hasOnboarded = useStore((s) => s.hasOnboarded)
  if (!hasOnboarded) return <Navigate to="/onboarding" replace />
  return <>{children}</>
}

export default function App() {
  const tickAIExecutions = useStore((s) => s.tickAIExecutions)
  const theme = useStore((s) => s.settings.theme)

  useEffect(() => {
    applyTheme(theme ?? 'claude')
  }, [theme])

  useEffect(() => {
    const interval = setInterval(tickAIExecutions, 1000)
    return () => clearInterval(interval)
  }, [tickAIExecutions])

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<SplashPage />} />
        <Route path="/onboarding" element={<OnboardingPage />} />
        <Route path="/today" element={<ProtectedRoute><TodayPage /></ProtectedRoute>} />
        <Route path="/tasks" element={<ProtectedRoute><TasksPage /></ProtectedRoute>} />
        <Route path="/tasks/new" element={<ProtectedRoute><TaskCreatePage /></ProtectedRoute>} />
        <Route path="/tasks/:id" element={<ProtectedRoute><TaskDetailPage /></ProtectedRoute>} />
        <Route path="/timeline" element={<ProtectedRoute><TimelinePage /></ProtectedRoute>} />
        <Route path="/insights" element={<ProtectedRoute><InsightsPage /></ProtectedRoute>} />
        <Route path="/profile" element={<ProtectedRoute><ProfilePage /></ProtectedRoute>} />
        <Route path="/focus/:id" element={<ProtectedRoute><FocusPage /></ProtectedRoute>} />
        <Route path="/ai/:id" element={<ProtectedRoute><AIExecutionPage /></ProtectedRoute>} />
        <Route path="/projects" element={<ProtectedRoute><ProjectsPage /></ProtectedRoute>} />
        <Route path="/projects/:id" element={<ProtectedRoute><ProjectDetailPage /></ProtectedRoute>} />
        <Route path="/goals/:id" element={<ProtectedRoute><GoalDetailPage /></ProtectedRoute>} />
        <Route path="/ai-tools" element={<ProtectedRoute><AIToolsPage /></ProtectedRoute>} />
        <Route path="/appearance" element={<ProtectedRoute><AppearancePage /></ProtectedRoute>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
