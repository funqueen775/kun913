import type { ReactNode } from 'react'
import './ui.css'

/* ============ 装饰件 ============ */

/**
 * 屋檐 —— 第 1 屏标题牌顶上那排瓦。
 * 参考图的标题牌是「瓦顶 + 米黄横幅」两块拼起来的，不是一体。
 */
export function Roof({ width = 540 }: { width?: number }) {
  return (
    <svg className="roof" width={width} height={70} viewBox="0 0 540 70" fill="none" aria-hidden="true">
      <path
        d="M14 62 L526 62 L470 30 L270 6 L70 30 Z"
        fill="var(--xz-brick)"
        stroke="var(--xz-ink)"
        strokeWidth="3.4"
        strokeLinejoin="round"
      />
      <path d="M54 50 L486 50 L470 40 L270 20 L70 40 Z" fill="var(--xz-brick-dark)" />
      <path d="M118 40 L422 40" stroke="var(--xz-ink)" strokeWidth="2" opacity="0.5" />
      <rect x="22" y="54" width="496" height="13" rx="4" fill="var(--xz-brick-dark)" stroke="var(--xz-ink)" strokeWidth="3" />
      <path d="M270 18 L282 30 L270 42 L258 30 Z" fill="var(--xz-title)" stroke="var(--xz-ink)" strokeWidth="2.4" strokeLinejoin="round" />
    </svg>
  )
}

/** 菜单牌顶上的小宝石 —— 参考图第 1 屏菜单牌正中那一颗 */
export function Gem({ size = 30 }: { size?: number }) {
  return (
    <svg className="gem" width={size} height={size} viewBox="0 0 30 30" aria-hidden="true">
      <path d="M15 2 L28 15 L15 28 L2 15 Z" fill="var(--xz-orange)" stroke="var(--xz-ink)" strokeWidth="2.6" strokeLinejoin="round" />
      <path d="M15 8 L22 15 L15 22 L8 15 Z" fill="var(--xz-title)" stroke="var(--xz-ink)" strokeWidth="1.8" strokeLinejoin="round" />
    </svg>
  )
}

/** 木质外框顶上的钟楼 —— 第 2/3 屏外壳正中那一座（向外只探出一点点，防止被外层容器裁掉） */
export function Crest({ width = 106 }: { width?: number }) {
  return (
    <svg className="crest" width={width} height={width * 0.774} viewBox="0 0 124 96" fill="none" aria-hidden="true">
      <path d="M14 50 L62 12 L110 50 Z" fill="var(--xz-orange)" stroke="var(--xz-ink)" strokeWidth="3.2" strokeLinejoin="round" />
      <rect x="8" y="47" width="108" height="12" rx="4" fill="var(--xz-orange-dark)" stroke="var(--xz-ink)" strokeWidth="3" />
      <rect x="30" y="58" width="64" height="34" rx="3" fill="var(--xz-brick)" stroke="var(--xz-ink)" strokeWidth="3" />
      <circle cx="62" cy="34" r="13" fill="var(--xz-title)" stroke="var(--xz-ink)" strokeWidth="3" />
      <path d="M62 34V26M62 34L69 38" stroke="var(--xz-ink)" strokeWidth="2.4" strokeLinecap="round" />
      <rect x="38" y="66" width="13" height="11" rx="2" fill="var(--xz-title)" stroke="var(--xz-ink)" strokeWidth="2" />
      <rect x="73" y="66" width="13" height="11" rx="2" fill="var(--xz-title)" stroke="var(--xz-ink)" strokeWidth="2" />
      <rect x="55" y="74" width="14" height="18" rx="2" fill="var(--xz-wood)" stroke="var(--xz-ink)" strokeWidth="2.4" />
    </svg>
  )
}

/** 木框四角的藤叶 —— 参考图的框上爬满了花叶，这是最重要的「贵」感来源 */
export function LeafSprig({ size = 54, flip = false }: { size?: number; flip?: boolean }) {
  return (
    <svg
      className="leaf"
      width={size}
      height={size}
      viewBox="0 0 54 54"
      fill="none"
      aria-hidden="true"
      style={flip ? { transform: 'scale(-1, 1)' } : undefined}
    >
      <path d="M6 48 Q20 36 26 14" stroke="var(--xz-leaf)" strokeWidth="3.2" strokeLinecap="round" />
      <ellipse cx="12" cy="33" rx="9" ry="5.4" fill="var(--xz-leaf)" stroke="var(--xz-ink)" strokeWidth="1.6" transform="rotate(-40 12 33)" />
      <ellipse cx="25" cy="23" rx="9" ry="5.4" fill="var(--xz-grass)" stroke="var(--xz-ink)" strokeWidth="1.6" transform="rotate(-14 25 23)" />
      <ellipse cx="17" cy="44" rx="8" ry="5" fill="var(--xz-grass)" stroke="var(--xz-ink)" strokeWidth="1.6" transform="rotate(-62 17 44)" />
    </svg>
  )
}

/* ============ 容器 ============ */

/** 带细边的小牌 —— 存档条 / 页码 / 底部提示 / 标题条都用它（参考图里不用胶囊） */
export function Plate({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`plate ${className}`}>{children}</div>
}

/** 米黄面板（第 1 屏的两块牌） */
export function WoodPanel({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`wood-panel ${className}`}>{children}</div>
}

/**
 * 第 2/3 屏的整屏外壳：深棕木质雕花框 + 里面一张羊皮纸。
 * 参考图的壳是深棕木头，羊皮纸才是内容区 —— 这个内外色差是质感的关键。
 */
export function ParchmentFrame({ children, crest = true }: { children: ReactNode; crest?: boolean }) {
  return (
    <div className="frame">
      {crest && <Crest />}
      <LeafSprig size={56} />
      <span className="frame__leaf frame__leaf--tr">
        <LeafSprig size={56} flip />
      </span>
      <span className="frame__leaf frame__leaf--br">
        <LeafSprig size={48} />
      </span>
      <div className="frame__paper">
        <div className="frame__paper-inner">{children}</div>
      </div>
    </div>
  )
}

/* ============ 按钮 ============ */

type GameButtonProps = {
  children: ReactNode
  variant?: 'primary' | 'secondary' | 'exit'
  className?: string
  disabled?: boolean
  onClick?: () => void
}

export function GameButton({ children, variant = 'primary', className = '', disabled, onClick }: GameButtonProps) {
  return (
    <button
      type="button"
      className={`game-btn game-btn--${variant} ${className}`}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  )
}

type IconButtonProps = {
  label: string
  children: ReactNode
  onClick?: () => void
}

export function IconButton({ label, children, onClick }: IconButtonProps) {
  return (
    <button type="button" className="sq-btn" aria-label={label} title={label} onClick={onClick}>
      {children}
    </button>
  )
}
