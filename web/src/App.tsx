import { useState } from 'react'
import { TitleScreen } from './screens/TitleScreen'
import { TownIntroScreen } from './screens/TownIntroScreen'
import { EntryScreen } from './screens/EntryScreen'
import { report } from './api/report'

/**
 * 开场流程：标题主菜单 → 认识小熊镇（三页导览）→ 进入游戏。
 *
 * **没有「选择初始同事」这一屏** —— 五位同事是游戏里写死的，
 * 玩家不选人。开场只需要让玩家认识小镇和这五个人。
 *
 * 屏数还少，用一个 step 状态机就够 —— 等主循环进来再决定要不要引 react-router。
 */
export type Step = 'title' | 'town' | 'game'

const STEPS: Step[] = ['title', 'town', 'game']

/** 深链：?screen=town&page=2 —— 评审时可以直接把某一屏某一页发出去 */
function readDeepLink(): { step: Step; page: number } {
  if (typeof window === 'undefined') return { step: 'title', page: 0 }
  const params = new URLSearchParams(window.location.search)
  const screen = params.get('screen') as Step | null
  const page = Number(params.get('page') ?? '0')
  return {
    step: screen && STEPS.includes(screen) ? screen : 'title',
    page: Number.isFinite(page) && page > 0 ? page - 1 : 0,
  }
}

export default function App() {
  const [{ step: initialStep, page: initialPage }] = useState(readDeepLink)
  const [step, setStep] = useState<Step>(initialStep)

  const go = (next: Step, event: string) => {
    report(event)
    setStep(next)
  }

  if (step === 'title') {
    return (
      <TitleScreen
        layout="left"
        hasSave
        onStart={() => go('town', 'intro_start_click')}
        onContinue={() => go('game', 'intro_continue_click')}
        onLoad={() => report('intro_load_click')}
        onReport={() => report('intro_report_click')}
        onSettings={() => report('intro_settings_click')}
        onExit={() => report('intro_exit_click')}
      />
    )
  }

  if (step === 'town') {
    return (
      <TownIntroScreen
        initialPage={initialPage}
        onBack={() => setStep('title')}
        onDone={() => go('game', 'intro_done')}
      />
    )
  }

  return (
    <EntryScreen
      title="进入游戏"
      subtitle="开场到此结束，下面是 48 个月的主循环"
      saveLine="小熊镇 · 第 1 年 第 1 月 · L1 新人"
      note="主循环还没开工。它要接后端 10 个接口：会话、存档、剧情推进、事件上报、报告。这一屏只负责把人送进来，进来之后的事等服务端口径定稿。"
      hint="原型边界：本屏只验证开场流程，主循环未接入"
      onBack={() => setStep('town')}
    />
  )
}
