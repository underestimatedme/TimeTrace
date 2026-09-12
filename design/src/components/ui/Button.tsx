import { forwardRef, type ButtonHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'default' | 'secondary' | 'ghost' | 'danger' | 'accent'
  size?: 'sm' | 'md' | 'lg'
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = 'default', size = 'md', ...props }, ref) => {
    const variants = {
      default: 'bg-bg-card text-text border border-border hover:bg-bg-hover',
      secondary: 'bg-bg-elevated text-text-secondary hover:text-text hover:bg-bg-hover',
      ghost: 'text-text-secondary hover:text-text hover:bg-bg-hover',
      danger: 'bg-danger/20 text-danger border border-danger/30 hover:bg-danger/30',
      accent: 'bg-accent text-bg font-medium hover:bg-accent-dim',
    }
    const sizes = {
      sm: 'px-3 py-1.5 text-xs rounded-lg',
      md: 'px-4 py-2.5 text-sm rounded-xl',
      lg: 'px-6 py-3 text-base rounded-xl',
    }
    return (
      <button
        ref={ref}
        className={cn(
          'inline-flex items-center justify-center gap-2 transition-colors disabled:opacity-50 disabled:pointer-events-none',
          variants[variant],
          sizes[size],
          className
        )}
        {...props}
      />
    )
  }
)
Button.displayName = 'Button'
