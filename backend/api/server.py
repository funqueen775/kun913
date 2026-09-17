# -*- coding: utf-8 -*-
"""M4 最小服务层：把 contracts/openapi.yaml 的核心端点变成可执行体。

范围（其余端点后续补）：
  GET  /api/v1/health                                    存活检查
  POST /api/v1/sessions                                  建会话（支持 resumeSessionId 续接）
  GET  /api/v1/sessions/{sid}                            读权威会话状态
  GET  /api/v1/sessions/{sid}/next                       下一个可玩节点
  POST /api/v1/sessions/{sid}/events                     幂等上报（主线选择真正进引擎结算）
  GET  /api/v1/sessions/{sid}/npcs/{npcId}/memories      NPC 记忆（事件流推导，只读）
  POST /api/v1/sessions/{sid}/report                     生成终局报告（202 + 状态）
  GET  /api/v1/sessions/{sid}/report                     读已成片的报告（未成片 404）
  GET  /api/v1/sessions/{sid}/report/status              轮询生成状态

设计要点：
  - 只用标准库（http.server + sqlite3），与 engine_core 的零依赖口径一致；FastAPI 是后续升级项。
  - 引擎状态以 JSON 快照存在 sessions.state_json，每结算一条主线事件推进一次；
    重启不丢，且与「跑批可复算」精神一致（事件流重放可还原同一状态）。
  - **叙事编号 ↔ 引擎键走 data/story/story_key_map.json**（2026-09-16 起）。
    旧做法「storyId 去掉 M 前缀」只对第 1 件成立：Godot 的 M1-E02 是「技术选型」，
    而打分卡 E02 是「第一次被轻视」。靠前缀裁剪的后果是前 8 件静默记错账、第 9 件起 409。
    映射表里不含任何打分载荷，所以不违反「scoring_cards 不下发前端」的红线。
  - **会话推进用映射表的 playableOrder，不是引擎的全量 44 节点 schedule**：
    Godot 目前只提供 19 个测评节点，按全量 schedule 校验会卡在缺失节点上（实测第 9 件
    就撞上成就节点 C1）。缺失节点在报告层表现为「证据不足」，算法册 §6 本来就允许。
    playableOrder 随剧情补齐逐件变长，全部补齐即等价于全量 schedule。
  - 跳事件仍回 409（契约：conflicts with current story state）—— 这条守住，
    它是唯二能发现编号错位的机制（另一个是 completedStoryIds 对账）。
  - **纯叙事成就节点 C1/C2/C3 靠 achievement_view 推进**：它们 no_decision、无选项，
    走不进选择通道；没有这条分支，会话会永远停在这三件上。
  - 测评埋点与叙事埋点全部落 events 表；只有带 storyId+choiceId 的选择事件触发引擎结算。
  - 选项没对齐的事件（align=pending_rewrite）一律 409 并说明原因，
    **绝不退回正则按同名选项记分** —— 那正是「善意选项被记成越界选项」的来源。
  - NPC 记忆四层（fact/relation/state/social）从决策流推导，绝不单独存储（契约红线）。
  - **报告走 app.report.build()，服务层只喂料不重算**（2026-09-16 起）：
    报告算法本身完整且是纯函数，服务层零算法；阈值与打分卡永不下发（契约 anti-leak 红线）。
    契约把生成写成异步（202 → 轮询），但生成是纯模板毫秒级、无大模型 → **同步生成后如实回 ready**，
    不伪造 pending/generating 中间态。POST 幂等：已成片则不重算（契约「请求两次返回同一个 handle」）。
    转成异步只需把 generate_report 换成丢线程池 + 状态位，接口形状不用动。
  - 报告缺料的地方**留空不估算**：服务层没有跑批的逐月日志 → situationTrack.states 为空；
    档案自评（profile_answer 埋点）尚未采集 → 无后验与矛盾度。报告层自己按「证据不足」处理，
    这是算法册 §6 允许的表现，不用假数据顶替。

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
from app.core import constants as C  # noqa: E402
from app.engine import timeline as tl  # noqa: E402
from app.engine.settlement import normalize_mainline, settle  # noqa: E402
from app.engine.state import DecisionRecord, GameState  # noqa: E402
from app.report import build as build_report  # noqa: E402

import id_map  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = Path(sys.argv[sys.argv.index("--db") + 1]) if "--db" in sys.argv \
    else Path(__import__("os").environ.get("WORKPLACE_TOWN_DB_PATH",
                                           Path(__file__).resolve().parent / "workplace_town.db"))
PORT = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv \
    else int(__import__("os").environ.get("WORKPLACE_TOWN_PORT", "8077"))

# 叙事编号 ↔ 引擎测评节点键的唯一映射（人工逐条确认，data/story 下）。
STORY_KEY_MAP_PATH = REPO_ROOT / "data" / "story" / "story_key_map.json"

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
        CREATE TABLE IF NOT EXISTS reports(
            session_id   TEXT PRIMARY KEY,
            status       TEXT NOT NULL,
            reason       TEXT NOT NULL DEFAULT '',
            payload_json TEXT NOT NULL DEFAULT '',
            requested_at TEXT NOT NULL,
            generated_at TEXT
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

    def event_stream(self, sid: str) -> list:
        """本会话的原始事件流（按落库顺序）。报告层要用它还原埋点轨迹。"""
        with _lock:
            return self.conn.execute(
                "SELECT event_type, payload_json FROM events WHERE session_id=?"
                " ORDER BY created_at", (sid,)).fetchall()

    # ---- reports（一个会话一份；契约要求幂等，所以按 session_id 主键 upsert）
    def get_report(self, sid: str):
        with _lock:
            return self.conn.execute(
                "SELECT * FROM reports WHERE session_id=?", (sid,)).fetchone()

    def save_report(self, sid: str, status: str, reason: str,
                    payload_json: str, generated_at: str | None) -> None:
        with _lock:
            self.conn.execute(
                "INSERT INTO reports(session_id, status, reason, payload_json,"
                " requested_at, generated_at) VALUES(?,?,?,?,?,?)"
                " ON CONFLICT(session_id) DO UPDATE SET"
                " status=excluded.status, reason=excluded.reason,"
                " payload_json=excluded.payload_json, generated_at=excluded.generated_at",
                (sid, status, reason, payload_json, now_iso(), generated_at))
            self.conn.commit()


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
        result = settle(st, choice, self.reg, month=month,
                        hesitation_ms=hesitation_ms, switch_count=switch_count)
        return result


    def next_undone(self, st: GameState) -> str | None:
        done = set(st.events_done)
        return next((e for e in self.sched_order if e not in done), None)


class ReportInput:
    """喂给 report.build() 的输入壳。

    报告层的签名收 `simulation.RunResult`（要 `result.state` 与
    `result.log.months` / `result.log.tracking`），但服务层是逐事件推进的，
    没有跑批那份逐月日志。这里只把**真实可得**的部分装进去，缺的留空 ——
    绝不用估算值顶替：报告层对空输入本来就按「证据不足」处理（算法册 §6 允许）。
    """

    class _Log:
        def __init__(self, months: list, tracking: list):
            self.months = months
            self.tracking = tracking

    def __init__(self, state: GameState, months: list, tracking: list):
        self.state = state
        self.log = ReportInput._Log(months, tracking)


class Service:
    def __init__(self, store: Store, engine: Engine, mapping: id_map.StoryKeyMap):
        self.store = store
        self.engine = engine
        self.mapping = mapping

    # ---- 推进口径
    def _next_step(self, st: GameState) -> str | None:
        """客户端当前该走的下一步（引擎键）。

        用映射表的 playableOrder，**不是**引擎的全量 schedule：
        Godot 侧目前只提供 44 个测评节点里的 19 个，按全量 schedule 校验会在
        缺失节点上永久卡死（实测第 9 件起全部 409，因为第 9 位是成就节点 C1）。
        缺失节点在报告层自然表现为「证据不足」——算法册 §6 本来就允许「没说」。
        playableOrder 随剧情补齐逐件变长，全部补齐就等价于全量 schedule。
        """
        return self.mapping.next_playable(set(st.events_done))

    def _client_label(self, engine_key: str | None) -> str | None:
        """引擎键 → 回给客户端的叙事 id。映射表查不到才退回契约口径拼装。"""
        if not engine_key:
            return None
        return self.mapping.client_id(engine_key) or \
            id_map.engine_to_story(engine_key, self.engine.act_number(engine_key))

    # ---- 响应组装
    def _session_state(self, sid: str, st: GameState) -> dict:
        regions = ["A", "H"] + [r for r in self.store.region_ids(sid) if r not in ("A", "H")]
        nxt = self._next_step(st)
        if nxt:
            current = self._client_label(nxt)
        elif st.events_done:
            current = self._client_label(st.events_done[-1])
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
            # 版本号跟打分卡走，别写死 —— 硬编码会在换版后骗人
            "scoringVersion": "v" + str(self.engine.reg.version.get("scoring_cards", "?")),
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
        nxt = self._next_step(st)
        if nxt is None:
            return 200, {"nodeId": "END", "nodeType": "finished",
                         "regionId": "A", "title": "48 个月走完了"}
        ev = self.engine.reg.events[nxt]
        client_id = self._client_label(nxt)
        # choiceId 用客户端的叙事 id 拼（Godot 的 _contract_choice_id 同形），
        # 后端收到后会先经映射表归一再进引擎。
        #
        # ⚠ 这里的 title / choices[].text 直接来自打分卡，是契约既有设计
        #   （§「证据不足就静默」那条不覆盖本端点）。但算法册 §1 的红线是
        #   「scoring_cards 不得下发前端」—— Godot 自带 MAIN_EVENTS 文案，
        #   并不调本端点，所以目前不冲突。若将来有瘦客户端要用它，
        #   应该改成只回结构（id + 选项数），文案由客户端自己出。
        choices = [{"choiceId": f"{client_id}-C{i + 1:02d}",
                    "text": opt.get("text", "")}
                   for i, opt in enumerate(ev.options.values())]
        return 200, {
            "nodeId": client_id,
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
        story_id = str(payload.get("storyId") or "")
        choice_id = str(payload.get("choiceId") or "")

        # ---- ① 纯叙事成就节点（C1/C2/C3）的推进通道
        # 这三个节点 no_decision=True、options 为空，永远走不进 CHOICE_TAPS。
        # 没有这条分支，_next_step 会一直停在 C1，它后面的节点全部 409 ——
        # 实测「Godot 走完第 8 件就再也过不去」就是这个原因。
        # 这一档只把节点记进 events_done：不调 settle、不加 seq、不进 decisions，
        # 因为成就演出本来就不测评（算法册：纯演出无 marker）。
        if event_type == "achievement_view" and story_id:
            a_key = self.mapping.scoring_key(story_id)
            a_ev = self.engine.reg.events.get(a_key or "")
            if a_ev is not None and a_ev.is_achievement and not a_ev.has_decision:
                if a_key not in st.events_done:
                    nxt = self._next_step(st)
                    if a_key != nxt:
                        return 409, {"error": "story state conflict",
                                     "expected": self._client_label(nxt),
                                     "got": story_id}
                    st.events_done.append(a_key)

        # ---- ② 选择事件
        elif event_type in CHOICE_TAPS and story_id and choice_id:
            align = self.mapping.align(story_id)
            if align == id_map.ALIGN_PENDING:
                # 编号对上了、选项还没对上。宁可 409 也说清楚，绝不退回正则瞎猜 ——
                # 「按同名选项记分」正是把善意选项记成越界选项的原因。
                return 409, {
                    "error": f"{story_id} 的选项尚未对齐，不能进测评",
                    "align": align,
                    "storyId": story_id,
                    "scoringKey": self.mapping.scoring_key(story_id),
                    "todo": self.mapping.todo(story_id),
                }
            if align != id_map.ALIGN_NON_SCORING:
                engine_key = self.mapping.scoring_key(story_id)
                if engine_key is None or engine_key not in self.engine.reg.events:
                    return 400, {"error": f"unknown storyId: {story_id}"}
                option = self.mapping.option_key(story_id, choice_id)
                if option is None or option not in self.engine.reg.events[engine_key].options:
                    return 400, {"error": f"unknown choiceId: {choice_id}"}
                done = set(st.events_done)
                if engine_key in done:
                    return 409, {"error": "event already settled"}
                nxt = self._next_step(st)
                if engine_key != nxt:
                    return 409, {"error": "story state conflict",
                                 "expected": self._client_label(nxt)}
                self.engine.settle_mainline(st, engine_key, option,
                                            _as_int(payload.get("hesitationMs")),
                                            _as_int(payload.get("switchCount")))
                seq = st.seq
            # ALIGN_NON_SCORING（熊熊有招训练对局这类 Godot 自创事件）：
            # 玩家确实做完了剧情，所以照常落库、进 completedStoryIds，
            # 但不进引擎结算 —— 只落日志不算账。

        # 先落事件行（响应占位），再算会话状态 —— 否则 state 里的
        # completedStoryIds / 解锁区域看不到本事件，幂等重放时也对不上。
        self.store.save_state(sid, Engine.state_to_json(st))
        self.store.insert_event(sid, event_id, seq, event_type,
                                str(body["clientTime"]), json.dumps(payload, ensure_ascii=False),
                                "{}")
        state = self._session_state(sid, st)
        nxt2 = self._next_step(st)
        resp = {
            "eventId": event_id,
            # 走到这里 = 校验全过：选择事件已结算、其余埋点已落日志，都算 accepted
            "accepted": True,
            "state": state,
            "nextNodeId": self._client_label(nxt2),
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

    # ---- 报告层（算法在 app.report，这里只喂料）
    def _report_tracking(self, sid: str, st: GameState) -> list[dict]:
        """把落库事件流还原成报告层要的 tracking。

        报告层的「冲刺与伪装」模块吃两类轨迹：
          - explore_click：自由周末的组团与同伴（真实埋点，从 events 表还原）
        另还原 encounter_choice（在场一幕应答）→ 报告层的性格回声（encounterEchoes）。
        服务层收不到的（比如还没实现的埋点）就不出现 —— 对应的分析自然为空。
        """
        tracking: list[dict] = []
        for row in self.store.event_stream(sid):
            if row["event_type"] == "encounter_choice":
                payload = json.loads(row["payload_json"] or "{}")
                tags = payload.get("memoryTags")
                tracking.append({
                    "tap": "encounter_choice",
                    "month": payload.get("month"),
                    "activityId": payload.get("activityId"),
                    "npcId": payload.get("npcId"),
                    "optionId": payload.get("optionId"),
                    "memoryTags": tags if isinstance(tags, list) else [],
                })
                continue
            if row["event_type"] != "explore_click":
                continue
            payload = json.loads(row["payload_json"] or "{}")
            month = _as_int(payload.get("slotIndex"))
            if month:
                targets = payload.get("targets")
                tracking.append({
                    "tap": "explore_click", "month": month,
                    "targets": targets if isinstance(targets, list) else [],
                    "activityId": payload.get("activityId"),
                })
        return tracking

    def _self_ratings(self, sid: str) -> dict[str, float] | None:
        """建档自评（0-10）。profile_answer 埋点尚未采集 → 现在恒为 None，
        大五只有行为一列、不出后验与矛盾度。埋点一落地这里自动生效。"""
        for row in self.store.event_stream(sid):
            if row["event_type"] != "profile_answer":
                continue
            payload = json.loads(row["payload_json"] or "{}")
            ratings = payload.get("ratings") or payload.get("selfRatings")
            if isinstance(ratings, dict) and ratings:
                out: dict[str, float] = {}
                for k, v in ratings.items():
                    try:
                        out[str(k).upper()] = float(v)
                    except (TypeError, ValueError):
                        continue
                return out or None
        return None

    def generate_report(self, sid: str) -> tuple[int, dict]:
        """POST /report。契约写的是异步（202 + 状态），但生成是纯模板、毫秒级、无大模型
        → 同步算完如实回 ready，不伪造 pending/generating 中间态。
        幂等：已成片就返回同一 handle，不重算（契约「请求两次返回同一个 handle」）。"""
        row = self.store.get_session(sid)
        if row is None:
            return 404, {"error": "unknown sessionId"}
        prev = self.store.get_report(sid)
        if prev is not None and prev["status"] == "ready":
            return 202, {"sessionId": sid, "status": "ready"}

        st = Engine.state_from_json(row["state_json"])
        try:
            report = build_report(
                ReportInput(st, [], self._report_tracking(sid, st)),
                self.engine.reg,
                self_ratings=self._self_ratings(sid),
                session_id=sid,
            )
        except Exception as exc:  # 生成失败要留痕，但不把内部堆栈泄漏给客户端
            self.store.save_report(sid, "failed", type(exc).__name__, "", None)
            sys.stdout.write("[api] report build failed: %r\n" % (exc,))
            return 202, {"sessionId": sid, "status": "failed",
                         "reason": "报告生成失败，详见服务端日志"}
        self.store.save_report(sid, "ready", "",
                               json.dumps(report, ensure_ascii=False),
                               report["generatedAt"])
        return 202, {"sessionId": sid, "status": "ready"}

    def report_status(self, sid: str) -> tuple[int, dict]:
        if self.store.get_session(sid) is None:
            return 404, {"error": "unknown sessionId"}
        row = self.store.get_report(sid)
        if row is None:
            return 200, {"sessionId": sid, "status": "pending"}
        out = {"sessionId": sid, "status": row["status"]}
        if row["status"] == "failed" and row["reason"]:
            out["reason"] = row["reason"]
        return 200, out

    def get_report(self, sid: str) -> tuple[int, dict]:
        """GET /report。契约：只有 ready 才 200，其余 404（客户端去轮询 status）。"""
        if self.store.get_session(sid) is None:
            return 404, {"error": "unknown sessionId"}
        row = self.store.get_report(sid)
        if row is None or row["status"] != "ready" or not row["payload_json"]:
            return 404, {"error": "report not generated yet"}
        return 200, json.loads(row["payload_json"])


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
        re.compile(r"^/api/v1/sessions/([\w-]+)/report$"),
        re.compile(r"^/api/v1/sessions/([\w-]+)/report/status$"),
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
        m0, m1, m2, m3, m4, m5, m6, m7 = self.routes

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
        m = m6.match(path)
        if method == "POST" and m:
            return self._reply(*svc.generate_report(m.group(1)))
        if method == "GET" and m:
            return self._reply(*svc.get_report(m.group(1)))
        m = m7.match(path)
        if method == "GET" and m:
            return self._reply(*svc.report_status(m.group(1)))
        return self._reply(404, {"error": "no route"})

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")


def build_service(db_path: Path | None = None,
                  mapping_path: Path | None = None) -> Service:
    return Service(
        Store(db_path or DB_PATH),
        Engine(),
        id_map.StoryKeyMap.load_or_empty(mapping_path or STORY_KEY_MAP_PATH),
    )


def main() -> None:
    svc = build_service()
    Handler.service = svc
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    cov = svc.mapping.coverage()
    print(f"[api] workplace-town M4 minimal server on http://127.0.0.1:{PORT}/api/v1 "
          f"(db={DB_PATH})")
    print(f"[api] 映射表 v{svc.mapping.version}：可连续承接 {len(svc.mapping.playable_engine_order())} 个节点"
          + (f"，Godot 已对齐 {cov.get('aligned')}/{cov.get('godotEvents')} 件、"
             f"覆盖打分卡 {cov.get('scoringNodes')}/{cov.get('scoringNodesTotal')} 个节点"
             if cov else ""))
    server.serve_forever()


if __name__ == "__main__":
    main()
