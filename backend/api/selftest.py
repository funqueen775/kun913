# -*- coding: utf-8 -*-
"""M4 最小服务自测：用 contracts/fixtures/ 的样例打真 HTTP。

跑法（引擎零依赖，标准库即可）：
  python backend/api/selftest.py

要点：
  - 每次跑用一个全新 DB 文件（本机新文件约 5 分钟后被锁，见 server.py 头注）。
  - 起真 ThreadingHTTPServer（随机端口），http.client 打请求，测的就是线上路径。
  - 覆盖：建会话、幂等、409 顺序冲突、400 坏 payload、404、犹豫埋点进引擎、
    记忆四层推导、resumeSessionId 续接、报告层用真实结算状态出片。
"""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import uuid
from http.client import HTTPConnection
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import server as srv  # noqa: E402

FIXTURES = HERE.parents[1] / "contracts" / "fixtures"

_checks: list[tuple[bool, str, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    _checks.append((bool(ok), name, detail))
    print(("OK]   " if ok else "FAIL] ") + name + (f"  —— {detail}" if detail and not ok else ""))


class Client:
    def __init__(self, port: int):
        self.conn = HTTPConnection("127.0.0.1", port, timeout=10)

    def req(self, method: str, path: str, body: dict | None = None):
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
        headers = {"Content-Type": "application/json"} if payload else {}
        self.conn.request(method, path, payload, headers)
        resp = self.conn.getresponse()
        raw = resp.read()
        return resp.status, json.loads(raw) if raw else {}

    def close(self):
        self.conn.close()


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def make_event(story_id: str, choice_id: str, *, event_type: str = "main_choice",
               hesitation=None, switch=None, region: str = "A") -> dict:
    ev = fixture("event-main-choice.json")
    ev["eventId"] = str(uuid.uuid4())
    ev["eventType"] = event_type
    ev["payload"] = {**ev["payload"], "regionId": region,
                     "storyId": story_id, "choiceId": choice_id}
    if hesitation is not None:
        ev["payload"]["hesitationMs"] = hesitation
    if switch is not None:
        ev["payload"]["switchCount"] = switch
    return ev


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="wt_api_selftest_"))
    db = tmp / f"selftest_{uuid.uuid4().hex[:8]}.db"

    svc = srv.build_service(db)
    handler = type("H", (srv.Handler,), {"service": svc})
    httpd = srv.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = httpd.server_address[1]
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    c = Client(port)

    # ---- ① health
    code, resp = c.req("GET", "/api/v1/health")
    check("health 200", code == 200 and resp.get("status") == "ok")

    # ---- ② 建会话：形状对齐 fixture session-created.json
    code, sess = c.req("POST", "/api/v1/sessions", {"contentVersion": "v1"})
    shape = fixture("session-created.json")
    sid = sess.get("sessionId", "")
    check("建会话 201", code == 201)
    check("SessionResponse 字段对齐契约",
          set(sess.keys()) >= {"sessionId", "contentVersion", "state"}
          and set(sess["state"].keys()) >= set(shape["state"].keys()),
          str(list(sess.get("state", {}).keys())))
    check("初始 currentNodeId=M1-E01", sess["state"]["currentNodeId"] == "M1-E01")

    # ---- ③ resume：不存在的 → 404；存在的 → 200 同一会话
    code, _ = c.req("POST", "/api/v1/sessions", {"resumeSessionId": str(uuid.uuid4())})
    check("resume 未知会话 404", code == 404)
    code, sess2 = c.req("POST", "/api/v1/sessions", {"resumeSessionId": sid})
    check("resume 续接 200 同 sessionId", code == 200 and sess2["sessionId"] == sid)

    # ---- ④ fixture 原样事件：M1-E01 + M1-E01-C02（契约口径）→ 引擎 E01 选 B
    ev = fixture("event-main-choice.json")
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events", ev)
    check("fixture 事件 200 accepted", code == 200 and resp.get("accepted") is True)
    check("完成后 completedStoryIds 含 M1-E01",
          "M1-E01" in resp["state"]["completedStoryIds"], str(resp["state"]["completedStoryIds"]))
    check("nextNodeId 指向 M1-E02", resp.get("nextNodeId") == "M1-E02", str(resp.get("nextNodeId")))

    # ---- ⑤ 幂等：同一 eventId 重发 → duplicate=true、状态不变
    code, dup = c.req("POST", f"/api/v1/sessions/{sid}/events", ev)
    check("同 eventId 重发 duplicate=true", code == 200 and dup.get("duplicate") is True)
    check("重发后 completedStoryIds 不重复增长",
          dup["state"]["completedStoryIds"].count("M1-E01") == 1
          and dup["state"]["completedStoryIds"] == resp["state"]["completedStoryIds"])

    # ---- ⑥ 顺序冲突：跳过 E02 直接报 E03 → 409
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M1-E03", "M1-E03-C01"))
    check("跳事件 409", code == 409, str((code, resp)))

    # ---- ⑦ 前端口径：option_b + 犹豫/横跳埋点（Godot 将来发的那种）
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M1-E02", "option_b", hesitation=8642, switch=2))
    check("前端 option_b 口径 accepted", code == 200 and resp.get("accepted") is True,
          str((code, resp)))
    # 引擎真的吃到了犹豫：从快照里把 DecisionRecord 翻出来
    st = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    e02 = next((d for d in st.decisions if d.node_id == "E02"), None)
    check("犹豫埋点进引擎 DecisionRecord",
          e02 is not None and e02.hesitation_ms == 8642 and e02.switch_count == 2,
          str(e02 and (e02.hesitation_ms, e02.switch_count)))
    # E01-B（fixture 事件映射到 B）带 memory_tags「先看人」——算法层的原料
    check("memory_tags 随结算进状态（算法层原料）",
          any(t["node"] == "E01" and t["tag"] == "先看人" for t in st.memory_tags),
          str(st.memory_tags[:3]))

    # ---- ⑧ 坏 payload：缺 regionId / 坏 choiceId / 坏 JSON
    bad = make_event("M1-E03", "M1-E03-C01")
    bad["payload"].pop("regionId")
    code, _ = c.req("POST", f"/api/v1/sessions/{sid}/events", bad)
    check("缺 regionId 400", code == 400)
    code, _ = c.req("POST", f"/api/v1/sessions/{sid}/events",
                    make_event("M1-E03", "M1-E03-C99"))
    check("未知 choiceId 400", code == 400)
    code, _ = c.req("POST", f"/api/v1/sessions/{sid}/events",
                    make_event("M9-XX99", "M9-XX99-C01"))
    check("未知 storyId 400", code == 400)

    # ---- ⑨ 顺序补上 E03（叙事流埋点先来一条，只落日志）
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("region_entered_extra", "", event_type="region_entered",
                                  region="B"))
    check("叙事埋点只落日志也 accepted", code == 200 and resp.get("accepted") is True)
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M1-E03", "M1-E03-C02", hesitation=3000, switch=0))
    check("E03 顺序通过", code == 200 and resp.get("accepted") is True, str((code, resp)))

    # ---- ⑩ NPC 记忆：四层推导、schema 对齐 fixture、404
    code, mem = c.req("GET", f"/api/v1/sessions/{sid}/npcs/wang_ge/memories")
    want = fixture("npc-memories.json")
    check("memories 200", code == 200)
    check("NpcMemoriesResponse 字段对齐契约",
          set(mem.keys()) >= set(want.keys()) - {"items"}
          and all(set(i.keys()) >= {"npcId", "layer", "kind", "month", "fact", "eventRef"}
                  for i in mem["items"]), str(mem)[:200])
    check("relationStage 是 Lv 枚举", mem["relationStage"] in {"Lv1", "Lv2", "Lv3", "Lv4", "Lv5"})
    check("fact 层有 E01/E03 的记忆标签（E02-B 本就无标签）",
          len(mem["items"]) >= 2, str(len(mem["items"])))
    code, _ = c.req("GET", f"/api/v1/sessions/{sid}/npcs/nobody/memories")
    check("未知 npcId 404", code == 404)
    code, mem_f = c.req("GET", f"/api/v1/sessions/{sid}/npcs/wang_ge/memories?layers=fact&limit=2")
    check("layers/limit 过滤生效", code == 200 and len(mem_f["items"]) <= 2
          and all(i["layer"] == "fact" for i in mem_f["items"]))

    # ---- ⑪ next 端点：形状对齐 fixture next-m1-e01.json
    code, nxt = c.req("GET", f"/api/v1/sessions/{sid}/next")
    nxt_shape = fixture("next-m1-e01.json")
    check("next 200 且 nodeId=M1-E04", code == 200 and nxt["nodeId"] == "M1-E04",
          str(nxt.get("nodeId")))
    check("NextResponse 字段对齐契约", set(nxt.keys()) >= set(nxt_shape.keys()))

    # ---- ⑫ 算法真的跑起来：报告层吃真实结算状态出片（重读最新快照，含 E03）
    from app.engine import simulation as sim
    from app.core.loader import load as load_cfg
    from app.report import build as build_report
    reg = load_cfg(srv.REPO_ROOT / "data" / "story")
    st_final = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    result = sim.RunResult(state=st_final, log=sim.RunLog())
    report = build_report(result, reg)
    persona = report.get("layers", {}).get("persona", {})
    big5 = persona.get("bigfive", [])
    check("报告层三层结构齐", {"persona", "market", "crossHints"} <= set(report.get("layers", {})),
          str(list(report.get("layers", {}).keys())))
    check("大五证据来自真实选择（evidenceCount>0）",
          any(t.get("evidenceCount", 0) > 0 for t in big5),
          str([(t.get("trait"), t.get("evidenceCount")) for t in big5]))
    check("决策数与上报一致（3 条主线）", report.get("decisionCount") == 3,
          str(report.get("decisionCount")))

    # ---- ⑬ 未知会话 404
    code, _ = c.req("GET", f"/api/v1/sessions/{uuid.uuid4()}")
    check("未知会话 404", code == 404)

    c.close()
    httpd.shutdown()

    fails = [x for x in _checks if not x[0]]
    print("\n──────")
    print(f"检查 {len(_checks)} 项，失败 {len(fails)} 项")
    if fails:
        for _, name, detail in fails:
            print(f"FAIL] {name}  {detail}")
        return 1
    print("全部通过 ✓  契约有可执行体了。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
