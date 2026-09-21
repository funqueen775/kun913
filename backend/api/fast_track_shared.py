# -*- coding: utf-8 -*-
"""快速模式共享逻辑：gen_report.py（CLI 快车道）与 server.py（HTTP 端点）共用。

提取动机：gen_report.py 顶部 `import server as srv` 依赖「server.py 不反向 import
gen_report」。server.py 作为入口运行时模块名是 __main__，gen_report 的
`import server as srv` 会把它当新模块重新加载一遍 —— 一旦 server.py 顶部
`from gen_report import ...`，就构成真循环 import（SLOT_NO 尚未定义时
gen_report 被再次 import，直接 ImportError）。把两端都要的选法/补节点逻辑
放这里，server.py 与 gen_report.py 都只依赖本模块，环就断了。
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MAP_PATH = REPO_ROOT / "data" / "story" / "story_key_map.json"

SLOT_NO = {"option_a": 1, "option_b": 2, "option_c": 3}

# v3.1 复活的三张卡 → Godot 补节点（1:1 选项映射，Godot 实现时由策划逐字对齐）
PENDING_GODOT = [
    ("M1-E02B", "E02", "第一次被轻视"),
    ("M2-E09", "E13", "跨组接口技术异议"),
    ("M2-E10", "E15", "会议上点子被抢先"),
]

# ---- demo 选法：贪心补齐五维，优先拉起 E/N 稀缺维度 ----
SCORE_CARDS = json.loads(
    (REPO_ROOT / "data" / "story" / "scoring_cards.json").read_text(encoding="utf-8"))

DEMO_TARGET = 4            # 每个 trait 想要展示到的证据条数
DEMO_EFFORT = {"E": 1.6, "N": 1.6, "A": 1.3, "O": 1.3, "C": 1.0}


def bigfive_traits(scoring_key: str, letter: str) -> list:
    if not scoring_key or not letter:
        return []
    card = SCORE_CARDS.get(scoring_key) or {}
    opt = (card.get("options") or {}).get(letter)
    return [bf.get("trait") for bf in (opt.get("bigfive") or []) if bf.get("trait")]


def extend_mapping(raw: dict) -> dict:
    """深拷贝映射表，把三件 v3.1 复活节点补进 playableOrder。

    v2.3 起正式映射表已含 M1-E02B/M2-E09/M2-E10（align=ok、已在 playableOrder），
    本函数改为幂等：节点已存在就不重复插入，保证新旧映射都能跑。
    """
    ext = json.loads(json.dumps(raw))
    ev = ext["events"]
    for gid, key, title in PENDING_GODOT:
        if gid in ev:
            continue
        ev[gid] = {
            "scoringKey": key,
            "align": "ok",
            "title": title,
            "options": {"option_a": "A", "option_b": "B", "option_c": "C"},
            "_v31": "快车道临时扩展：1:1 选项映射，正式表为 pending_godot。",
        }
    po = ext["playableOrder"]["list"]
    if "M1-E02B" not in po:
        i1 = po.index("M1-E02")                # M1-E02B 插在 M1-E01 之后、M1-E02 之前
        po.insert(i1, "M1-E02B")
    for gid in ("M2-E09", "M2-E10"):
        if gid not in po:
            po.append(gid)
    return ext


def make_click(story_id: str, choice_id: str, region: str = "B", i: int = 0) -> dict:
    return {
        "eventId": str(uuid.uuid4()),
        "eventType": "option_click",
        "contentVersion": "v1",
        "clientTime": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "payload": {"regionId": region, "storyId": story_id, "choiceId": choice_id,
                    "hesitationMs": 3000 + i, "switchCount": i % 3,
                    "snapshot": {"month": 1, "day": 1}},
    }


def demo_slot_plan(order: list, ev_all: dict) -> tuple:
    """逐件在当下最稀缺的维度上补刀（优先 E/N），返回 {gid: slot_plan} 与五维覆盖统计。
    贪心目标是让 5 个 trait 的证据都被拉起，从而使报告五维对照与交叉匹配都能展示。"""
    counts = {t: 0 for t in DEMO_EFFORT}
    chosen: dict[str, str] = {}
    for gid in order:
        entry = ev_all[gid]
        slotmap = entry.get("options") or {}
        if entry.get("align") == "non_scoring":
            chosen[gid] = "option_a"
            continue
        slots = [s for s, v in slotmap.items() if v] or ["option_a"]
        best, best_score = slots[0], None
        for slot in slots:
            letter = slotmap.get(slot, slot)
            uniq = set(bigfive_traits(entry.get("scoringKey"), letter))
            score = sum(DEMO_EFFORT.get(t, 1.0) * max(0, DEMO_TARGET - counts[t])
                        for t in uniq)
            if not uniq:
                score -= 1.0  # 无大五标记的选项，仅在全是空标记时才兜底选中
            if best_score is None or score > best_score:
                best, best_score = slot, score
        chosen[gid] = best
        for t in bigfive_traits(entry.get("scoringKey"), slotmap.get(best, best)):
            counts[t] += 1
    return chosen, counts
