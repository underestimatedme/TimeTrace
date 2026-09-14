import { useEffect, useId, useRef } from 'react'
import type { ReactNode } from 'react'
import { ArrowLeftIcon, CaretRightIcon, XIcon } from '@phosphor-icons/react'

export function GlassSheet({title, children, close}: {title:string;children:ReactNode;close:()=>void}) {
  const dialog = useRef<HTMLDialogElement>(null)
  const id = useId()
  useEffect(() => { const element=dialog.current; element?.showModal(); return () => element?.close() }, [])
  return <dialog className="gl-sheet" ref={dialog} onCancel={close} aria-labelledby={id}>
    <header><h2 id={id}>{title}</h2><button className="gl-icon" aria-label="关闭弹窗" onClick={close}><XIcon size={21}/></button></header>
    <div className="gl-sheet-content">{children}</div>
  </dialog>
}
export function PageTitle({title, subtitle, back, action}: {title:string;subtitle?:string;back?:()=>void;action?:ReactNode}) {
  return <header className="gl-page-title">{back && <button className="gl-back" onClick={back}><ArrowLeftIcon size={18}/>返回</button>}<div><h1>{title}</h1>{action}</div>{subtitle && <p>{subtitle}</p>}</header>
}
export function MenuRow({icon, title, detail, onClick, danger=false}: {icon:ReactNode;title:string;detail?:string;onClick:()=>void;danger?:boolean}) {
  return <button className={`gl-menu-row ${danger?'danger':''}`} onClick={onClick}><span className="gl-menu-icon">{icon}</span><span><b>{title}</b>{detail && <small>{detail}</small>}</span><CaretRightIcon size={17}/></button>
}
export function Toggle({label, detail, checked, change}: {label:string;detail?:string;checked:boolean;change:(v:boolean)=>void}) {
  return <div className="gl-toggle-row"><div><b>{label}</b>{detail && <p>{detail}</p>}</div><button type="button" className="gl-toggle" role="switch" aria-label={label} aria-checked={checked} onClick={()=>change(!checked)}><span/></button></div>
}
export function Empty({title, detail, action}: {title:string;detail:string;action?:ReactNode}) { return <div className="gl-empty"><h2>{title}</h2><p>{detail}</p>{action}</div> }
