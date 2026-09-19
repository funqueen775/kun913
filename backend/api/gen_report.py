# -*- coding: utf-8 -*-
"""报告快车道：不玩 48 个月，几秒钟出一份真实引擎报告。

原理与 e2e_story_flow.py 同一套服务层：进程内 Service（临时 SQLite），
按 story_key_map 的 playableOrder 逐件结算剧情事件（纯计算，无网络、无界面），
然后 POST 生成报告并落盘。报告内容 = 玩家真正玩完后 GET /report 拿到的同一份。

⚠ 27 件口径（2026-09-19，v2.3）：正式 story_key_map.json 的 playableOrder 已含全部
27 件（26 件进测评 + M2-E08 非测评），M1-E02B/M2-E09/M2-E10 三件复活节点已在
Godot WorldClock.gd 实现。extend_mapping 改为幂等：对旧映射也能在内存里补上三件，
保证快车道永远跑「设计完成态」的完整测评 —— 报告五维证据即均衡后的形态。

用法：
  python backend/api/gen_report.py                              # 默认：全部选每个事件第一个选项
  python backend/api/gen_report.py --slot last                  # 全部选最后一个选项（压力口味）
  python backend/api/gen_report.py --slot demo                  # 演示选法：贪心补齐五维（优先 E/N），五维匹配全展示
  python backend/api/gen_report.py --self C=7,A=6,O=6,E=5,N=6   # 带建档自评（出后验/矛盾度）
  python backend/api/gen_report.py --out path/to/report.json    # 自定义输出路径

默认输出到 kun913/report_out/report.json —— 网页 React 预览（web/）已删除，报告 JSON 供 Godot/后端联调或存档对比用。
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

API_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(API_DIR))
sys.path.insert(0, str(API_DIR.parent / "engine_core"))

import id_map  # noqa: E402
import server as srv  # noqa: E402

REPO_ROOT = API_DIR.parents[1]
MAP_PATH = REPO_ROOT / "data" / "story" / "story_key_map.json"
DEFAULT_OUT = REPO_ROOT / "report_out" / "report.json"

SLOT_NO = {"option_a": 1, "option_b": 2, "option_c": 3}

# v3.1 复活的三张卡 → Godot 待补节点（1:1 选项映射，Godot 实现时由策划逐字对齐）
PENDING_GODOT = [
    ("M1-E02B", "E02", "第一次被轻视"),
    ("M2-E09", "E13", "跨组接口技术异议"),
    ("M2-E10", "E15", "会议上点子被抢先"),
]


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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--slot", choices=["first", "last", "demo"], default="first",
                    help="每件事件选哪个选项：first=第一个非空槽，last=最后一个非空槽，"
                         "demo=贪心补齐五维（优先 E/N），用于展示均衡五维匹配的报告")
    ap.add_argument("--self", default=None,
                    help="建档自评，如 C=7,A=6,O=6,E=5,N=6（不传则只出行为列）")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="报告 JSON 输出路径")
    args = ap.parse_args()

    mapping_raw = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    mapping_raw = extend_mapping(mapping_raw)
    order = mapping_raw["playableOrder"]["list"]

    svc = srv.Service(
        srv.Store(Path(tempfile.mkdtemp(prefix="wt_fast_")) / f"fast_{uuid.uuid4().hex[:8]}.db"),
        srv.Engine(),
        id_map.StoryKeyMap(mapping_raw))
    code, sess = svc.create_session({"contentVersion": "v1"})
    sid = sess["sessionId"]
    print(f"映射表 v{mapping_raw.get('version')}  完整测评 {len(order)} 件"
          f"（含 v3.1 复活 {len(PENDING_GODOT)} 件）")

    # 可选：建档自评埋点（profile_answer）。报告层 _self_ratings 会吃掉它 → 出后验与矛盾度。
    if args.self:
        ratings: dict[str, float] = {}
        for part in args.self.split(","):
            k, v = part.split("=")
            ratings[k.strip().upper()] = float(v)
        svc.post_event(sid, {
            "eventId": str(uuid.uuid4()), "eventType": "profile_answer",
            "contentVersion": "v1",
            "clientTime": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "payload": {"regionId": "A", "ratings": ratings}})
        print(f"建档自评：{ratings}")

    settled, skipped = 0, 0
    ev_all = mapping_raw["events"]
    demo_plan = demo_slot_plan(order, ev_all)[0] if args.slot == "demo" else None
    for i, gid in enumerate(order):
        entry = ev_all[gid]
        opts = entry.get("options") or {}
        if args.slot == "demo":
            slot = demo_plan[gid]
        elif entry.get("align") == "non_scoring":
            slot = "option_a"
        else:
            slots = [s for s, v in opts.items() if v] or ["option_a"]
            slot = slots[-1] if args.slot == "last" else slots[0]
        cid = f"{gid}-C{SLOT_NO.get(slot, 1):02d}"
        code, resp = svc.post_event(sid, make_click(gid, cid, "B", i))
        if code == 200 and resp.get("accepted") is True:
            if entry.get("align") == "non_scoring":
                skipped += 1
            else:
                settled += 1
        else:
            print(f"!! {gid} 未按预期推进：HTTP {code} {str(resp)[:140]}")
            return 1

    st = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    print(f"结算 {settled} 个测评事件（另有 {skipped} 件非测评剧情落库）"
          f"  月份推进到第 {st.month} 月  职级 L{st.level}")

    code, resp = svc.generate_report(sid)
    if code != 202 or resp.get("status") != "ready":
        print(f"!! 报告生成失败：{resp}")
        return 1
    code, report = svc.get_report(sid)
    if code != 200:
        print(f"!! 拉取报告失败：HTTP {code}")
        return 1

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"报告已写出：{out}")

    print("\n── 速览（对照整改项）──")
    p = report["layers"]["persona"]
    print("雷达（pillar score/cap）:")
    for r in p["radar"]:
        mark = "  ← 上限<15 有弱标注" if r["cap"] < 15 else ""
        print(f"  {r['pillar']:<6} {r['score']:>3} / {r['cap']:>3}{mark}")
    print("大五：")
    for r in p["bigfive"]:
        if r["behaviorAvailable"]:
            print(f"  {r['traitCn']}: 行为 {r['behavior']}（{r['evidenceCount']} 条证据）")
        else:
            print(f"  {r['traitCn']}: 证据不足({r['evidenceCount']})→已降级不出结论")
    print("专题（只列会渲染的）:")
    shown = [t for t in p["topics"] if t["displayable"]]
    if shown:
        for t in shown:
            print(f"  {t['key']} (n={t['n']})")
    else:
        print("  （无）")
    hidden = [t["key"] for t in p["topics"] if not t["displayable"]]
    if hidden:
        print(f"隐藏模块（n<门槛）：{hidden}")
    if args.slot == "demo":
        cov = demo_slot_plan(order, ev_all)[1]
        print("demo 行为证据覆盖（按所选项大五标记累计）："
              + " | ".join(f"{t}×{cov[t]}" for t in ["C", "A", "N", "O", "E"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
