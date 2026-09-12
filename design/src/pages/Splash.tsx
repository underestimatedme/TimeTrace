import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

export function SplashPage() {
  const navigate = useNavigate()

  useEffect(() => {
    const timer = setTimeout(() => navigate('/onboarding'), 2500)
    return () => clearTimeout(timer)
  }, [navigate])

  return (
    <div
      className="app-shell flex flex-col items-center justify-center px-8 cursor-pointer"
      onClick={() => navigate('/onboarding')}
    >
      <div className="time-tick w-24 mb-12" />
      <h1 className="text-4xl font-light text-text tracking-widest mb-3">刻迹</h1>
      <p className="text-sm text-text-secondary mb-16">让每一刻，都留下痕迹。</p>
      <div className="absolute bottom-16 text-center">
        <p className="text-xs text-text-muted leading-relaxed">
          管理你的时间，也管理替你工作的 AI。
        </p>
        <p className="text-xs text-text-muted mt-4 animate-pulse-soft">点击进入</p>
      </div>
    </div>
  )
}
