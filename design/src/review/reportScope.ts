import type { GlassPlan } from './glassModel'

export function plansForReport(plans:GlassPlan[], tasks:{id:string;projectId:string}[], projectId:string|null) {
  if(projectId===null)return plans
  const taskIds=new Set(tasks.filter(t=>t.projectId===projectId).map(t=>t.id))
  return plans.filter(p=>taskIds.has(p.taskId))
}
