# -*- coding: utf-8 -*-
"""自由周末：每 3 个月 1 个，共 16 次。内容由玩家自选。

口径（free_time_system.json v1.3 / 剧情册 §11）：
  - 天气 80% 晴 / 20% 雨；雨天且与某 NPC 同出口时 D6 共伞可触发（彩蛋）
  - 收益递减：同一 NPC 连续 3 次后 ×0.5（前端文案「他有点意外你又来了」）
  - 知心时刻：每 NPC 一次性，触发后 D2/D4 降为普通深谈（好感 +5）
  - 数值隐藏：好感度、等级、解锁条件一律不下发前端
  - 不做橡皮筋：绝不因玩家处境自动调整活动收益权重
"""

from __future__ import annotations

import random

from ..core import constants as C
from ..core.loader import ConfigRegistry
from .settlement import normalize_freetime, normalize_freetime_decision, settle
from .state import GameState


def weather_for(reg: ConfigRegistry, rng: random.Random) -> str:
    dist = reg.free_time.get("weather", {}).get("distribution", C.WEATHER_DIST)
    return "rainy" if rng.random() < float(dist.get("rainy", 0.2)) else "sunny"


def available_activities(reg: ConfigRegistry, state: GameState, month: int, weather: str) -> list[dict]:
    """可用活动池：按局解锁（第 1/2/3 局 = 月 1-16 / 17-32 / 33-48）。"""
    game = 1 if month <= 16 else (2 if month <= 32 else 3)
    out = []
    for a in reg.activities:
        if int(a.get("unlock_game", 1)) > game:
            continue
        if a.get("auto_trigger"):                      # 自动触发剧情（D6）不进自选池
            continue
        if a.get("weather_req") == "rainy" and weather != "rainy":
            continue
        out.append(a)
    return out


def _effective_multiplier(state: GameState, npc: str, slot: int) -> float:
    """收益递减：同一 NPC 连续 3 次后 ×0.5。"""
    recent = state.npc_last_slots.get(npc, [])[-C.DIMINISHING_SAME_NPC:]
    if len(recent) >= C.DIMINISHING_SAME_NPC:
        return C.DIMINISHING_MULTIPLIER
    return 1.0


def run_free_weekend(state: GameState, reg: ConfigRegistry, rng: random.Random,
                     activity_id: str, slot_index: int,
                     target_npc: str | None = None,
                     decision_option: str | None = None) -> dict:
    """执行一个自由周末：活动本体 → （若有）小决策 → 好感度结算。"""
    month = state.month
    weather = weather_for(reg, rng)
    act = reg.activity(activity_id)
    if act is None:
        raise KeyError(f"未知活动 {activity_id}")

    events = []

    # ① 活动本体（低权重；工作型活动带 sdt）
    body = normalize_freetime(reg, activity_id)
    events.append(settle(state, body, reg))

    # ② 好感（活动级）
    aff = []
    gain_spec = act.get("affinity_gain")
    if gain_spec is not None and target_npc:
        ps = act.get("party_size", 1)
        ps = ps if isinstance(ps, (int, float)) else 1     # 部分活动写的是 "team" 之类的描述值
        raw = 0
        if isinstance(gain_spec, dict):
            raw = int(gain_spec.get("each", 0)) * int(ps)
        elif isinstance(gain_spec, int):
            raw = gain_spec
        eff = int(round(raw * _effective_multiplier(state, target_npc, slot_index)))
        if eff:
            aff.append(state.npc_add(target_npc, eff, reason=activity_id))
            state.npc_last_slots.setdefault(target_npc, []).append(slot_index)

    # ③ 小决策（4 个决策点活动）
    if decision_option and act.get("decision"):
        choice = normalize_freetime_decision(reg, activity_id, decision_option)
        for a in choice.affinity_list:
            npc = a.get("npc")
            if npc in (None, "party", "party_each"):
                npc = target_npc
            if npc:
                aff.append(state.npc_add(npc, int(a.get("delta", 0)),
                                         reason=f"{activity_id}.{decision_option}"))
        events.append(settle(state, choice, reg))

    # ④ 知心时刻（每 NPC 一次性；触发后 D2/D4 降为普通深谈 +5）
    if target_npc and target_npc not in state.intimate_done:
        if state.npc_affinity.get(target_npc, 0) >= 40 and activity_id in (
                "D2_lakeside_deep_talk", "D4_camp_bbq"):
            state.intimate_done.append(target_npc)
            aff.append(state.npc_add(target_npc, 5, reason="intimate_moment"))

    state.npc_last_slots.setdefault(target_npc or "_", [])
    return {
        "month": month, "slot_index": slot_index, "weather": weather,
        "activity_id": activity_id, "zone": act.get("zone"),
        "activity_type": act.get("type"), "target_npc": target_npc,
        "affinity_changes": aff, "events": events,
        "instant_feedback": act.get("instant_feedback"),
    }
