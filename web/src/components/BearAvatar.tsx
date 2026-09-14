import type { BearAccessory } from '../data/roster'

/**
 * 占位熊头像 —— 与地图同一套画风：均匀深棕描边、平涂、无渐变。
 * 三只熊共用一个画法，只换毛色 / 耳内色 / 配件，所以五只熊看得出是一家人。
 * 美术组的真立绘到位后，把这个组件换成 <img> 即可。
 */

const INK = '#5B3A26'

function Accessory({ kind }: { kind: BearAccessory }) {
  switch (kind) {
    case 'glasses':
      return (
        <g fill="none" stroke={INK} strokeWidth="2.4">
          <circle cx="39" cy="49" r="8.5" fill="rgba(255,255,255,0.35)" />
          <circle cx="61" cy="49" r="8.5" fill="rgba(255,255,255,0.35)" />
          <path d="M47.5 49h5" />
        </g>
      )
    case 'collar':
      return (
        <g stroke={INK} strokeWidth="2.4" strokeLinejoin="round">
          <path d="M36 78 L50 68 L64 78 L50 86 Z" fill="#F2E3C2" />
          <path d="M50 74 L56 78 L50 84 L44 78 Z" fill="#B94A32" />
        </g>
      )
    case 'headset':
      return (
        <g stroke={INK} strokeWidth="2.4">
          <path d="M20 46 A30 30 0 0 1 80 46" fill="none" />
          <rect x="12" y="44" width="11" height="17" rx="5" fill="#E08A3C" />
          <rect x="77" y="44" width="11" height="17" rx="5" fill="#E08A3C" />
        </g>
      )
    case 'brow':
      // 粗眉 —— 比胡子在小尺寸下更读得出来，且不会糊住口鼻
      return (
        <g stroke={INK} strokeWidth="3.4" strokeLinecap="round" fill="none">
          <path d="M33 42 L45 40" />
          <path d="M67 42 L55 40" />
        </g>
      )
    case 'cap':
      return (
        <g stroke={INK} strokeWidth="2.4" strokeLinejoin="round">
          <path d="M24 34 A26 26 0 0 1 76 34 Z" fill="#7CBF4A" />
          <rect x="20" y="32" width="60" height="8" rx="4" fill="#639922" />
          <circle cx="50" cy="16" r="5" fill="#F2E3C2" />
        </g>
      )
    default:
      return null
  }
}

export function BearAvatar({
  fur,
  inner,
  accessory,
  size = 72,
}: {
  fur: string
  inner: string
  accessory: BearAccessory
  size?: number
}) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" aria-hidden="true">
      {/* 耳朵 */}
      <circle cx="26" cy="28" r="14" fill={fur} stroke={INK} strokeWidth="3" />
      <circle cx="74" cy="28" r="14" fill={fur} stroke={INK} strokeWidth="3" />
      <circle cx="26" cy="28" r="7" fill={inner} />
      <circle cx="74" cy="28" r="7" fill={inner} />
      {/* 头 */}
      <circle cx="50" cy="55" r="31" fill={fur} stroke={INK} strokeWidth="3" />
      {/* 口鼻 */}
      <ellipse cx="50" cy="65" rx="16" ry="12" fill={inner} stroke={INK} strokeWidth="2.4" />
      {/* 眼 */}
      <circle cx="39" cy="49" r="3.6" fill={INK} />
      <circle cx="61" cy="49" r="3.6" fill={INK} />
      {/* 鼻 */}
      <ellipse cx="50" cy="59" rx="4.6" ry="3.4" fill={INK} />
      <path d="M50 62.5v3.5M50 66q-4 3-7 0M50 66q4 3 7 0" fill="none" stroke={INK} strokeWidth="2.2" strokeLinecap="round" />
      <Accessory kind={accessory} />
    </svg>
  )
}
