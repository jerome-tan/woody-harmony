import React from 'react'
import ReactDOM from 'react-dom/client'
import { ConfigProvider } from 'antd'
import zhCN from 'antd/locale/zh_CN'
import App from './App'
import CompareApp from './CompareApp'
import ReportApp from './ReportApp'
import 'antd/dist/reset.css'

// 独立窗口路由：?mode=compare 渲染对比视图，?mode=report 渲染单报告视图，否则为主窗口
const mode = new URLSearchParams(window.location.search).get('mode')

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <ConfigProvider locale={zhCN}>
      {mode === 'compare' ? <CompareApp /> : mode === 'report' ? <ReportApp /> : <App />}
    </ConfigProvider>
  </React.StrictMode>
)
