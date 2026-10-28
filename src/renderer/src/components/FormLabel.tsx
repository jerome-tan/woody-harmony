import { Typography } from 'antd'

/** 表单横向行标签的固定宽度（峰值采样 / 快照 / 实时查看 / TargetPicker 共用，保证整表对齐） */
export const FORM_LABEL_W = 88

interface Props {
  text: string
  required?: boolean
}

/** 表单标签：必填星号占独立槽位（固定 10px，不参与文字排版），所有行的文字左缘对齐 */
export default function FormLabel({ text, required }: Props): JSX.Element {
  return (
    <Typography.Text
      type="secondary"
      style={{ flex: `0 0 ${FORM_LABEL_W}px`, fontSize: 12.5, paddingTop: 6 }}
    >
      <span style={{ display: 'inline-block', width: 10, color: '#ff4d4f' }}>
        {required ? '*' : ''}
      </span>
      {text}
    </Typography.Text>
  )
}
