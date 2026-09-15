# -*- coding: utf-8 -*-
"""投入结构与内在动机（算法册 V2.3 §5 3e 投入结构）。

内在动机 = work 型占比 × 自愿系数（自己想做 = 1.0，加班 = 0.6）。
数据源：自由周末的 explore 类决策（state.decisions 里 source=free_time，
node_id 即活动 ID，活动类型查 free_time_system.json）。

红线（算法册 §5）：内在动机只作适配提示，不进大五、不算人格分、
不说「你适合/不适合」。
"""

from __future__ import annotations

from ..core import constants as C
from ..engine.state import GameState

_TYPE_CN = {"work": "技术", "social": "人", "solo": "自己"}


def _voluntary(activity_id: str) -> float:
    return C.OVERTIME_COEF if activity_id in C.OVERTIME_ACTIVITIES else C.VOLUNTEER_COEF


def build_investment(state: GameState, reg) -> dict:
    weekends = [d for d in state.decisions if d.source == "free_time"]
    counts: dict[str, int] = {}
    work_n = 0
    motivation_sum = 0.0
    for d in weekends:
        act = reg.activity(d.node_id) or {}
        t = act.get("type", "solo")
        counts[t] = counts.get(t, 0) + 1
        if t == "work":
            work_n += 1
            motivation_sum += _voluntary(d.node_id)

    n = len(weekends)
    inner = round(motivation_sum / n, 2) if n else None     # work 占比 × 自愿系数
    counts_cn = {_TYPE_CN.get(k, k): v for k, v in counts.items()}

    line = ""
    if n:
        top = max(counts, key=counts.get)
        line = (f"{n} 个周末，{counts.get(top, 0)} 次给了{_TYPE_CN.get(top, top)}。"
                f"没人要求的时候你也在学。"
                if top == "work" else
                f"{n} 个周末，{counts.get(top, 0)} 次给了{_TYPE_CN.get(top, top)}。")

    return {
        "weekend_counts": counts_cn,
        "inner_motivation": inner,
        "line": line,
    }
