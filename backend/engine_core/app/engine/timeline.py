# -*- coding: utf-8 -*-
"""时间轴：把在册打分卡节点排进 48 个月。

⚠ 待策划确认：剧本只给了「六幕 + 职级解锁」，没给逐月排期。本模块给出的是
**默认排期**（按幕窗口均匀铺开），属于可配置项，策划改这里即可，不改引擎。

2026-09-16（24 件基准 / scoring_cards v3.0）：
  - 节点数由 44（39 主线 + 5 成就）改为**在册 23 张**（成就节点 C1–C4 归档、C5 并入主线）。
  - 幕数由 5 改为 **6**（Godot 侧是六幕；引擎此前没有第六幕，导致 act=6 的
    E40/E41/E42/C5 排不进任何窗口 → `server.sched_month['E40']` KeyError，
    端到端「M6-E21 起全部连接被断开」）。
  - 窗口按 Godot 的真实月份反推（Godot 的 month 才是剧情权威，引擎月份只是账本记号）：
    act1 1–9 / act2 11–16 / act3 18–23 / act4 25–32 / act5 35–39 / act6 41–48。
    中间的 10 / 17 / 24 / 33-34 / 40 月是留白（Godot 在这几个月没有主线）。
"""

from __future__ import annotations

from ..core.loader import ConfigRegistry

# 幕 → (起始月, 结束月)。六幕覆盖 1-48 月，留白月见模块 docstring。
ACT_WINDOWS: dict[int, tuple[int, int]] = {
    1: (1, 9),
    2: (11, 16),
    3: (18, 23),
    4: (25, 32),
    5: (35, 39),
    6: (41, 48),
}

# 项目阶段解锁（剧情册 §2.2）：职级不够 → 阶段不解锁，玩家以「旁观座位」参与
ACT_REQUIRED_LEVEL = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 6}


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
