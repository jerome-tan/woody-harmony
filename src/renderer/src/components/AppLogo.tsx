import { useId } from 'react'

/** 应用 Logo（与 build/icon.svg 同稿）；useId 保证同页多个实例的渐变 id 不冲突 */
export default function AppLogo({ size = 30, radius = 8 }: { size?: number; radius?: number }): JSX.Element {
  const uid = useId().replace(/[^a-zA-Z0-9]/g, '')
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 256 256"
      style={{ borderRadius: radius, flex: '0 0 auto', display: 'block' }}
    >
      <defs>
        <linearGradient id={`bg${uid}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ede9fe" />
          <stop offset="1" stopColor="#c4b5fd" />
        </linearGradient>
        <linearGradient id={`body${uid}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#a78bfa" />
          <stop offset="1" stopColor="#7c3aed" />
        </linearGradient>
      </defs>
      <rect width="256" height="256" rx="56" fill={`url(#bg${uid})`} />
      <path d="M124 64 Q132 34 112 22 Q140 36 140 66 Z" fill="#6d28d9" />
      <circle cx="128" cy="144" r="76" fill={`url(#body${uid})`} />
      <circle cx="100" cy="124" r="24" fill="#ffffff" />
      <circle cx="156" cy="124" r="24" fill="#ffffff" />
      <circle cx="104" cy="128" r="12" fill="#3b0764" />
      <circle cx="152" cy="128" r="12" fill="#3b0764" />
      <circle cx="108" cy="123" r="4" fill="#ffffff" />
      <circle cx="156" cy="123" r="4" fill="#ffffff" />
      <path d="M118 150 L138 150 L128 188 Z" fill="#fbbf24" />
    </svg>
  )
}
