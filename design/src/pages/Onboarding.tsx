import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { useStore } from '@/store/useStore'
import { cn } from '@/lib/utils'

const slides = [
  {
    title: '看见时间去了哪里',
    description: '自动记录投入、等待、切换与返工。',
    icon: '◐',
  },
  {
    title: '安排你与 AI 的工作',
    description: '把任务交给自己、Claude、Codex 或其他执行者。',
    icon: '◎',
  },
  {
    title: '让每一次改变都能被验证',
    description: '刻迹会根据真实数据分析效率，并持续优化你的工作方式。',
    icon: '◉',
  },
]

export function OnboardingPage() {
  const [current, setCurrent] = useState(0)
  const navigate = useNavigate()
  const completeOnboarding = useStore((s) => s.completeOnboarding)

  const handleStart = (useSample: boolean) => {
    completeOnboarding(useSample)
    navigate('/today')
  }

  const isLast = current === slides.length - 1

  return (
    <div className="app-shell flex flex-col px-6 py-12">
      <div className="flex-1 flex flex-col items-center justify-center">
        <div className="text-5xl mb-8 opacity-60">{slides[current].icon}</div>
        <h2 className="text-xl font-medium text-text text-center mb-3">
          {slides[current].title}
        </h2>
        <p className="text-sm text-text-secondary text-center leading-relaxed max-w-[280px]">
          {slides[current].description}
        </p>
      </div>

      <div className="flex justify-center gap-2 mb-8">
        {slides.map((_, i) => (
          <button
            key={i}
            onClick={() => setCurrent(i)}
            className={cn(
              'w-2 h-2 rounded-full transition-all',
              i === current ? 'bg-accent w-6' : 'bg-border'
            )}
          />
        ))}
      </div>

      <div className="space-y-3">
        {isLast ? (
          <>
            <Button variant="accent" size="lg" className="w-full" onClick={() => handleStart(false)}>
              开始使用
            </Button>
            <Button variant="secondary" size="lg" className="w-full" onClick={() => handleStart(true)}>
              使用示例数据体验
            </Button>
          </>
        ) : (
          <Button variant="accent" size="lg" className="w-full" onClick={() => setCurrent(current + 1)}>
            继续
          </Button>
        )}
      </div>
    </div>
  )
}
