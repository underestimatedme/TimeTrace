import { cn } from '@/lib/utils'
import type { InputHTMLAttributes, TextareaHTMLAttributes, SelectHTMLAttributes } from 'react'

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        'w-full bg-bg-elevated border border-border rounded-xl px-4 py-2.5 text-sm text-text placeholder:text-text-muted focus:outline-none focus:border-accent/50 transition-colors',
        className
      )}
      {...props}
    />
  )
}

export function Textarea({ className, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        'w-full bg-bg-elevated border border-border rounded-xl px-4 py-2.5 text-sm text-text placeholder:text-text-muted focus:outline-none focus:border-accent/50 transition-colors resize-none',
        className
      )}
      {...props}
    />
  )
}

export function Select({ className, children, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        'w-full bg-bg-elevated border border-border rounded-xl px-4 py-2.5 text-sm text-text focus:outline-none focus:border-accent/50 transition-colors appearance-none',
        className
      )}
      {...props}
    >
      {children}
    </select>
  )
}

export function Label({ className, children, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return (
    <label className={cn('block text-xs text-text-secondary mb-1.5', className)} {...props}>
      {children}
    </label>
  )
}

export function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mb-4">
      <Label>{label}</Label>
      {children}
    </div>
  )
}
