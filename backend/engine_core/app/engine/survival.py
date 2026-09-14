# -*- coding: utf-8 -*-
"""生存轨：岗位存续与「最后谈话」。与成长轨完全独立。

口径（剧情册 §2.4）：
  驱动因素 = 隐瞒类 flag、引爆的事故、谈话中的表现；
  **绝不以「没晋升」本身为触发条件**；
  明示原则（最高优先级红线）——每一次处境变化都看得见、说得出原因、知道还剩多少余地。

  五级预警：首次重大失误 → 累计第二次进入「观察」→ 观察期内再失误进入「危急」
           → 危急期内再失误触发「最后谈话」→ 谈话后按出口走
  保护：前 12 个月不进危急（新人保护）；连续 6 个月无新增失误 → 自动回升一级
"""

from __future__ import annotations

from ..core import constants as C
from .state import GameState

# 「最后谈话」三个出口（剧情册 §2.4）
LAST_TALK_EXITS = {
    "A": {"name": "争取转岗", "走向": "调往边缘项目组，后续主线换「边缘视角变体」"},
    "B": {"name": "主动离开", "走向": "提前终局，报告照常生成（决策点 >=18 为完整报告）"},
    "C": {"name": "背水一战", "走向": "3 个月观察期：达标回「观察」，不达标转 A/B"},
}


def register_mistake(state: GameState, month: int, reason: str, severity: int = 1) -> dict:
    """登记一次重大失误（埋雷引爆 / 隐瞒类 flag / 事故）。"""
    state.survival_strikes += severity
    state.months_since_mistake = 0
    state.incidents.append({"month": month, "reason": reason, "severity": severity})
    return {"month": month, "strikes": state.survival_strikes, "reason": reason}


def raise_flags(state: GameState, month: int) -> list[dict]:
    """结算期检查：本窗新增的隐瞒类 flag 记一次失误。"""
    out = []
    for f in state.window_flags:
        if f in C.CONCEAL_FLAGS:
            out.append(register_mistake(state, month, f"隐瞒类 flag：{f}"))
    return out


def monthly_tick(state: GameState, month: int) -> dict:
    """每月推进一次：状态迁移 + 自我修复。"""
    prev = state.survival_state

    # 自我修复：连续 6 个月无新增失误 → 自动回升一级（且观察期/危急期同样适用）
    state.months_since_mistake += 1
    if state.months_since_mistake >= C.SELF_HEAL_MONTHS and state.survival_strikes > 0:
        state.survival_strikes -= 1
        state.months_since_mistake = 0

    strikes = state.survival_strikes
    if strikes <= 0:
        new_state = "stable"
    elif strikes == 1:
        new_state = "stable"          # 级 1：即时剧情反馈 + 灰便签，状态仍是稳定
    elif strikes == 2:
        new_state = "observation"     # 级 2：主管当面警告
    elif strikes == 3:
        new_state = "critical"        # 级 3：HR 预约 + 明示「下一次触发正式谈话」
    else:
        new_state = "last_talk"       # 级 4：最后谈话

    # 新人保护：前 12 个月不进危急
    if month <= C.NEWBIE_PROTECT_MONTHS and new_state in ("critical", "last_talk"):
        new_state = "observation"

    state.survival_state = new_state
    return {
        "month": month, "from": prev, "to": new_state,
        "strikes": strikes,
        "changed": prev != new_state,
        "reason_list": [i["reason"] for i in state.incidents][-5:],
        "player_visible": C.SURVIVAL_CN[new_state],
    }


def trigger_last_talk(state: GameState, month: int, exit_id: str) -> dict:
    """执行「最后谈话」：开场逐条复述原因（证据回放式），然后三选一。"""
    spec = LAST_TALK_EXITS.get(exit_id)
    if spec is None:
        raise KeyError(f"未知出口 {exit_id}")
    if exit_id == "A":
        state.survival_state = "exited"
    elif exit_id == "B":
        state.survival_state = "exited"
    else:
        state.survival_state = "critical"     # C：背水一战，仍留在危急
    return {
        "month": month, "exit": exit_id, **spec,
        "reason_replay": [i for i in state.incidents],
        "state_after": state.survival_state,
    }


def should_trigger_crisis(state: GameState) -> bool:
    """危机对话触发：连续 2 个考核窗未达标（成长轨，与生存轨互不混淆）。"""
    return state.consecutive_promotion_failures >= 2
