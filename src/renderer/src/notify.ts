import { Modal } from 'antd'

/** 去掉 IPC 抛错自带的前缀（Error invoking remote method 'xxx': Error: ...），只保留真实错误描述 */
export function errText(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e)
  return raw.replace(/^Error invoking remote method '[^']+':\s*(Error:\s*)?/, '')
}

/** 统一的弹窗式报错与提示（替代顶部横幅式 message） */
export const notify = {
  error(title: string, e: unknown): void {
    Modal.error({ title, content: errText(e), okText: '知道了' })
  },
  info(title: string, content?: string): void {
    Modal.info({ title, content, okText: '知道了' })
  },
  success(title: string, content?: string): void {
    Modal.success({ title, content, okText: '知道了' })
  }
}
