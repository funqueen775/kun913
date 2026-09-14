import { useState } from 'react'
import { Stage } from '../components/Stage'
import { GameButton, ParchmentFrame, Plate } from '../components/ui'
import { BearAvatar } from '../components/BearAvatar'
import { CAST_NOTE, INTRO_DONE_LABEL, INTRO_FOOTER_HINT, INTRO_PAGES, ROSTER } from '../data/townIntro'
import { report } from '../api/report'
import './TownIntroScreen.css'

type TownIntroScreenProps = {
  initialPage?: number
  onBack?: () => void
  onDone?: () => void
}

const TOTAL = INTRO_PAGES.length

/**
 * 第 2 屏 · 认识小熊镇
 *
 * 外壳照参考图第 2 屏：深棕木质雕花框（顶部钟楼、四角藤叶）+ 里面一张羊皮纸。
 * 三页都是**固定内容页**：小镇介绍 / 人物名单 / 开始生活。
 *
 * 「人物名单」这一页是**人物档案**版式：整屏五张卡并排，一人一格，
 * 只做介绍、不做选择（选择在第 3 屏）。之前挤在左半边小框里跟插图并排，看不清，已改。
 *
 * 另外两页配右侧插图，插图直接裁自小熊镇地图——另画一张插画是最容易跑味的地方。
 */
export function TownIntroScreen({ initialPage = 0, onBack, onDone }: TownIntroScreenProps) {
  const [index, setIndex] = useState(Math.min(Math.max(initialPage, 0), TOTAL - 1))
  const page = INTRO_PAGES[index]
  const isLast = index === TOTAL - 1

  const goto = (next: number, event: string) => {
    report(event, { from: page.id, to: INTRO_PAGES[next]?.id ?? 'done', index: next })
    setIndex(next)
  }

  return (
    <Stage layout="center">
      <ParchmentFrame>
        <div className="intro__top">
          <div className="intro__back">
            <GameButton variant="secondary" onClick={onBack}>
              返回
            </GameButton>
          </div>
          <div className="intro__titles">
            <h1 className="intro__title">认识小熊镇</h1>
            <p className="intro__subtitle">先了解这里怎么过，再决定怎么开始</p>
          </div>
          <div className="intro__status">L1 新人</div>
        </div>

        <div className="intro__tabs" role="tablist">
          {INTRO_PAGES.map((p, i) => (
            <button
              key={p.id}
              type="button"
              role="tab"
              aria-selected={i === index}
              className={`intro__tab${i === index ? ' intro__tab--on' : ''}`}
              onClick={() => goto(i, 'intro_tab_click')}
            >
              {p.tab}
            </button>
          ))}
        </div>

        {page.cast ? (
          <div className="intro__body intro__body--cast">
            <div className="intro__cast">
              {ROSTER.map((bear) => (
                <article key={bear.id} className="cast-card">
                  <div className="cast-card__portrait">
                    <BearAvatar fur={bear.fur} inner={bear.inner} accessory={bear.accessory} size={112} />
                  </div>
                  <div className="cast-card__name">{bear.name}</div>
                  <div className="cast-card__role">{bear.role}</div>
                  <div className="cast-card__place">
                    <span className="cast-card__pin" aria-hidden="true" />
                    {bear.place}
                  </div>
                  <div className="cast-card__rule" />
                  <p className="cast-card__line">{bear.line}</p>
                  {bear.note && <span className="cast-card__badge">{bear.note}</span>}
                </article>
              ))}
            </div>
            <p className="intro__cast-note">{CAST_NOTE}</p>
          </div>
        ) : (
          <div className="intro__body">
            <div className="intro__text">
              <div className="intro__kicker">{page.kicker}</div>
              <h2 className="intro__heading">{page.title}</h2>
              {page.body.map((paragraph) => (
                <p key={paragraph.slice(0, 12)} className="intro__paragraph">
                  {paragraph}
                </p>
              ))}
            </div>

            <figure className="intro__art">
              <img src={page.art} alt="小熊镇地图局部" />
              {page.ripples && (
                <svg className="intro__ripples" viewBox="0 0 450 420" preserveAspectRatio="none" aria-hidden="true">
                  <g fill="none" stroke="var(--xz-title)">
                    <circle cx="225" cy="210" r="52" strokeWidth="2" opacity="0.7" />
                    <circle cx="225" cy="210" r="92" strokeWidth="1.6" opacity="0.45" />
                    <circle cx="225" cy="210" r="134" strokeWidth="1.4" opacity="0.25" />
                  </g>
                </svg>
              )}
            </figure>
          </div>
        )}

        <div className="intro__pager">
          <Plate className="intro__pager-plate">
            第 {index + 1} / {TOTAL} 页
          </Plate>
        </div>

        <div className="intro__footer">
          <Plate className="intro__hint">{INTRO_FOOTER_HINT}</Plate>
          <div className="intro__actions">
            <GameButton
              variant="secondary"
              disabled={index === 0}
              onClick={() => goto(index - 1, 'intro_page_prev')}
            >
              上一页
            </GameButton>
            <GameButton variant="secondary" onClick={onDone}>
              跳过
            </GameButton>
            <GameButton onClick={() => (isLast ? onDone?.() : goto(index + 1, 'intro_page_next'))}>
              {isLast ? INTRO_DONE_LABEL : '继续'}
            </GameButton>
          </div>
        </div>
      </ParchmentFrame>
    </Stage>
  )
}
