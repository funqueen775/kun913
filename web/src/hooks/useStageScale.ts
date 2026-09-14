import { useEffect, useState } from 'react'

export const STAGE_W = 1600
export const STAGE_H = 900

/**
 * 设计稿固定 1600×900（正好等于地图原生分辨率），按窗口等比缩放。
 * 这样任何屏幕都不裁切、不变形，UI 也不用写响应式断点。
 */
export function useStageScale() {
  const [scale, setScale] = useState(1)

  useEffect(() => {
    const fit = () => setScale(Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H))
    fit()
    window.addEventListener('resize', fit)
    return () => window.removeEventListener('resize', fit)
  }, [])

  return scale
}
