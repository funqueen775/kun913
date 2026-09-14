# -*- coding: utf-8 -*-
"""晋升：只看努力，不看日历。三层判定，7 个考核窗。

口径（剧情册 §2.1-2.3）：
  累积层 70% | 行为层 20% | 答辩层 10%；三层全达标 → 升；
  任何一层不达标 → 不升，**数值不清零**，下个考核日继续。
  考核窗：第 6/12/18/24/30/36/42 月。职级 L1→L7。
  终局分级：传承者 L6-L7 / 中坚者 L3-L5 / 守界者 L1-L2。
  红线：阈值数字永不出现。

⚠ 阈值缺省值是**占位值**，剧本与机制文档均未给标定数字，必须由机制层校准后替换。
"""

from __future__ import annotations

from ..core import constants as C
from .state import GameState

# ⚠ 占位阈值（待机制层校准）：目标职级 → 累积层门槛
PLACEHOLDER_CUMULATIVE_MIN = {2: 8, 3: 15, 4: 23, 5: 32, 6: 42, 7: 52}
# ⚠ 占位阈值：行为层允许的隐瞒类 flag 数（0 = 一个都不能有）
PLACEHOLDER_BEHAVIOR_MAX_CONCEAL = 0
# ⚠ 占位阈值：答辩层最低分（仅 L4+ 有答辩）
PLACEHOLDER_DEFENSE_MIN = 0


def evaluate(state: GameState) -> dict:
    """对当前考核窗做三层判定。返回结果与逐层明细（明细只进后台日志，不下发）。"""
    target = min(state.level + 1, C.LEVEL_MAX)

    cumulative = state.window_cumulative
    cum_min = PLACEHOLDER_CUMULATIVE_MIN.get(target, 999)
    cum_pass = cumulative >= cum_min

    conceal = [f for f in state.window_flags if f in C.CONCEAL_FLAGS]
    beh_pass = len(conceal) <= PLACEHOLDER_BEHAVIOR_MAX_CONCEAL

    defense_pass = True
    if target >= 4:
        defense_pass = state.competency.get("integrity", 0) >= PLACEHOLDER_DEFENSE_MIN

    promoted = cum_pass and beh_pass and defense_pass
    return {
        "target_level": target,
        "cumulative": {"value": cumulative, "min": cum_min, "pass": cum_pass, "weight": 0.70},
        "behavior": {"conceal_flags": conceal, "max": PLACEHOLDER_BEHAVIOR_MAX_CONCEAL,
                     "pass": beh_pass, "weight": 0.20},
        "defense": {"pass": defense_pass, "weight": 0.10, "has_defense": target >= 4},
        "promoted": promoted,
        "thresholds_are_placeholder": True,
    }


def settle_window(state: GameState, month: int) -> dict:
    """执行一个考核窗：判定 → 升降级 → 重置窗口统计 → 记录。"""
    result = evaluate(state)
    result["month"] = month
    result["level_before"] = state.level

    if result["promoted"] and state.level < C.LEVEL_MAX:
        state.level += 1
        state.consecutive_promotion_failures = 0
    else:
        result["promoted"] = False
        state.consecutive_promotion_failures += 1

    result["level_after"] = state.level
    state.promotion_windows.append(result)

    # 窗口重置（数值不清零 → 六维保留，只重置窗口统计）
    state.window_cumulative = 0
    state.window_flags = []
    return result


def final_grade(state: GameState) -> dict:
    """第 48 月答辩后的终局评级（剧情册 §2.3）。"""
    level = state.level
    grade = next((g for g, (lo, hi) in C.FINAL_GRADE.items() if lo <= level <= hi), "守界者")
    windows = state.promotion_windows
    ever_failed = any(not w["promoted"] for w in windows)
    has_conceal = any(f in C.CONCEAL_FLAGS for f in state.flags)

    if not ever_failed and not has_conceal:
        label = "晋升达成"
    elif has_conceal:
        label = "带保留通过"
    elif ever_failed and level >= 3:
        label = "中途卡过"
    else:
        label = "再沉淀一年"

    return {
        "grade": grade, "label": label, "level": level,
        "frames": {"甩锅场合": state.counter_blame_scenes,
                   "甩锅场合守住": state.counter_blame_held,
                   "无人监督场合": state.counter_nosupervision,
                   "无人监督场合守住": state.counter_nosupervision_held},
        "window_count": len(windows),
    }
