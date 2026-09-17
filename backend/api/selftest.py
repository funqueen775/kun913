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
    # 映射表 playableOrder 的下一件是 M1-E02（Godot 的六幕叙事顺序）。
    # 2026-09-16 之前 M1-E02 是 pending_rewrite、被排除在可承接链外，所以这里原本是 M1-E03；
    # 现在 24 件全部对齐，链 = 完整叙事顺序。
    check("nextNodeId 指向 M1-E02", resp.get("nextNodeId") == "M1-E02", str(resp.get("nextNodeId")))

    # ---- ⑤ 幂等：同一 eventId 重发 → duplicate=true、状态不变
    code, dup = c.req("POST", f"/api/v1/sessions/{sid}/events", ev)
    check("同 eventId 重发 duplicate=true", code == 200 and dup.get("duplicate") is True)
    check("重发后 completedStoryIds 不重复增长",
          dup["state"]["completedStoryIds"].count("M1-E01") == 1
          and dup["state"]["completedStoryIds"] == resp["state"]["completedStoryIds"])

    # ---- ⑥ 顺序冲突：跳过 M1-E03 直接报 M2-E06 → 409
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M2-E06", "M2-E06-C01"))
    check("跳事件 409", code == 409, str((code, resp)))

    # ---- ⑦ M1-E02 已于 2026-09-16 对齐：option_b 改写成「先找王哥聊聊…」后落在 E04 的 C
    # （C 是 E04 唯一的协作锚点，N+2 / S+1 保住了）。现在必须 200 并记成 E04-C。
    # 修复前它会按 E02「第一次被轻视」的载荷，把「技术选型」这四个字记进账本 ——
    # 善意选项被算成越界选项，且全程不报错。
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M1-E02", "option_b", hesitation=8642, switch=2))
    check("M1-E02 已对齐：200 进测评", code == 200 and resp.get("accepted") is True,
          str((code, resp)))
    st_probe = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    e04 = next((d for d in st_probe.decisions if d.node_id == "E04"), None)
    check("M1-E02 option_b 落到 E04 的 C（协作锚点）",
          e04 is not None and e04.option_id == "C", str(e04 and e04.option_id))
    check("账本里没有 E02（旧口径把善意选项记成越界）",
          all(d.node_id != "E02" for d in st_probe.decisions),
          str([d.node_id for d in st_probe.decisions]))

    # ---- ⑦b 「编号对上、选项没对上 → 409 并且把原因说清楚」这条性质
    # 24 件全部对齐以后，线上已经没有任何 pending_rewrite 的件了，
    # 这条回归会悄悄失效 —— 所以用临时映射表把 M1-E02 置回 pending 来守住它。
    # 核心是：宁可 409，也绝不退回「按同名选项猜着记分」。
    p_map = tmp / "map_pending.json"
    praw = json.loads(srv.STORY_KEY_MAP_PATH.read_text(encoding="utf-8"))
    praw["events"]["M1-E02"]["align"] = "pending_rewrite"
    praw["events"]["M1-E02"]["_todo"] = "（自检临时置位）验证 409 通道没有被 24 件对齐冲掉"
    p_map.write_text(json.dumps(praw, ensure_ascii=False), encoding="utf-8")
    svc_p = srv.build_service(tmp / "pending.db", p_map)
    httpd_p = srv.ThreadingHTTPServer(("127.0.0.1", 0),
                                      type("HP", (srv.Handler,), {"service": svc_p}))
    cp = Client(httpd_p.server_address[1])
    threading.Thread(target=httpd_p.serve_forever, daemon=True).start()
    _, sp = cp.req("POST", "/api/v1/sessions", {"contentVersion": "v1"})
    cp.req("POST", f"/api/v1/sessions/{sp['sessionId']}/events",
           make_event("M1-E01", "M1-E01-C01"))
    code, rp = cp.req("POST", f"/api/v1/sessions/{sp['sessionId']}/events",
                      make_event("M1-E02", "option_b", hesitation=8642, switch=2))
    check("未对齐事件 409", code == 409, str((code, rp)))
    check("409 带 align=pending_rewrite 与原因",
          rp.get("align") == "pending_rewrite" and rp.get("scoringKey") == "E04"
          and bool(rp.get("todo")), str(rp))
    st_p = srv.Engine.state_from_json(svc_p.store.get_session(sp["sessionId"])["state_json"])
    check("被拒事件没有污染引擎账本",
          all(d.node_id not in ("E02", "E04") for d in st_p.decisions),
          str([d.node_id for d in st_p.decisions]))
    cp.close()
    httpd_p.shutdown()

    # ---- ⑧ Godot 自创事件（non_scoring）：玩家做完了剧情，落库但不进测评
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M2-E08", "M2-E08-C01", region="E"))
    check("non_scoring 事件 accepted", code == 200 and resp.get("accepted") is True,
          str((code, resp)))
    check("non_scoring 进 completedStoryIds",
          "M2-E08" in resp["state"]["completedStoryIds"],
          str(resp["state"]["completedStoryIds"]))
    st_ns = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    check("non_scoring 不结算：seq 不变、events_done 不变",
          st_ns.seq == st_probe.seq and st_ns.events_done == st_probe.events_done,
          f"seq {st_probe.seq}->{st_ns.seq}")

    # ---- ⑧b 坏 payload：缺 regionId / 坏 choiceId / 坏 JSON
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

    # ---- ⑨ 顺序补上 M1-E03（叙事流埋点先来一条，只落日志）
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("region_entered_extra", "", event_type="region_entered",
                                  region="B"))
    check("叙事埋点只落日志也 accepted", code == 200 and resp.get("accepted") is True)
    # 注意用 option_b：映射表里 M1-E03 的 option_b → 引擎 C（B/C 是互换的）。
    # 这条断言就是「选项语义对齐真的生效」—— 发 option_b 必须落到 C，不是 B。
    code, resp = c.req("POST", f"/api/v1/sessions/{sid}/events",
                       make_event("M1-E03", "option_b", hesitation=3000, switch=0))
    check("M1-E03 顺序通过", code == 200 and resp.get("accepted") is True, str((code, resp)))
    st_m13 = srv.Engine.state_from_json(svc.store.get_session(sid)["state_json"])
    e05 = next((d for d in st_m13.decisions if d.node_id == "E05"), None)
    check("选项映射生效：option_b 落到引擎 C（B/C 互换）",
          e05 is not None and e05.option_id == "C", str(e05 and e05.option_id))

    # ---- ⑩ NPC 记忆：四层推导、schema 对齐 fixture、404
    code, mem = c.req("GET", f"/api/v1/sessions/{sid}/npcs/wang_ge/memories")
    want = fixture("npc-memories.json")
    check("memories 200", code == 200)
    check("NpcMemoriesResponse 字段对齐契约",
          set(mem.keys()) >= set(want.keys()) - {"items"}
          and all(set(i.keys()) >= {"npcId", "layer", "kind", "month", "fact", "eventRef"}
                  for i in mem["items"]), str(mem)[:200])
    check("relationStage 是 Lv 枚举", mem["relationStage"] in {"Lv1", "Lv2", "Lv3", "Lv4", "Lv5"})
    # E01-B 的 memory_tags 是「先看人」；E05-C 本来就无标签（打分卡里就空），
    # 所以断言只认 E01 那条，另外查 eventRef 是否指回客户端上报的 eventId。
    check("fact 层推到 E01 的记忆标签「先看人」",
          any("先看人" in str(i.get("fact", "")) for i in mem["items"]),
          str(mem["items"])[:240])
    check("fact 层 eventRef 指回客户端 eventId",
          bool(mem["items"]) and all(i.get("eventRef") for i in mem["items"]),
          str(mem["items"])[:240])
    code, _ = c.req("GET", f"/api/v1/sessions/{sid}/npcs/nobody/memories")
    check("未知 npcId 404", code == 404)
    code, mem_f = c.req("GET", f"/api/v1/sessions/{sid}/npcs/wang_ge/memories?layers=fact&limit=2")
    check("layers/limit 过滤生效", code == 200 and len(mem_f["items"]) <= 2
          and all(i["layer"] == "fact" for i in mem_f["items"]))

    # ---- ⑪ next 端点：形状对齐 fixture next-m1-e01.json
    code, nxt = c.req("GET", f"/api/v1/sessions/{sid}/next")
    nxt_shape = fixture("next-m1-e01.json")
    # 已上报 M1-E01 / M1-E02 / M1-E03，playableOrder 的下一件是 M1-E04（E08）。
    # 2026-09-16 前 M1-E02 被排除在链外，所以这里原本断到 M2-E06。
    check("next 200 且 nodeId=M1-E04", code == 200 and nxt["nodeId"] == "M1-E04",
          str(nxt.get("nodeId")))
    check("NextResponse 字段对齐契约", set(nxt.keys()) >= set(nxt_shape.keys()))
    check("next 的 choiceId 用客户端叙事口径",
          bool(nxt.get("choices"))
          and all(str(ch["choiceId"]).startswith(nxt["nodeId"] + "-C")
                  for ch in nxt.get("choices", [])),
          str(nxt.get("choices")))

    # ---- ⑪b 纯叙事成就节点（C1/C2/C3）的推进通道
    # 这三件 no_decision=True、options 为空，永远走不进选择通道。
    # Godot 侧还没写 C1 的剧情，但这条后端通道必须现在就可验证 ——
    # 否则等补剧情时才发现「走完第 8 件就再也过不去」。
    # ⚠ 24 件基准下 C1-C4 已从 scoring_cards 的 _index 摘出（卡数据仍在文件里），
    # 所以这里除了临时映射表，还要按 loader 同样的方式把 C1 补回引擎的登记表。
    # 这里另起一套服务：独立库 + 把 C1 放进 playableOrder 的临时映射表。
    tmp_map = tmp / "map_with_c1.json"
    mraw = json.loads(srv.STORY_KEY_MAP_PATH.read_text(encoding="utf-8"))
    mraw["events"]["C1"] = {"scoringKey": "C1", "align": "ok",
                            "title": "你的第一个 demo 跑通了", "options": {}}
    mraw["playableOrder"]["list"] = ["C1"] + list(mraw["playableOrder"]["list"])
    tmp_map.write_text(json.dumps(mraw, ensure_ascii=False), encoding="utf-8")

    svc2 = srv.build_service(tmp / "c1.db", tmp_map)
    from app.core.loader import EventDef
    svc2.engine.reg.events["C1"] = EventDef(
        event_id="C1", raw=svc2.engine.reg.cards["C1"], index=0)
    handler2 = type("H2", (srv.Handler,), {"service": svc2})
    httpd2 = srv.ThreadingHTTPServer(("127.0.0.1", 0), handler2)
    c2 = Client(httpd2.server_address[1])
    threading.Thread(target=httpd2.serve_forever, daemon=True).start()
    code, s2 = c2.req("POST", "/api/v1/sessions", {"contentVersion": "v1"})
    sid2 = s2["sessionId"]

    code, r = c2.req("POST", f"/api/v1/sessions/{sid2}/events",
                     make_event("C1", "-", event_type="achievement_view"))
    check("成就节点 achievement_view 推进 200",
          code == 200 and r.get("accepted") is True, str((code, r)))
    st2 = srv.Engine.state_from_json(svc2.store.get_session(sid2)["state_json"])
    check("C1 进 events_done", "C1" in st2.events_done, str(st2.events_done))
    check("成就演出不测评：seq 仍为 0、decisions 仍为空",
          st2.seq == 0 and len(st2.decisions) == 0,
          f"seq={st2.seq} decisions={len(st2.decisions)}")
    check("成就推进后 nextNodeId 指向 M1-E01", r.get("nextNodeId") == "M1-E01",
          str(r.get("nextNodeId")))
    # 顺序仍然守住：C1 完成后重复发 → 状态不变；跳过它发 M1-E01 之前也不该乱
    code, r2 = c2.req("POST", f"/api/v1/sessions/{sid2}/events",
                      make_event("C1", "-", event_type="achievement_view"))
    check("成就节点可重复上报（幂等推进）", code == 200, str((code, r2)))
    c2.close()
    httpd2.shutdown()

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
    # M1-E01 / M1-E02 / M1-E03 三条进测评；M2-E08 是 non_scoring，不算。
    check("决策数与上报一致（3 条进测评的主线，M2-E08 不算）",
          report.get("decisionCount") == 3, str(report.get("decisionCount")))

    # ---- ⑬ 报告路由（HTTP 级）：契约四态与幂等必须真的从路由走得通
    # 上面 ⑫ 是直接调 build()（验算法），这里验的是「路由把算法接上了没」。
    code, _ = c.req("GET", f"/api/v1/sessions/{sid}/report")
    check("未生成时 GET /report 404", code == 404, str(code))
    code, st_pre = c.req("GET", f"/api/v1/sessions/{sid}/report/status")
    check("未生成时 status 200 pending",
          code == 200 and st_pre.get("status") == "pending", str((code, st_pre)))

    code, post1 = c.req("POST", f"/api/v1/sessions/{sid}/report")
    check("POST /report 202 且同步 ready（纯模板无大模型，不伪造中间态）",
          code == 202 and post1.get("status") == "ready", str((code, post1)))

    code, post2 = c.req("POST", f"/api/v1/sessions/{sid}/report")
    check("POST /report 幂等：重复请求返同一 handle",
          code == 202 and post2.get("sessionId") == sid
          and post2.get("status") == "ready", str((code, post2, sid)))

    code, rep_http = c.req("GET", f"/api/v1/sessions/{sid}/report")
    check("ready 后 GET /report 200", code == 200, str(code))
    check("GET /report 三层结构齐",
          {"persona", "market", "crossHints"} <= set(rep_http.get("layers", {})),
          str(list(rep_http.get("layers", {}).keys())))
    check("GET /report 回填 sessionId 与 decisionCount",
          rep_http.get("sessionId") == sid and rep_http.get("decisionCount") == 3,
          str((rep_http.get("sessionId"), rep_http.get("decisionCount"))))

    code, st_post = c.req("GET", f"/api/v1/sessions/{sid}/report/status")
    check("生成后 status 200 ready",
          code == 200 and st_post.get("status") == "ready", str((code, st_post)))

    # 未知会话三条路由都要 404，不能因为「没有 reports 行」就 500
    ghost = uuid.uuid4()
    codes = [c.req("GET", f"/api/v1/sessions/{ghost}/report")[0],
             c.req("GET", f"/api/v1/sessions/{ghost}/report/status")[0],
             c.req("POST", f"/api/v1/sessions/{ghost}/report")[0]]
    check("未知会话报告三路由 404", codes == [404, 404, 404], str(codes))

    # ---- ⑮ 在场一幕上报：encounter_choice 落库 → 报告 encounterEchoes 回声
    # B 件的性格标签走通后端：报告的 encounterEchoes 能区分「会先开口的人」和「想自己待着的人」。
    # 用全新会话：报告幂等（ready 后不重建），sid 在 ⑬ 已出过片。
    code, s4 = c.req("POST", "/api/v1/sessions", {"contentVersion": "v1"})
    sid4 = s4["sessionId"]
    post_ok = True
    for i, (opt, tag) in enumerate([("A", "会先开口的人"),
                                    ("A", "会先开口的人"),
                                    ("C", "想自己待着")]):
        code, r = c.req("POST", f"/api/v1/sessions/{sid4}/events", {
            "eventId": str(uuid.uuid4()),
            "eventType": "encounter_choice",
            "contentVersion": "v1",
            "clientTime": "2026-09-17T12:00:00+08:00",
            "payload": {"regionId": "C", "activityId": "D1_coffee_chat",
                        "optionId": opt, "npcId": "xiao_lin",
                        "memoryTags": [tag], "month": 9 + i},
        })
        if code != 200 or not r.get("accepted"):
            post_ok = False
            break
    check("encounter_choice 上报 accepted", post_ok, str((code, r)))
    code, rep4_pre = c.req("POST", f"/api/v1/sessions/{sid4}/report")
    check("encounter 会话报告 ready", rep4_pre.get("status") == "ready", str(rep4_pre))
    code, rep4 = c.req("GET", f"/api/v1/sessions/{sid4}/report")
    echoes = (rep4.get("layers", {}).get("persona", {}).get("encounterEchoes") or {})
    check("报告 encounterEchoes.n = 上报幕数", echoes.get("n") == 3, str(echoes))
    check("标签按频次聚合、最高频在前",
          bool(echoes.get("tags")) and echoes["tags"][0]["tag"] == "会先开口的人"
          and echoes["tags"][0]["n"] == 2, str(echoes.get("tags")))
    check("回声一句话带上 top 标签", "会先开口的人" in echoes.get("line", ""),
          str(echoes.get("line")))
    check("标签零数字（红线：只记性格标签，不落任何分）",
          not any(ch.isdigit() for t in echoes.get("tags", []) for ch in str(t.get("tag", ""))),
          str(echoes.get("tags")))
    # 对照：⑬ 那个会话从没上报过在场一幕 → n=0、line 空串（无据不推断）
    zero = (rep_http.get("layers", {}).get("persona", {}).get("encounterEchoes")
            if isinstance(rep_http, dict) else {})
    check("没上报过应答的会话 n=0、line 空串（不做补偿性推断）",
          isinstance(zero, dict) and zero.get("n") == 0 and zero.get("line") == "",
          str(zero))

    # ---- ⑭ 未知会话 404
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
