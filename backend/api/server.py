# -*- coding: utf-8 -*-
"""M4 最小服务层：把 contracts/openapi.yaml 的三个核心端点变成可执行体。

范围（先让契约有能跑的实体，其余端点后续补）：
  GET  /api/v1/health                                    存活检查
  POST /api/v1/sessions                                  建会话（支持 resumeSessionId 续接）
  GET  /api/v1/sessions/{sid}                            读权威会话状态
  GET  /api/v1/sessions/{sid}/next                       下一个可玩节点
  POST /api/v1/sessions/{sid}/events                     幂等上报（主线选择真正进引擎结算）
  GET  /api/v1/sessions/{sid}/npcs/{npcId}/memories      NPC 记忆（事件流推导，只读）

设计要点：
  - 只用标准库（http.server + sqlite3），与 engine_core 的零依赖口径一致；FastAPI 是后续升级项。
  - 引擎状态以 JSON 快照存在 sessions.state_json，每结算一条主线事件推进一次；
    重启不丢，且与「跑批可复算」精神一致（事件流重放可还原同一状态）。
  - 主线事件按 schedule 顺序强校验：跳事件回 409（契约：conflicts with current story state）。
  - 测评埋点与叙事埋点全部落 events 表；只有带 storyId+choiceId 的选择事件触发引擎结算。
  - NPC 记忆四层（fact/relation/state/social）从决策流推导，绝不单独存储（契约红线）。

本机注意：这台机器新文件约 5 分钟后被锁、新进程无法写打开 —— SQLite 库文件重启会变只读。
      用环境变量 WORKPLACE_TOWN_DB_PATH 每次启动指一个新文件即可（同 ARISAI 的 ARISAI_DB_PATH 做法）。

环境变量：
  WORKPLACE_TOWN_DB_PATH   SQLite 路径（默认 backend/api/workplace_town.db）
  WORKPLACE_TOWN_PORT      监听端口（默认 8077）
"""

from __future__ import annotations

import json
import re
import sqlite3
import sys
import threading
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_ENGINE_ROOT = Path(__file__).resolve().parents[1] / "engine_core"
sys.path.insert(0, str(_ENGINE_ROOT))

from app.core.loader import load  # noqa: E402
from app.engine import timeline as tl  # noqa: E402
from app.engine.settlement import normalize_mainline, settle  # noqa: E402
from app.engine.state import DecisionRecord, GameState  # noqa: E402

import id_map  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = Path(sys.argv[sys.argv.index("--db") + 1]) if "--db" in sys.argv \
    else Path(__import__("os").environ.get("WORKPLACE_TOWN_DB_PATH",
                                           Path(__file__).resolve().parent / "workplace_town.db"))
PORT = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv \
    else int(__import__("os").environ.get("WORKPLACE_TOWN_PORT", "8077"))

NPC_IDS = {"wang_ge", "chen_gong", "xiao_lin", "lao_zhou", "xiao_zhao"}
# 契约 eventType 枚举里没有 "main_choice"（fixture 在用），两条口径都收。
CHOICE_TAPS = {"main_choice", "option_click"}
REGION_RE = re.compile(r"^[A-H]$")

_lock = threading.Lock()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Store:
    """SQLite 存取。所有写操作持锁，ThreadingHTTPServer 下安全。"""

    def __init__(self, db_path: Path):
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(db_path), check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript("""
        CREATE TABLE IF NOT EXISTS sessions(
            session_id      TEXT PRIMARY KEY,
            created_at      TEXT NOT NULL,
            content_version TEXT NOT NULL,
            state_json      TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS events(
            session_id    TEXT NOT NULL,
            event_id      TEXT NOT NULL,
            seq           INTEGER,
            event_type    TEXT NOT NULL,
            client_time   TEXT NOT NULL,
            payload_json  TEXT NOT NULL,
            response_json TEXT NOT NULL,
            created_at    TEXT NOT NULL,
            PRIMARY KEY(session_id, event_id)
        );
        """)

    # ---- sessions
    def create_session(self, content_version: str, state_json: str) -> str:
        sid = str(uuid.uuid4())
        with _lock:
            self.conn.execute(
                "INSERT INTO sessions VALUES(?,?,?,?)",
                (sid, now_iso(), content_version, state_json))
            self.conn.commit()
        return sid

    def get_session(self, sid: str):
        with _lock:
            row = self.conn.execute(
                "SELECT * FROM sessions WHERE session_id=?", (sid,)).fetchone()
        return row

    def save_state(self, sid: str, state_json: str) -> None:
        with _lock:
            self.conn.execute(
                "UPDATE sessions SET state_json=? WHERE session_id=?", (state_json, sid))
            self.conn.commit()

    # ---- events
    def get_event(self, sid: str, event_id: str):
        with _lock:
            row = self.conn.execute(
                "SELECT * FROM events WHERE session_id=? AND event_id=?",
                (sid, event_id)).fetchone()
        return row

    def insert_event(self, sid: str, event_id: str, seq, event_type: str,
                     client_time: str, payload_json: str, response_json: str) -> None:
        with _lock:
            self.conn.execute(
                "INSERT INTO events VALUES(?,?,?,?,?,?,?,?)",
                (sid, event_id, seq, event_type, client_time, payload_json,
                 response_json, now_iso()))
            self.conn.commit()

    def update_event_response(self, sid: str, event_id: str, response_json: str) -> None:
        with _lock:
            self.conn.execute(
                "UPDATE events SET response_json=? WHERE session_id=? AND event_id=?",
                (response_json, sid, event_id))
            self.conn.commit()

    def story_ids(self, sid: str) -> list[str]:
        with _lock:
            rows = self.conn.execute(
                "SELECT payload_json FROM events WHERE session_id=? ORDER BY created_at",
                (sid,)).fetchall()
        out = []
        for r in rows:
            p = json.loads(r["payload_json"])
            if p.get("storyId") and p.get("choiceId"):
                out.append(p["storyId"])
        return out

    def region_ids(self, sid: str) -> list[str]:
        with _lock:
            rows = self.conn.execute(
                "SELECT payload_json FROM events WHERE session_id=?", (sid,)).fetchall()
        out = []
        for r in rows:
            p = json.loads(r["payload_json"])
            rid = p.get("regionId")
            if rid and REGION_RE.match(str(rid)) and rid not in out:
                out.append(rid)
        return out


class Engine:
    """engine_core 的进程内单例：配置装一次，schedule 算一次。"""

    def __init__(self):
        # 引擎的 FILES 直接拼 scoring_cards.json，配置在 data/story/ 下
        self.reg = load(REPO_ROOT / "data" / "story")
        schedule = tl.build_schedule(self.reg)
        self.sched_month = {eid: m for m, eid in schedule}
        self.sched_order = [eid for _, eid in schedule]

    def new_state(self) -> GameState:
        return GameState(seed=0)

    # ---- 序列化
    @staticmethod
    def state_to_json(st: GameState) -> str:
        return json.dumps(st.to_dict(), ensure_ascii=False)

    @staticmethod
    def state_from_json(raw: str) -> GameState:
        d = json.loads(raw)
        decisions = [DecisionRecord(**r) for r in d.pop("decisions", [])]
        st = GameState(**d)
        st.decisions = decisions
        return st

    def act_number(self, engine_key: str) -> int:
        act = str(self.reg.events[engine_key].act)
        m = re.search(r"\d+", act)
        return int(m.group()) if m else 1

    # ---- 主线结算
    def settle_mainline(self, st: GameState, engine_key: str, option: str,
                        hesitation_ms, switch_count) -> dict:
        month = self.sched_month[engine_key]
        st.month = max(st.month, month)
        choice = normalize_mainline(self.reg, engine_key, option)
        return settle(st, choice, self.reg, month=month,
                      hesitation_ms=hesitation_ms, switch_count=switch_count)

    def next_undone(self, st: GameState) -> str | None:
        done = set(st.events_done)
        return next((e for e in self.sched_order if e not in done), None)


class Service:
    def __init__(self, store: Store, engine: Engine):
        self.store = store
        self.engine = engine

    # ---- 响应组装
    def _session_state(self, sid: str, st: GameState) -> dict:
        regions = ["A", "H"] + [r for r in self.store.region_ids(sid) if r not in ("A", "H")]
        nxt = self.engine.next_undone(st)
        if nxt:
            current = id_map.engine_to_story(nxt, self.engine.act_number(nxt))
        elif st.events_done:
            last = st.events_done[-1]
            current = id_map.engine_to_story(last, self.engine.act_number(last))
        else:
            current = "M1-E01"
        return {
            "chapterId": f"M{max(1, (st.month - 1) // 12 + 1)}",
            "currentNodeId": current,
            "completedStoryIds": self.store.story_ids(sid),
            "completedActivityIds": [],
            "unlockedRegionIds": sorted(set(regions)),
            "energy": st.life,
            "npcAffinity": dict(st.npc_affinity),
            "flags": {f: True for f in st.flags},
            "scoreSummary": {"decisions": float(st.seq)},
            "scoringVersion": "v2.9",
        }

    def session_response(self, sid: str, content_version: str, st: GameState) -> dict:
        return {"sessionId": sid, "contentVersion": content_version,
                "state": self._session_state(sid, st)}

    # ---- 端点
    def create_session(self, body: dict) -> tuple[int, dict]:
        resume = str(body.get("resumeSessionId") or "")
        if resume:
            row = self.store.get_session(resume)
            if row is None:
                return 404, {"error": "unknown sessionId"}
            return 200, self.session_response(
                resume, row["content_version"], Engine.state_from_json(row["state_json"]))
        content_version = str(body.get("contentVersion") or "v1")
        st = self.engine.new_state()
        sid = self.store.create_session(content_version, Engine.state_to_json(st))
        return 201, self.session_response(sid, content_version, st)

    def get_session(self, sid: str) -> tuple[int, dict]:
        row = self.store.get_session(sid)
        if row is None:
            return 404, {"error": "unknown sessionId"}
        st = Engine.state_from_json(row["state_json"])
        return 200, self.session_response(sid, row["content_version"], st)

    def next_node(self, sid: str) -> tuple[int, dict]:
        row = self.store.get_session(sid)
        if row is None:
            return 404, {"error": "unknown sessionId"}
        st = Engine.state_from_json(row["state_json"])
        nxt = self.engine.next_undone(st)
        if nxt is None:
            return 200, {"nodeId": "END", "nodeType": "finished",
                         "regionId": "A", "title": "48 个月走完了"}
        ev = self.engine.reg.events[nxt]
        choices = [{"choiceId": f"{id_map.engine_to_story(nxt, 1)}-C{i + 1:02d}",
                    "text": opt.get("text", "")}
                   for i, opt in enumerate(ev.options.values())]
        return 200, {
            "nodeId": id_map.engine_to_story(nxt, self.engine.act_number(nxt)),
            "nodeType": "main_story",
            "regionId": "A",
            "title": ev.title,
            "body": "",
            "choices": choices,
        }

    def post_event(self, sid: str, body: dict) -> tuple[int, dict]:
        row = self.store.get_session(sid)
        if row is None:
            return 404, {"error": "unknown sessionId"}

        for field in ("eventId", "eventType", "contentVersion", "clientTime", "payload"):
            if field not in body:
                return 400, {"error": f"missing required field: {field}"}
        event_id = str(body["eventId"])
        event_type = str(body["eventType"])
        payload = body["payload"] if isinstance(body["payload"], dict) else {}
        region = payload.get("regionId")
        if not (isinstance(region, str) and REGION_RE.match(region)):
            return 400, {"error": "payload.regionId must be one of A..H"}

        # 幂等：同一 eventId 直接回当时的响应
        prev = self.store.get_event(sid, event_id)
        if prev is not None:
            resp = json.loads(prev["response_json"])
            resp["duplicate"] = True
            return 200, resp

        st = Engine.state_from_json(row["state_json"])
        seq = None
        if event_type in CHOICE_TAPS and payload.get("storyId") and payload.get("choiceId"):
            engine_key = id_map.story_to_engine(str(payload["storyId"]))
            option = id_map.choice_to_engine(str(payload["choiceId"]))
            if engine_key is None or engine_key not in self.engine.reg.events:
                return 400, {"error": f"unknown storyId: {payload['storyId']}"}
            if option is None or option not in self.engine.reg.events[engine_key].options:
                return 400, {"error": f"unknown choiceId: {payload['choiceId']}"}
            done = set(st.events_done)
            if engine_key in done:
                return 409, {"error": "event already settled"}
            nxt = self.engine.next_undone(st)
            if engine_key != nxt:
                expected = id_map.engine_to_story(nxt, 1) if nxt else None
                return 409, {"error": f"story state conflict, expected {expected}"}
            hes = payload.get("hesitationMs")
            swc = payload.get("switchCount")
            self.engine.settle_mainline(st, engine_key, option,
                                        _as_int(hes), _as_int(swc))
            seq = st.seq

        # 先落事件行（响应占位），再算会话状态 —— 否则 state 里的
        # completedStoryIds / 解锁区域看不到本事件，幂等重放时也对不上。
        self.store.save_state(sid, Engine.state_to_json(st))
        self.store.insert_event(sid, event_id, seq, event_type,
                                str(body["clientTime"]), json.dumps(payload, ensure_ascii=False),
                                "{}")
        state = self._session_state(sid, st)
        nxt2 = self.engine.next_undone(st)
        resp = {
            "eventId": event_id,
            # 走到这里 = 校验全过：选择事件已结算、其余埋点已落日志，都算 accepted
            "accepted": True,
            "state": state,
            "nextNodeId": id_map.engine_to_story(nxt2, self.engine.act_number(nxt2)) if nxt2 else None,
        }
        self.store.update_event_response(sid, event_id, json.dumps(resp, ensure_ascii=False))
        return 200, resp

    def npc_memories(self, sid: str, npc_id: str, layers: list[str] | None,
                     limit: int) -> tuple[int, dict]:
        row = self.store.get_session(sid)
        if row is None:
            return 404, {"error": "unknown sessionId"}
        if npc_id not in NPC_IDS:
            return 404, {"error": f"unknown npcId: {npc_id}"}
        st = Engine.state_from_json(row["state_json"])
        want = set(layers or ["fact", "relation", "state", "social"])

        # seq → 上报时的客户端 eventId（MemoryRef/NpcMemory 的 eventRef 都要指回它）
        seq_to_client: dict[int, str] = {}
        with _lock:
            rows = self.store.conn.execute(
                "SELECT seq, event_id, payload_json FROM events WHERE session_id=?",
                (sid,)).fetchall()
        for r in rows:
            if r["seq"] is not None:
                seq_to_client[int(r["seq"])] = r["event_id"]

        items: list[dict] = []

        # fact 层：决策记忆标签（决策流推导，不落库）
        if "fact" in want:
            for d in st.decisions:
                tags = list(d.memory_tags or [])
                if not tags:
                    continue
                ev_ref = seq_to_client.get(d.seq, str(uuid.uuid4()))
                for t in tags:
                    items.append({
                        "npcId": npc_id, "layer": "fact", "kind": "memory_tag",
                        "month": d.month, "seq": d.seq,
                        "fact": f"第 {d.seq} 个决策点（{d.node_id}）你选择了「{d.option_text}」——{t}",
                        "eventRef": ev_ref,
                    })

        # relation 层：该 NPC 的好感变动（按决策重放 affinity，确定性与引擎一致）
        if "relation" in want:
            for d in st.decisions:
                ev = self.engine.reg.events.get(d.node_id)
                if ev is None:
                    continue
                opt = (ev.options.get(d.option_id) or {})
                aff = opt.get("affinity")
                if isinstance(aff, dict) and aff.get("npc") == npc_id:
                    ev_ref = seq_to_client.get(d.seq, str(uuid.uuid4()))
                    delta = int(aff.get("delta", 0))
                    items.append({
                        "npcId": npc_id, "layer": "relation", "kind": "affinity",
                        "month": d.month, "seq": d.seq,
                        "fact": f"好感度 {'+' if delta >= 0 else ''}{delta}（{d.node_id}.{d.option_id}）",
                        "eventRef": ev_ref,
                    })

        # state 层：处境事实（事故/倦怠，行为语言）
        if "state" in want:
            for inc in st.incidents:
                items.append({
                    "npcId": npc_id, "layer": "state", "kind": "incident",
                    "month": inc.get("month", 0), "seq": 0,
                    "fact": str(inc.get("reason", "处境变化")),
                    "eventRef": str(uuid.uuid4()),
                })

        # social 层：闲聊进游戏记忆流（/chat 未实现前恒为空）
        # 只保留能指回客户端 eventId 的条目（seq 作键查，不是查 eventId 集合）
        items = [i for i in items if i["seq"] == 0 or i["seq"] in seq_to_client]
        items.sort(key=lambda x: (-x["seq"], x["month"]))
        stage = f"Lv{st.npc_level.get(npc_id, 1)}"
        return 200, {"npcId": npc_id, "relationStage": stage, "items": items[:limit]}


def _as_int(v) -> int | None:
    if v is None or isinstance(v, bool):
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


class Handler(BaseHTTPRequestHandler):
    service: Service = None  # type: ignore[assignment]
    routes = [
        re.compile(r"^/api/v1/health$"),
        re.compile(r"^/api/v1/sessions$"),
        re.compile(r"^/api/v1/sessions/([\w-]+)$"),
        re.compile(r"^/api/v1/sessions/([\w-]+)/next$"),
        re.compile(r"^/api/v1/sessions/([\w-]+)/events$"),
        re.compile(r"^/api/v1/sessions/([\w-]+)/npcs/([\w-]+)/memories$"),
    ]

    def log_message(self, fmt, *args):  # 安静模式由 -v 控制，默认打印一行
        sys.stdout.write("[api] %s\n" % (fmt % args))

    # ---- helpers
    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    def _reply(self, code: int, obj: dict) -> None:
        raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _dispatch(self, method: str) -> None:
        svc = self.service
        path = self.path.split("?")[0]
        query = self.path.split("?")[1] if "?" in self.path else ""
        m0, m1, m2, m3, m4, m5 = self.routes

        if method == "GET" and m0.match(path):
            return self._reply(200, {"status": "ok", "time": now_iso()})
        if method == "POST" and m1.match(path):
            body = self._body()
            if body is None:
                return self._reply(400, {"error": "invalid JSON"})
            code, resp = svc.create_session(body or {})
            return self._reply(code, resp)
        m = m2.match(path)
        if method == "GET" and m:
            return self._reply(*svc.get_session(m.group(1)))
        m = m3.match(path)
        if method == "GET" and m:
            return self._reply(*svc.next_node(m.group(1)))
        m = m4.match(path)
        if method == "POST" and m:
            body = self._body()
            if body is None:
                return self._reply(400, {"error": "invalid JSON"})
            return self._reply(*svc.post_event(m.group(1), body or {}))
        m = m5.match(path)
        if method == "GET" and m:
            layers = None
            if "layers=" in query:
                layers = [x for x in query.split("layers=")[1].split("&")[0].split(",") if x]
            limit = 20
            if "limit=" in query:
                try:
                    limit = max(1, min(100, int(query.split("limit=")[1].split("&")[0])))
                except ValueError:
                    pass
            return self._reply(*svc.npc_memories(m.group(1), m.group(2), layers, limit))
        return self._reply(404, {"error": "no route"})

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")


def build_service(db_path: Path | None = None) -> Service:
    return Service(Store(db_path or DB_PATH), Engine())


def main() -> None:
    svc = build_service()
    Handler.service = svc
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[api] workplace-town M4 minimal server on http://127.0.0.1:{PORT}/api/v1 "
          f"(db={DB_PATH})")
    server.serve_forever()


if __name__ == "__main__":
    main()
