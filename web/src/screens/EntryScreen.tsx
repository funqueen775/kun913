import { Stage } from '../components/Stage'
import { GameButton, ParchmentFrame, Plate } from '../components/ui'
import './EntryScreen.css'

type EntryScreenProps = {
  title: string
  subtitle: string
  /** 存档行：小熊镇 · 第 1 年 第 1 月 · L1 新人 */
  saveLine: string
  note: string
  hint: string
  onBack?: () => void
  /** 主循环还没开工，所以默认不传 —— 按钮会渲染成 disabled，把边界画出来 */
  onStart?: () => void
}

/**
 * 第 3 屏 · 进入游戏（原型边界屏）
 *
 * 外壳跟第 2 屏同一套：深棕木质雕花框 + 羊皮纸（ParchmentFrame），
 * 顶栏结构也照抄（返回 / 标题条 / 状态牌）—— 三屏是一个产品，不能换语言。
 *
 * 上一版是个浮在左边的小面板 + 一颗「待做」胶囊徽章 + 虚线分隔，
 * 那是第 1 屏标题牌的语言，混进来就显廉价；胶囊还违反 tokens.css 的「不用胶囊」。
 *
 * 这屏的职责是**把原型的边界画清楚**：存档信息在这儿（标题页被用户要求不报进度，
 * 进度留给游戏内），下一步「开始第 1 个月」以 disabled 呈现 —— 主循环接上后端 10 个
 * 接口后，把它换成真的按钮即可。
 */
export function EntryScreen({ title, subtitle, saveLine, note, hint, onBack, onStart }: EntryScreenProps) {
  return (
    <Stage layout="center">
      <ParchmentFrame>
        <div className="entry__top">
          <div className="entry__back">
            <GameButton variant="secondary" onClick={onBack}>
              返回
            </GameButton>
          </div>
          <div className="entry__titles">
            <h1 className="entry__title">{title}</h1>
            <p className="entry__subtitle">{subtitle}</p>
          </div>
          <div className="entry__status">L1 新人</div>
        </div>

        <div className="entry__body">
          <div className="entry__card xz-rise">
            <div className="entry__save">
              <span className="entry__save-dot" aria-hidden="true" />
              <span className="entry__save-label">存档</span>
              <span className="entry__save-value">{saveLine}</span>
            </div>

            <p className="entry__note">{note}</p>

            <ol className="entry__steps">
              <li className="entry__step">
                <span className="entry__step-num" aria-hidden="true">
                  1
                </span>
                会话、存档、剧情进度都由服务端权威保存，客户端只渲染
              </li>
              <li className="entry__step">
                <span className="entry__step-num" aria-hidden="true">
                  2
                </span>
                每次选择作为事件上报，网络重试不重复计分
              </li>
              <li className="entry__step">
                <span className="entry__step-num" aria-hidden="true">
                  3
                </span>
                48 个月走完，回放这四年，生成职业测评报告
              </li>
            </ol>

            <div className="entry__facts">
              <div className="entry__fact">
                <span className="entry__fact-num">48</span>
                <span className="entry__fact-label">个月，一局走完</span>
              </div>
              <div className="entry__fact">
                <span className="entry__fact-num">16</span>
                <span className="entry__fact-label">个自由周末</span>
              </div>
              <div className="entry__fact">
                <span className="entry__fact-num">19</span>
                <span className="entry__fact-label">件可以做的事</span>
              </div>
            </div>
          </div>
        </div>

        <div className="entry__footer">
          <Plate className="entry__hint">{hint}</Plate>
          <div className="entry__actions">
            <GameButton disabled={!onStart} onClick={onStart}>
              开始第 1 个月
            </GameButton>
          </div>
        </div>
      </ParchmentFrame>
    </Stage>
  )
}
