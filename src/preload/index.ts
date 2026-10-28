import { contextBridge, ipcRenderer } from 'electron'
import type { IpcRendererEvent } from 'electron'
import type {
  AboutInfo,
  IpcApi,
  ProcessMemorySample,
  SamplerConfig,
  SamplingStatus,
  SnapshotOptions
} from '../shared/types'

const api: IpcApi = {
  getHdcPath: () => ipcRenderer.invoke('hdc:getPath'),
  setHdcPath: (path: string) => ipcRenderer.invoke('hdc:setPath', path),
  getSessionsDir: () => ipcRenderer.invoke('settings:getSessionsDir'),
  chooseSessionsDir: () => ipcRenderer.invoke('settings:chooseSessionsDir'),
  setSessionsDir: (dir: string) => ipcRenderer.invoke('settings:setSessionsDir', dir),
  listDevices: () => ipcRenderer.invoke('device:list'),
  setTarget: (targetId: string) => ipcRenderer.invoke('device:setTarget', targetId),
  getDeviceInfo: () => ipcRenderer.invoke('device:info'),
  listApps: () => ipcRenderer.invoke('app:list'),
  startSampling: (config: SamplerConfig, bundleName: string, appLabel: string, persist?: boolean, taskName?: string) =>
    ipcRenderer.invoke('sampling:start', config, bundleName, appLabel, persist, taskName),
  stopSampling: () => ipcRenderer.invoke('sampling:stop'),
  takeSnapshot: (bundleName: string, appLabel: string, taskName?: string, options?: SnapshotOptions) =>
    ipcRenderer.invoke('snapshot:take', bundleName, appLabel, taskName, options),
  loadSnapshot: (dir: string) => ipcRenderer.invoke('snapshot:load', dir),
  onSample: (cb: (s: ProcessMemorySample) => void) => {
    const listener = (_e: IpcRendererEvent, s: ProcessMemorySample): void => cb(s)
    ipcRenderer.on('sampling:sample', listener)
    return () => ipcRenderer.removeListener('sampling:sample', listener)
  },
  onSamplingStatus: (cb: (s: SamplingStatus) => void) => {
    const listener = (_e: IpcRendererEvent, s: SamplingStatus): void => cb(s)
    ipcRenderer.on('sampling:status', listener)
    return () => ipcRenderer.removeListener('sampling:status', listener)
  },
  openSession: () => ipcRenderer.invoke('session:open'),
  listSessions: () => ipcRenderer.invoke('session:list'),
  openSessionDir: (dir: string) => ipcRenderer.invoke('session:openDir', dir),
  deleteSession: (dir: string) => ipcRenderer.invoke('session:delete', dir),
  renameSession: (dir: string, taskName: string) =>
    ipcRenderer.invoke('session:rename', dir, taskName),
  getSessionDir: () => ipcRenderer.invoke('session:getDir'),
  revealPath: (path: string) => ipcRenderer.invoke('shell:revealPath', path),
  openReportWindow: (dir: string) => ipcRenderer.invoke('report:open', dir),
  openCompareWindow: (dirs: string[]) => ipcRenderer.invoke('compare:open', dirs),
  onShowAbout: (cb: (info: AboutInfo) => void) => {
    const listener = (_e: IpcRendererEvent, info: AboutInfo): void => cb(info)
    ipcRenderer.on('app:about', listener)
    return () => ipcRenderer.removeListener('app:about', listener)
  }
}

contextBridge.exposeInMainWorld('api', api)