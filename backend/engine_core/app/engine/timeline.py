# -*- coding: utf-8 -*-
"""时间轴：把 44 个节点（39 主线 + 5 成就）排进 48 个月。

⚠ 待策划确认：剧本只给了「五幕 + 职级解锁」，没给逐月排期。本模块给出的是
**默认排期**（按幕窗口均匀铺开），属于可配置项，策划改这里即可，不改引擎。
"""

from __future__ import annotations

from ..core.loader import ConfigRegistry

# 幕 → (起始月, 结束月)。合计覆盖 1-48 月，其中 40/42/45/47 月无主线节点（留白）
ACT_WINDOWS: dict[int, tuple[int, int]] = {
    1: (1, 9),
    2: (10, 19),
    3: (20, 27),
    4: (28, 38),
    5: (39, 48),
}

# 项目阶段解锁（剧情册 §2.2）：职级不够 → 阶段不解锁，玩家以「旁观座位」参与
ACT_REQUIRED_LEVEL = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6}


def build_schedule(reg: ConfigRegistry) -> list[tuple[int, str]]:
    """返回 [(month, event_id)]，按月份升序。"""
    out: list[tuple[int, str]] = []
    for act, (start, end) in ACT_WINDOWS.items():
        nodes = [e for e in reg.events.values() if e.act == act]
        nodes.sort(key=lambda e: e.index)
        n = len(nodes)
        if n == 0:
            continue
        span = end - start
        for i, ev in enumerate(nodes):
            month = start + round(i * span / max(n - 1, 1))
            out.append((month, ev.event_id))
    out.sort(key=lambda x: (x[0], reg.events[x[1]].index))
    return out


def build_position_schedule() -> dict[int, list[int]]:
    """返回 {月: [自由周末 / 考核窗]} 等固定节奏钩子。"""
    return {}


def free_time_months() -> list[int]:
    """每 3 个月一个自由周末：第 3/6/9…48 月，共 16 个。"""
    return [m for m in range(3, 49, 3)]


def is_promotion_month(month: int, windows: tuple[int, ...]) -> bool:
    return month in windows
