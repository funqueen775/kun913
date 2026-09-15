import type { ReactNode } from 'react'
import { STAGE_H, STAGE_W, useStageScale } from '../hooks/useStageScale'

type StageProps = {
  children: ReactNode
  /** left = 面板靠左；center = 面板居中 */
  layout?: 'left' | 'center'
  stamp?: string
  /**
   * 画布底图。默认是游戏内的世界地图（俯视沙盘）。
   * 标题页必须传专门的标题画面 —— 俯视沙盘压不住标题，那是给进游戏后看的。
   */
  bg?: string
  /** 底图缓慢推近（标题页用），让静态画面有呼吸感 */
  bgDrift?: boolean
}

export function Stage({ children, layout = 'left', stamp, bg = '/art/map.jpg', bgDrift }: StageProps) {
  const scale = useStageScale()

  const vignette =
    layout === 'left'
      ? 'radial-gradient(ellipse 80% 80% at 62% 46%, rgba(30,20,10,0) 36%, rgba(30,20,10,0.36) 100%)'
      : 'radial-gradient(ellipse 78% 78% at 50% 46%, rgba(30,20,10,0) 34%, rgba(30,20,10,0.34) 100%)'

  return (
    <div className="stage-viewport">
      <div className="stage" style={{ width: STAGE_W, height: STAGE_H, transform: `scale(${scale})` }}>
        <div
          className={`stage__map${bgDrift ? ' stage__map--drift' : ''}`}
          style={{ backgroundImage: `url("${bg}")` }}
        />
        {layout === 'left' && <div className="stage__shade-left" />}
        <div className="stage__vignette" style={{ background: vignette }} />
        {children}
        {stamp && <div className="stage__stamp">{stamp}</div>}
      </div>
    </div>
  )
}
