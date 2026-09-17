import { GameButton, ParchmentFrame, Plate } from '../components/ui'
import rawReport from '../data/report_sample.json'
import './ReportScreen.css'

/* ---------- 报告形状（按服务端真实字段定义，缺的自动落空态） ---------- */

type RadarRow = { pillar: string; score: number; cap: number; evidence_count: number; note: string }

type BigFiveRow = {
  trait: string
  traitCn: string
  self: number | null
  behavior: number | null
  posterior: number | null
  conflict: number | null
  conflictSignificant: boolean
  evidenceCount: number
  behaviorAvailable: boolean
  consistency: number | null
  note: string
}

type TopicBullet = { label: string; value: string }
type TopicEvidence = { seq: number; month: number; node_id: string; option_id: string; snippet: string }
type Topic = {
  key: string
  title: string
  displayable: boolean
  n: number
  summary: string
  bullets: TopicBullet[]
  evidence: TopicEvidence[]
}

type PromoWindow = { seq: number; month: number; passed: boolean; levelAfter: number }
type ReplayRow = {
  seq: number
  month: number
  restMonth: boolean
  nodeId: string
  optionId: string
  hesitationMs: number
  switchCount: number
  snippet: string
}

type Report = {
  sessionId: string
  scoringVersion: string
  generatedAt: string
  decisionCount: number
  layers: {
    persona: {
      personaSketch: string
      bigfive: BigFiveRow[]
      radar: RadarRow[]
      topics: Topic[]
      investment: { innerMotivation: string | null; line: string }
      energyLedger: { dangerZoneCount: number; pushedThroughCount: number; line: string }
      situationTrack: { states: unknown[]; burnoutCount: number }
      promotionTrack: {
        windows: PromoWindow[]
        finalGrade: { grade: string; level: number; label: string; line: string }
      }
      sprintAndDisguise: { sprint: unknown[]; disguise: { level: string; line: string } }
      psychDriveHighlights: string[]
    }
    market: { dataSource: string; corpusSize: number; jobs: unknown[] }
    crossHints: { hints: { line: string; basis: unknown[] }[] }
  }
  evidenceReplay: ReplayRow[]
}

/** 版式验证数据源：真实引擎跑完 24 件主线导出的报告（非手造样例） */
const REPORT = rawReport as unknown as Report
const P = REPORT.layers.persona

/* ---------- 六柱雷达（SVG 手绘，不引依赖） ---------- */

const CX = 130
const CY = 124
const R = 86
/* 从正上方开始，每 60° 一根轴；与报告 radar 数组顺序一致 */
const ANGLES = [-90, -30, 30, 90, 150, 210].map((d) => (d * Math.PI) / 180)

function pt(i: number, r: number): [number, number] {
  return [CX + r * Math.cos(ANGLES[i]), CY + r * Math.sin(ANGLES[i])]
}

function ringPoints(r: number): string {
  return ANGLES.map((_, i) => pt(i, r).map((n) => n.toFixed(1)).join(',')).join(' ')
}

/** 数据多边形：报告的 score 已是 0-100 百分制（引擎侧已按 cap 归一），直接按百分比画。 */
function dataPoints(): string {
  return P.radar
    .map((row, i) => pt(i, R * Math.min(100, Math.max(0, row.score)) / 100).map((n) => n.toFixed(1)).join(','))
    .join(' ')
}

function RadarHex() {
  return (
    <svg className="rp__radar" viewBox="0 0 260 252" role="img" aria-label="六支柱雷达图">
      {[R / 3, (R * 2) / 3, R].map((r) => (
        <polygon key={r} points={ringPoints(r)} fill="none" stroke="var(--xz-ink-soft)" strokeWidth="1" />
      ))}
      {ANGLES.map((_, i) => {
        const [x, y] = pt(i, R)
        return <line key={i} x1={CX} y1={CY} x2={x} y2={y} stroke="var(--xz-ink-soft)" strokeWidth="1" />
      })}
      <polygon points={dataPoints()} fill="var(--xz-orange)" fillOpacity="0.45" stroke="var(--xz-orange-dark)" strokeWidth="2" />
      {P.radar.map((row, i) => {
        const [x, y] = pt(i, R)
        const top = i === 0
        const right = i === 1 || i === 2
        const bottom = i === 3
        const anchor = top || bottom ? 'middle' : right ? 'start' : 'end'
        const lx = top || bottom ? x : right ? x + 12 : x - 12
        const nameY = top ? y - 20 : bottom ? y + 18 : y - 5
        const valY = top ? y - 6 : bottom ? y + 32 : y + 10
        return (
          <g key={row.pillar}>
            <text x={lx} y={nameY} textAnchor={anchor} fontSize="12" fontWeight="700" fill="var(--xz-ink)">
              {row.pillar}
            </text>
            <text x={lx} y={valY} textAnchor={anchor} fontSize="11" fill="var(--xz-brown-text)">
              {row.score} 分
            </text>
          </g>
        )
      })}
    </svg>
  )
}

/* ---------- 小部件 ---------- */

function SectionHead({ index, title }: { index: number; title: string }) {
  return (
    <h2 className="rp__sec-head">
      <span className="rp__sec-no">{index}</span>
      {title}
    </h2>
  )
}

function LineCard({ text }: { text: string }) {
  return (
    <div className="rp__line-card">
      <p>{text}</p>
    </div>
  )
}

/* ---------- 主屏 ---------- */

type ReportScreenProps = { onBack?: () => void }

export function ReportScreen({ onBack }: ReportScreenProps) {
  const fg = P.promotionTrack.finalGrade
  const generated = REPORT.generatedAt.slice(0, 16).replace('T', ' ')
  const topics = P.topics.filter((t) => t.displayable)

  return (
    <ParchmentFrame>
      <div className="rp__top">
        <div className="rp__back">
          <GameButton variant="secondary" onClick={onBack}>
            返回
          </GameButton>
        </div>
        <div className="rp__titles">
          <h1 className="rp__title">职业测评报告</h1>
          <p className="rp__subtitle">
            48 个月 · {REPORT.decisionCount} 个决策点 · {generated}
          </p>
        </div>
        <div className="rp__status">
          L{fg.level} {fg.grade}
        </div>
      </div>

      <div className="rp__body">
        {/* 一 · 终局总评 */}
        <section className="rp__sec">
          <SectionHead index={1} title="终局总评" />
          <div className="rp__verdict">
            <div className="rp__verdict-grade">
              <span className="rp__verdict-level">L{fg.level}</span>
              <span className="rp__verdict-name">{fg.grade}</span>
            </div>
            <div className="rp__verdict-side">
              <p className="rp__verdict-label">{fg.label}</p>
              <p className="rp__verdict-sketch">{P.personaSketch}</p>
            </div>
          </div>
          <LineCard text={fg.line} />
        </section>

        {/* 二 · 六支柱 */}
        <section className="rp__sec">
          <SectionHead index={2} title="能力六支柱" />
          <div className="rp__radar-wrap">
            <RadarHex />
            <ul className="rp__pillar-list">
              {P.radar.map((row) => (
                <li key={row.pillar} className="rp__pillar">
                  <span className="rp__pillar-name">{row.pillar}</span>
                  <span className="rp__pillar-bar">
                    <i style={{ width: `${Math.min(100, Math.max(0, row.score))}%` }} />
                  </span>
                  <span className="rp__pillar-val">{row.score} 分</span>
                </li>
              ))}
            </ul>
          </div>
        </section>

        {/* 三 · 性格五维（行为证据不足的行如实降档展示） */}
        <section className="rp__sec">
          <SectionHead index={3} title="性格五维" />
          <ul className="rp__bigfive">
            {P.bigfive.map((row) => (
              <li key={row.trait} className={`rp__bf ${row.behaviorAvailable ? '' : 'rp__bf--dim'}`}>
                <span className="rp__bf-name">{row.traitCn}</span>
                {row.behaviorAvailable ? (
                  <span className="rp__bf-detail">
                    行为 <b>{row.behavior}</b>
                    {row.posterior != null && (
                      <>
                        · 后验 <b>{row.posterior}</b>
                      </>
                    )}
                    {row.conflictSignificant && <em className="rp__bf-conflict">有矛盾</em>}
                  </span>
                ) : (
                  <span className="rp__bf-detail">{row.note}</span>
                )}
                <span className="rp__bf-ev">{row.evidenceCount} 条证据</span>
              </li>
            ))}
          </ul>
        </section>

        {/* 四 · 行为专题 */}
        {topics.length > 0 && (
          <section className="rp__sec">
            <SectionHead index={4} title="行为专题" />
            <div className="rp__topics">
              {topics.map((t) => (
                <div key={t.key} className="rp__topic">
                  <h3>{t.title}</h3>
                  <p className="rp__topic-sum">{t.summary}</p>
                  <ul>
                    {t.bullets.map((b) => (
                      <li key={b.label}>
                        <span>{b.label}</span>
                        <b>{b.value}</b>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* 五 · 晋升轨迹 */}
        {P.promotionTrack.windows.length > 0 && (
          <section className="rp__sec">
            <SectionHead index={5} title="晋升轨迹" />
            <div className="rp__windows">
              {P.promotionTrack.windows.map((w) => (
                <div key={w.seq} className={`rp__win ${w.passed ? 'rp__win--pass' : ''}`}>
                  <span className="rp__win-month">第 {w.month} 月</span>
                  <span className="rp__win-state">{w.passed ? `升到 L${w.levelAfter}` : '未通过'}</span>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* 六 · 状态与精力（有内容才出现） */}
        {(P.energyLedger.line || P.sprintAndDisguise.disguise.line) && (
          <section className="rp__sec">
            <SectionHead index={6} title="状态与精力" />
            {P.energyLedger.line && <LineCard text={P.energyLedger.line} />}
            {P.sprintAndDisguise.disguise.line && <LineCard text={P.sprintAndDisguise.disguise.line} />}
          </section>
        )}

        {/* 七 · 关键时刻回放 */}
        {REPORT.evidenceReplay.length > 0 && (
          <section className="rp__sec">
            <SectionHead index={7} title="关键时刻回放" />
            <ul className="rp__replay">
              {REPORT.evidenceReplay.map((e) => (
                <li key={e.seq}>
                  <span className="rp__replay-when">
                    第 {e.month} 月 · {e.nodeId} · 选 {e.optionId} · 犹豫 {(e.hesitationMs / 1000).toFixed(1)} 秒
                  </span>
                  <span className="rp__replay-text">{e.snippet}</span>
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* 八 · 与岗位的差距（占位提示也如实呈现） */}
        {REPORT.layers.crossHints.hints.length > 0 && (
          <section className="rp__sec">
            <SectionHead index={8} title="与岗位的差距" />
            {REPORT.layers.crossHints.hints.map((h, i) => (
              <LineCard key={i} text={h.line} />
            ))}
          </section>
        )}

        <Plate className="rp__foot">
          报告由服务端生成 · 评分版本 {REPORT.scoringVersion} · 本报告只描述已发生的选择，不预言你的未来
        </Plate>
      </div>
    </ParchmentFrame>
  )
}
