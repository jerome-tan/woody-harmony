import { useRef, useState } from 'react'

/**
 * - 右缘拖拽调整列宽（colResizable）
 * - 拖拽整个表头调整列顺序（colDraggable）；固定列不可拖
 */
interface Props extends React.ThHTMLAttributes<HTMLTableCellElement> {
  colKey?: string
  colResizable?: boolean
  colDraggable?: boolean
  /** 列最小宽度（不小于表头标题文本长度） */
  colMinWidth?: number
  onColResize?: (key: string, width: number) => void
  onColReorder?: (from: string, to: string) => void
}

export default function ResizableHeaderCell(props: Props): JSX.Element {
  const {
    colKey,
    colResizable,
    colDraggable,
    colMinWidth,
    onColResize,
    onColReorder,
    style,
    children,
    ...rest
  } = props
  const [dragOver, setDragOver] = useState(false)
  // 拖拽结束后吞掉紧随其后的 click，避免误触表头排序
  const resizingRef = useRef(false)

  const startResize = (e: React.MouseEvent): void => {
    if (!colKey || !onColResize) return
    e.preventDefault()
    e.stopPropagation()
    const th = (e.currentTarget as HTMLElement).closest('th')
    if (!th) return
    const startX = e.clientX
    const startW = th.getBoundingClientRect().width
    const minW = colMinWidth ?? 56
    let moved = false
    const onMove = (ev: MouseEvent): void => {
      moved = true
      onColResize(colKey, Math.max(minW, Math.round(startW + ev.clientX - startX)))
    }
    const onUp = (): void => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
      if (moved) {
        resizingRef.current = true
        setTimeout(() => {
          resizingRef.current = false
        }, 0)
      }
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }

  return (
    <th
      {...rest}
      onClickCapture={(e) => {
        if (resizingRef.current) {
          e.preventDefault()
          e.stopPropagation()
        }
      }}
      style={{
        ...style,
        position: 'relative',
        ...(dragOver ? { background: '#e6f4ff' } : {})
      }}
      draggable={colDraggable}
      onDragStart={(e) => {
        if (!colKey) return
        e.dataTransfer.setData('text/plain', colKey)
        e.dataTransfer.effectAllowed = 'move'
      }}
      onDragOver={(e) => {
        if (!colDraggable) return
        e.preventDefault()
        e.dataTransfer.dropEffect = 'move'
        setDragOver(true)
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        setDragOver(false)
        if (!colDraggable) return
        const from = e.dataTransfer.getData('text/plain')
        if (from && colKey && from !== colKey) onColReorder?.(from, colKey)
      }}
    >
      {children}
      {colResizable && (
        <span
          onMouseDown={startResize}
          style={{
            position: 'absolute',
            right: -4,
            top: 0,
            bottom: 0,
            width: 9,
            cursor: 'col-resize',
            zIndex: 2
          }}
        />
      )}
    </th>
  )
}
