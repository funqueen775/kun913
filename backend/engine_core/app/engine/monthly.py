# -*- coding: utf-8 -*-
"""月度轻节点（monthly_action）：4 套模板 × 4 选项，运行时按月份展开为 48 个节点。

口径（monthly_action_nodes.json v1.0 / 算法册 §9 全局参数表）：
  - 每月 3 点精力、不可结转；1 点 = 对应方向 1 点（skill→S / output→O / network→N / recovery→生命与 H 恢复）
  - 休息点效果走「花精力休息」递减：当月第 1 次 生命+2/H+1、第 2 次 生命+1/H+0、第 3 次 0，按月重置
  - 休息计数器与自由活动的休息共用（state.rest_points_used_this_month）
  - 本类节点不进 competency / bigfive 标定（雷达只来自剧情事件）
  - C 类「全砸」附 H−1：是激进偏好的测量点，不是疏漏
"""

from __future__ import annotations

from ..core.loader import ConfigRegistry
from .settlement import Choice, normalize_monthly, settle
from .state import GameState

TEMPLATE_BY_LEVEL = ((4, "monthly_L4"), (3, "monthly_L3"), (2, "monthly_L2"), (1, "monthly_L1"))


def template_for_level(level: int) -> str:
    for min_level, tpl in TEMPLATE_BY_LEVEL:
        if level >= min_level:
            return tpl
    return "monthly_L1"


def rest_effect(reg: ConfigRegistry, order: int) -> dict:
    """order 为该月第几次休息（1 起）。"""
    table = reg.monthly["monthly_rule"]["rest_point_effect_by_order_in_month"]
    if order < 1 or order > len(table):
        return {"life": 0, "h": 0}
    return dict(table[order - 1])


def apply_rest(state: GameState, reg: ConfigRegistry, points: int) -> list[dict]:
    """结算休息点：查表 → 恢复公开生命与 H。休息选择是「放弃产出换休息」的直接行为证据。"""
    applied = []
    mods = reg.monthly["monthly_rule"].get("state_modifiers", [])
    bonus = 0
    for m in mods:
        if m.get("if") == "life <= 3" and state.life <= 3:
            bonus = 1
    for _ in range(points):
        state.rest_points_used_this_month += 1
        eff = rest_effect(reg, state.rest_points_used_this_month)
        life_gain = int(eff.get("life", 0)) + (bonus if eff.get("life", 0) > 0 else 0)
        h_gain = int(eff.get("h", 0))
        state.life = min(10, state.life + life_gain)
        state.H = min(10, state.H + h_gain)
        applied.append({"order": state.rest_points_used_this_month, "life": life_gain, "h": h_gain})
    return applied


def run_monthly_node(state: GameState, reg: ConfigRegistry, option_id: str) -> dict:
    """执行一次月度精力分配。option_id ∈ {A,B,C,D}。"""
    tpl_id = template_for_level(state.level)
    choice: Choice = normalize_monthly(reg, tpl_id, option_id)
    rest_applied = apply_rest(state, reg, choice.rest_points)
    choice.state_delta.pop("life_rest", None)          # 休息效果已在上面查表结算
    result = settle(state, choice, reg)
    result["template_id"] = tpl_id
    result["allocation_vector"] = choice.extra.get("allocation_vector")
    state.monthly_allocations.append({
        "month": state.month, "template_id": tpl_id, "option_id": option_id,
        "allocation_vector": choice.extra.get("allocation_vector"),
        "rest_applied": rest_applied,
        "rest_month": state.in_rest_month,
    })
    return result


def start_new_month(state: GameState) -> dict:
    """月初清算：重置休息计数器、月度自然回血、D 月末归账。"""
    state.rest_points_used_this_month = 0
    state.life = min(10, state.life + 1)               # 每月自然回 +1
    if state.pending_dignity:
        state.D += state.pending_dignity
        state.pending_dignity = 0
    # 债务优先偿还（E17 翻车产生的客户赔偿）
    if state.debt > 0:
        pay = min(state.debt, int(reg_fixed_pay()))
        state.debt -= pay
        state.money = max(0, state.money - pay)
    return {"month": state.month, "life": state.life, "D": state.D}


def reg_fixed_pay() -> int:
    """E17 欠款每月分期（默认 1667，锚点参数）。"""
    return 1667
