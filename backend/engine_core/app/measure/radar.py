# -*- coding: utf-8 -*-
"""能力雷达六柱归一化（算法册 V2.3 §9 雷达满分口径）。

满分口径（本册为准）：**按事件算**——玩家每个事件只能选一个选项，
所以每根柱的满分 = Σ 每个事件在该柱上的最优选项贡献（只取正向增量）。
数据源是主线 + 成就打分卡，月度/自由活动不进雷达（monthly.py 口径）。

⚠ 算法册 §9 表值（40/33/33/31/23/14）与 v2.9 实算（40/37/35/34/30/8）不一致，
校验器 B 段已标红待拍板；本模块**以实算为准**，表值仅存 constants.RADAR_CAP_IN_DOC。
11 个能力键 → 6 根柱的归属用 constants.RADAR_MAP（语义默认值，待确认）。

归一化：score = clamp(pillar_raw, 0, cap) / cap × 100。抗压韧性样本最薄，
报告文案须说明该柱由 H 行为记录（硬扛/危险区/休息方式）补强。
"""

from __future__ import annotations

from ..core import constants as C
from ..engine.state import GameState


def compute_caps(reg) -> dict[str, int]:
    """按事件口径实算各柱满分（与 validators.check_radar 同一算法，保证一致）：
    单键按「每个事件取该键最大正分」累计，柱分 = 柱内各键之和。"""
    per_key = {k: 0 for k in C.COMPETENCY_KEYS}
    for ev in reg.decision_events():
        best = {k: 0 for k in C.COMPETENCY_KEYS}
        for opt in ev.options.values():
            for k, v in (opt.get("competency") or {}).items():
                if v > 0 and k in best:
                    best[k] = max(best[k], int(v))
        for k, v in best.items():
            per_key[k] += v
    return {p: sum(per_key[k] for k in keys) for p, keys in C.RADAR_MAP.items()}


def build_radar(state: GameState, reg) -> list[dict]:
    caps = compute_caps(reg)
    raw = {p: sum(state.competency.get(k, 0) for k in keys)
           for p, keys in C.RADAR_MAP.items()}
    out = []
    for pillar in C.RADAR_MAP:
        cap = caps.get(pillar, 0)
        if cap <= 0:
            continue
        clamped = max(0, min(cap, raw[pillar]))
        score = round(clamped / cap * 100)
        note = ""
        if pillar == C.RADAR_THIN_PILLAR:
            note = "该柱机会少，样本由精力行为记录（硬扛/危险区/休息方式）补强。"
        out.append({
            "pillar": pillar,
            "score": score,
            "cap": cap,
            "evidence_count": len([d for d in state.decisions
                                   if d.source in ("mainline", "achievement")]),
            "note": note,
        })
    return out
