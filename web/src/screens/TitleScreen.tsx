import { Stage } from '../components/Stage'
import { GameButton, Gem, IconButton, Roof } from '../components/ui'
import './TitleScreen.css'

type TitleScreenProps = {
  layout?: 'left' | 'center'
  /** 标题画面。默认 /art/title-bg.jpg —— 与游戏内的 map.jpg 是两张不同的画 */
  bg?: string
  hasSave?: boolean
  onStart?: () => void
  onContinue?: () => void
  onLoad?: () => void
  onReport?: () => void
  onSettings?: () => void
  onExit?: () => void
}

const DocIcon = () => (
  <svg width="28" height="28" viewBox="0 0 32 32" fill="none" aria-hidden="true">
    <path d="M7 4h12l6 6v18H7z" fill="var(--xz-cream-light)" stroke="var(--xz-ink)" strokeWidth="2.6" strokeLinejoin="round" />
    <path d="M19 4v6h6" fill="none" stroke="var(--xz-ink)" strokeWidth="2.6" strokeLinejoin="round" />
    <path d="M11 16h10M11 21h7" stroke="var(--xz-ink)" strokeWidth="2.4" strokeLinecap="round" />
  </svg>
)

const SliderIcon = () => (
  <svg width="28" height="28" viewBox="0 0 32 32" fill="none" aria-hidden="true">
    <path d="M6 11h20M6 21h20" stroke="var(--xz-ink)" strokeWidth="2.6" strokeLinecap="round" />
    <circle cx="12" cy="11" r="4" fill="var(--xz-cream-light)" stroke="var(--xz-ink)" strokeWidth="2.6" />
    <circle cx="21" cy="21" r="4" fill="var(--xz-cream-light)" stroke="var(--xz-ink)" strokeWidth="2.6" />
  </svg>
)

/**
 * 第 1 屏 · 标题主菜单
 *
 * 版式照参考图第 1 屏：**上下两块独立的牌**，不是一整块——
 * 上面是「瓦顶 + 米黄横幅」的标题牌，下面才是菜单牌（顶上镶一颗小宝石）。
 *
 * 标题牌上只有四个字：副标题（Agent 开发师 · 48 个月）和存档条
 * （小熊镇 · 第 1 年 第 1 月 · L1 新人）用户已要求去掉 —— 标题页不需要报进度，
 * 存档信息留给游戏内。
 *
 * 底图是专门的标题画面（月夜小熊镇，湖心立着熊头鱼尾的熊石雕塑），
 * 不是游戏内的俯视世界地图——后者是进游戏之后看的东西，压不住标题。
 */
export function TitleScreen({
  layout = 'left',
  bg = '/art/title-bg.jpg',
  hasSave = true,
  onStart,
  onContinue,
  onLoad,
  onReport,
  onSettings,
  onExit,
}: TitleScreenProps) {
  return (
    <Stage layout={layout} bg={bg} bgDrift>
      <div className="title-screen__topbar xz-rise" style={{ animationDelay: '0.05s' }}>
        <IconButton label="我的报告" onClick={onReport}>
          <DocIcon />
        </IconButton>
        <IconButton label="游戏设置" onClick={onSettings}>
          <SliderIcon />
        </IconButton>
        <IconButton label="帮助">
          <span className="sq-btn__glyph">?</span>
        </IconButton>
      </div>

      <div className={`title-screen__stack title-screen__stack--${layout}`}>
        <div className="title-screen__banner xz-rise" style={{ animationDelay: '0.15s' }}>
          <Roof width={560} />
          <h1 className="title-screen__title">熊心壮职</h1>
        </div>

        <div className="title-screen__menu xz-rise" style={{ animationDelay: '0.26s' }}>
          <Gem size={30} />

          <div className="title-screen__buttons">
            {hasSave && (
              <GameButton className="xz-rise" onClick={onContinue}>
                继续游戏
              </GameButton>
            )}
            <GameButton className="xz-rise" onClick={onStart}>
              开始新游戏
            </GameButton>
            <GameButton className="xz-rise" onClick={onLoad}>
              加载游戏
            </GameButton>
            <div className="title-screen__row">
              <GameButton className="xz-rise" variant="secondary" onClick={onReport}>
                我的报告
              </GameButton>
              <GameButton className="xz-rise" variant="secondary" onClick={onSettings}>
                游戏设置
              </GameButton>
            </div>
            <GameButton className="xz-rise" variant="exit" onClick={onExit}>
              退出游戏
            </GameButton>
          </div>
        </div>
      </div>
    </Stage>
  )
}
