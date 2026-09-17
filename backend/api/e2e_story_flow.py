# -*- coding: utf-8 -*-
"""端到端验收：按 Godot 的真实叙事顺序走完 24 件，验「剧情 ↔ 算法」这条链路。

和 selftest.py 的分工：
  selftest.py  验**接口形状**（契约字段、幂等、404/409 语义）
  本脚本        验**编号与选项语义有没有再次错位**

2026-09-16 之前，`storyId` 靠「去掉 M 前缀」转引擎键，结果是：
  第 1–8 件 HTTP 200 静默记到别的事件名下（「技术选型」被记成「第一次被轻视」），
  第 9 件起全部 409（撞上成就节点 C1，而 Godot 侧没有这件剧情）。
本脚本把那次的每个失败点都变成断言：

  ① 已对齐的 23 件必须真的结算，落到的引擎节点与映射表逐条一致
  ② 未对齐的件必须被**明确拒绝**（409 + align=pending_rewrite），不许静默记错账
     ⚠ 24 件全部对齐后线上已无 pending 的件，这条性质改由 selftest.py ⑦b
        用临时映射表置位来守住（否则回归会悄悄失效）
  ③ Godot 自创的 1 件（M2-E08 熊熊有招训练对局）必须落库、进 completedStoryIds，但不进引擎结算
  ④ 最后逐条比对「引擎账本里的节点」vs「Godot 事件的真标题」—— 防错位的核心断言
  ⑤ Godot 源码里的 scoringKey 必须与映射表同源

用法：python backend/api/e2e_story_flow.py
"""

from __future__ import annotations

import difflib
import json
import re
import sys
import tempfile
import threading
import uuid
from http.client import HTTPConnection
from pathlib import Path

API_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(API_DIR))
sys.path.insert(0, str(API_DIR.parent / "engine_core"))

import server as srv  # noqa: E402

REPO_ROOT = API_DIR.parents[1]
MAP_PATH = REPO_ROOT / "data" / "story" / "story_key_map.json"
CARDS_PATH = REPO_ROOT / "data" / "story" / "scoring_cards.json"
WORLDCLOCK_PATH = REPO_ROOT / "scripts" / "WorldClock.gd"

_checks: list[tuple[bool, str, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    _checks.append((bool(ok), name, detail))
    print(("OK]   " if ok else "FAIL] ") + name + (f"  —— {detail}" if detail and not ok else ""))


def clean(s) -> str:
    return re.sub(r"[\s·、，。：:（）()（）\-—_/「」]", "", str(s or ""))


def similarity(a, b) -> float:
    return difflib.SequenceMatcher(None, clean(a), clean(b)).ratio()


class Client:
    def __init__(self, port: int):
        self.conn = HTTPConnection("127.0.0.1", port, timeout=10)

    def post(self, path: str, body: dict):
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.conn.request("POST", path, payload, {"Content-Type": "application/json"})
        r = self.conn.getresponse()
        raw = r.read()
        return r.status, (json.loads(raw) if raw else {})

    def close(self):
        self.conn.close()


def make_click(story_id: str, choice_id: str, region: str = "B", i: int = 0) -> dict:
    return {
        "eventId": str(uuid.uuid4()),
        "eventType": "option_click",
        "contentVersion": "v1",
        "clientTime": "2026-09-16T21:00:00+08:00",
        "payload": {"regionId": region, "storyId": story_id, "choiceId": choice_id,
                    "hesitationMs": 3000 + i, "switchCount": i % 3,
                    "snapshot": {"month": 1, "day": 1}},
    }


def main() -> int:
    mapping_raw = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    events: dict[str, dict] = {k: v for k, v in mapping_raw["events"].items()
                               if not k.startswith("_")}
    cards = json.loads(CARDS_PATH.read_text(encoding="utf-8"))

    print("=" * 92)
    print(f"映射表 v{mapping_raw.get('version')}：{len(events)} 个 Godot 事件"
          f"（对齐 {sum(1 for e in events.values() if e.get('align') == 'ok')} / "
          f"待改文案 {sum(1 for e in events.values() if e.get('align') == 'pending_rewrite')} / "
          f"不进测评 {sum(1 for e in events.values() if e.get('align') == 'non_scoring')}）")
    print("=" * 92)

    tmp = Path(tempfile.mkdtemp(prefix="wt_e2e_"))
    svc = srv.build_service(tmp / f"e2e_{uuid.uuid4().hex[:8]}.db", MAP_PATH)
    handler = type("H", (srv.Handler,), {"service": svc})
    httpd = srv.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    c = Client(httpd.server_address[1])

    code, sess = c.post("/api/v1/sessions", {"contentVersion": "v1"})
    sid = sess["sessionId"]
    check("建会话 201", code == 201)

    # ---- 按 Godot 叙事顺序逐件走（映射表的 key 就是 Godot 的顺序）
    settled: list[tuple[str, str, str]] = []      # (godotId, engineKey, choiceId)
    rejected: list[tuple[str, str]] = []
    non_scoring: list[str] = []

    for i, (gid, entry) in enumerate(events.items()):
        align = entry.get("align")
        opts = entry.get("options") or {}
        if align == "non_scoring":
            code, resp = c.post(f"/api/v1/sessions/{sid}/events", make_click(gid, f"{gid}-C01", "E", i))
            check(f"{gid} non_scoring 落库不结算", code == 200 and resp.get("accepted") is True,
                  str((code, resp))[:160])
            non_scoring.append(gid)
            continue

        # 挑一个能映射的槽位（pending 的件取第一个非 null 槽位来试，看它是否被拒）
        slot = next((s for s, v in opts.items() if v), "option_a")
        n = {"option_a": 1, "option_b": 2, "option_c": 3}[slot]
        code, resp = c.post(f"/api/v1/sessions/{sid}/events",
                            make_click(gid, f"{gid}-C{n:02d}", "B", i))

        if align == "ok":
            check(f"{gid} 已对齐 → 结算成功", code == 200 and resp.get("accepted") is True,
                  str((code, resp))[:160])
            settled.append((gid, str(entry.get("scoringKey")), slot))
        else:
            check(f"{gid} 未对齐 → 明确 409", code == 409, str((code, resp))[:160])
            check(f"{gid} 409 带 align 与原因",
                  resp.get("align") == "pending_rewrite" and bool(resp.get("todo")),
                  str(resp)[:200])
            rejected.append((gid, str(entry.get("scoringKey"))))

    print()
    print("=" * 92)
    print("引擎账本 vs Godot 真标题（防错位的核心断言）")
    print("=" * 92)
    st = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    by_engine = {d.node_id: d for d in st.decisions}

    check("结算条数 = 映射表里 align=ok 的件数",
          len(st.decisions) == len(settled),
          f"decisions={len(st.decisions)} expected={len(settled)}")

    print(f"{'Godot 事件':<11}{'Godot 标题':<20}{'引擎键':<7}{'打分卡标题':<24}{'相似':<7}判定")
    print("-" * 92)
    for gid, key, slot in settled:
        d = by_engine.get(key)
        gtitle = str(events[gid].get("title") or "")
        ctitle = str(cards.get(key, {}).get("title") or "")
        sim = similarity(gtitle, ctitle)
        ok = d is not None and sim >= 0.40
        print(f"{gid:<11}{gtitle:<20}{key:<7}{ctitle:<24}{sim:<7.2f}{'OK' if ok else '错位!'}")
        check(f"{gid} 落到 {key} 且标题对得上", ok,
              f"decision={d is not None} 相似度={sim:.2f} Godot「{gtitle}」vs 卡「{ctitle}」")

    print()
    # ---- 未对齐的件：账本里绝不能出现它们的引擎键
    banned = {k for _, k in rejected}
    hit = [k for k in banned if k in by_engine]
    check("被拒事件的引擎键没进账本（不静默记错账）", not hit, f"污染了 {hit}")

    # ---- 顺序仍然守得住：playable 走完后，再发一个已结算的 → 409
    if settled:
        last_gid = settled[-1][0]
        code, _ = c.post(f"/api/v1/sessions/{sid}/events", make_click(last_gid, f"{last_gid}-C01"))
        check("重复结算同一件 → 409", code == 409)

    code, nxt = c.post("/api/v1/sessions", {"resumeSessionId": sid})
    state = nxt["state"]
    # completedStoryIds 是「玩家走过哪些剧情」，所以 = 已结算 + non_scoring。
    # 被 409 拒掉的件没落库，本来就不该出现在这里 —— 逐条比对，不是只数个数。
    expect_ids = sorted({g for g, _, _ in settled} | set(non_scoring))
    check(f"completedStoryIds = 已结算 {len(settled)} + non_scoring {len(non_scoring)} 件",
          sorted(set(state["completedStoryIds"])) == expect_ids,
          f"实得 {sorted(set(state['completedStoryIds']))}")
    check("events_done 只含进测评的节点",
          set(st.events_done) == {k for _, k, _ in settled},
          f"{sorted(set(st.events_done))}")
    check("scoringVersion 跟打分卡走", state["scoringVersion"] == "v" + str(cards.get("version")),
          str(state["scoringVersion"]))

    print()
    # ---- Godot 源码里的 scoringKey 必须与映射表同源
    gd = WORLDCLOCK_PATH.read_text(encoding="utf-8")
    pairs = dict(re.findall(r'"id"\s*:\s*"(M\d+-[EC]\d+)",\s*"scoringKey"\s*:\s*"(\w+)"', gd))
    check(f"WorldClock.gd 里 24 件都带 scoringKey（实得 {len(pairs)}）", len(pairs) == 24)
    mismatch = []
    for gid, entry in events.items():
        want = str(entry.get("scoringKey") or "none")
        got = pairs.get(gid)
        if got != want:
            mismatch.append(f"{gid}: 源码 {got} vs 表 {want}")
    check("Godot 源码 scoringKey 与映射表逐条一致", not mismatch, "; ".join(mismatch))

    # ---- non_scoring 的件不能被误当成测评件
    # 2026-09-16 起 24 件全部进测评，non_scoring 只剩 M2-E08 一件
    extra = [g for g in non_scoring if g != "M2-E08"]
    check("non_scoring 清单符合预期", not extra, str(extra))

    c.close()
    httpd.shutdown()

    fails = [x for x in _checks if not x[0]]
    print()
    print("──────")
    print(f"检查 {len(_checks)} 项，失败 {len(fails)} 项")
    if fails:
        for _, name, detail in fails:
            print(f"FAIL] {name}  {detail}")
        return 1
    print("全部通过 ✓  剧情与算法对上了：编号不串、选项不反、未对齐不静默。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
