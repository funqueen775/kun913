# -*- coding: utf-8 -*-
"""ID 口径映射：契约 storyId/choiceId ↔ 引擎 event key/option key。

仓库里现存三套 ID：
  契约 fixtures:  storyId="M1-E01"  choiceId="M1-E01-C02"（或 "E27-A"）
  前端 Godot:     storyId="M1-E01"  choiceId="option_b"
  引擎 scoring:   "E01"             选项键 "A"/"B"/"C"

## 2026-09-16 起：以映射表为准，正则只做兜底

原来的做法是「storyId 去掉 M 前缀」→ `M1-E02 → E02`。这条规则**只对第 1 件成立**：
Godot 的叙事编号是「幕-序号」连续 1..24，引擎是「排期表序号」共 44 个节点，
`M1-E02`（技术选型）在打分卡里其实是 E04，`M5-E17`（副业边界）是 E39。
靠前缀裁剪等于赌两套编号恰好相同 —— 前 8 件校验全过、静默记错账，第 9 件起 409 卡死。

现在改为查 `data/story/story_key_map.json`（人工逐条确认过的映射）。
纯正则那三个函数保留，只作为「映射表里查不到」时的兜底，方便老工具继续跑。
"""

from __future__ import annotations

import json
import re
from pathlib import Path

# "M1-E01" / "E01" → 引擎 key "E01"（兜底用）
_STORY_RE = re.compile(r"^(?:M\d+-)?([A-Z]\d+)$")

# 前端风格："option_a" / "optionA" → 槽位 option_a
_FRONT_SLOT_RE = re.compile(r"^option[_-]?([abc])$", re.IGNORECASE)

# 契约序号风格："M1-E01-C02" → 槽位 option_b（C01→a, C02→b, C03→c）
_SEQ_SLOT_RE = re.compile(r"[-_.][Cc]0?([1-9])$")

# 契约字母风格："E27-A" / "M1-E01-A" → 槽位 option_a
_LETTER_SLOT_RE = re.compile(r"[-_.]([ABC])$")

# 兜底：前端风格 → A
_FRONT_OPTION_RE = re.compile(r"^option[_-]?([abc])$", re.IGNORECASE)

# 兜底：契约序号风格 "M1-E01-C02" → B
_SEQ_OPTION_RE = re.compile(r"^[\w]+(?:-[\w]+)*[-_.][Cc]0?([1-9])$")

# 兜底：契约字母风格 "E27-A" → A
_LETTER_OPTION_RE = re.compile(r"^(?:[\w]+(?:-[\w]+)*[-_.])?([ABC])$")

ALIGN_OK = "ok"
ALIGN_PENDING = "pending_rewrite"
ALIGN_NON_SCORING = "non_scoring"
ALIGN_UNKNOWN = "unknown"


# ------------------------------------------------------------------ 兜底原语
def story_to_engine(story_id: str) -> str | None:
    """契约/前端 storyId → 引擎事件 key。'M1-E01'→'E01'，'E01'→'E01'。

    ⚠ 兜底路径：它对第 2 件之后就不再可信（见模块头）。正式链路走 StoryKeyMap。
    """
    if not story_id:
        return None
    m = _STORY_RE.match(str(story_id).strip())
    return m.group(1) if m else None


def engine_to_story(engine_key: str, act_number: int = 1) -> str:
    """引擎 key → 契约 storyId。'E01' + act1 → 'M1-E01'。"""
    return f"M{act_number}-{engine_key}"


def choice_to_engine(choice_id: str) -> str | None:
    """三种 choiceId 写法 → 引擎选项键 A/B/C。认不出返回 None。"""
    if not choice_id:
        return None
    cid = str(choice_id).strip()
    m = _FRONT_OPTION_RE.match(cid)
    if m:
        return m.group(1).upper()
    m = _SEQ_OPTION_RE.match(cid)
    if m:
        return chr(ord("A") + int(m.group(1)) - 1)
    m = _LETTER_OPTION_RE.match(cid)
    if m:
        return m.group(1).upper()
    return None


def choice_to_slot(choice_id: str) -> str | None:
    """任意 choiceId 写法 → Godot 槽位名 option_a/option_b/option_c。

    'option_b' / 'M1-E01-C02' / 'E27-A' 都能归一成槽位，这样才拿得去映射表查表。
    """
    if not choice_id:
        return None
    cid = str(choice_id).strip()
    m = _FRONT_SLOT_RE.match(cid)
    if m:
        return f"option_{m.group(1).lower()}"
    m = _SEQ_SLOT_RE.search(cid)
    if m:
        n = int(m.group(1))
        return f"option_{'abc'[n - 1]}" if 1 <= n <= 3 else None
    m = _LETTER_SLOT_RE.search(cid)
    if m:
        return f"option_{m.group(1).lower()}"
    return None


# ------------------------------------------------------------------ 映射表
class StoryKeyMap:
    """`data/story/story_key_map.json` 的只读视图。

    刻意做成数据驱动：策划改映射只动 JSON，不动 Python；
    映射表里只有 id 对应关系、不含任何打分载荷，
    所以不违反「scoring_cards 不下发前端、不进客户端」的红线。
    """

    def __init__(self, raw: dict):
        self.raw = raw
        self.version = str(raw.get("version", "?"))
        events = raw.get("events") or {}
        self._events: dict[str, dict] = {
            k: dict(v) for k, v in events.items() if not str(k).startswith("_")
        }
        po = raw.get("playableOrder") or {}
        self._playable: list[str] = [str(x) for x in (po.get("list") or [])]

        self._engine_to_client: dict[str, str] = {}
        for client_id, entry in self._events.items():
            key = entry.get("scoringKey")
            if key and key not in self._engine_to_client:
                self._engine_to_client[str(key)] = client_id

        self._playable_engine: list[str] = []
        for client_id in self._playable:
            key = (self._events.get(client_id) or {}).get("scoringKey")
            if key:
                self._playable_engine.append(str(key))

    # ---- 加载
    @classmethod
    def load(cls, path: str | Path) -> "StoryKeyMap":
        with Path(path).open("r", encoding="utf-8") as fh:
            return cls(json.load(fh))

    @classmethod
    def load_or_empty(cls, path: str | Path) -> "StoryKeyMap":
        """文件不存在时给空表：不依赖映射的老探针仍能跑起来。"""
        p = Path(path)
        if not p.exists():
            return cls({"version": "missing", "events": {}, "playableOrder": {"list": []}})
        return cls.load(p)

    # ---- 查询
    def entry(self, story_id: str | None) -> dict:
        if not story_id:
            return {}
        return self._events.get(str(story_id).strip()) or {}

    def known(self, story_id: str | None) -> bool:
        return bool(self.entry(story_id))

    def align(self, story_id: str | None) -> str:
        """'ok' / 'pending_rewrite' / 'non_scoring'；表里没有则 'unknown'。"""
        e = self.entry(story_id)
        if not e:
            return ALIGN_UNKNOWN
        return str(e.get("align") or ALIGN_UNKNOWN)

    def todo(self, story_id: str | None) -> str:
        return str(self.entry(story_id).get("_todo") or "")

    def scoring_key(self, story_id: str | None) -> str | None:
        """storyId → 引擎键。表里没有则退回旧的去前缀规则（兜底）。"""
        e = self.entry(story_id)
        if e:
            return e.get("scoringKey")          # 可能是 None（non_scoring）
        return story_to_engine(str(story_id or ""))

    def option_key(self, story_id: str | None, choice_id: str | None) -> str | None:
        """(storyId, choiceId) → 引擎选项键 A/B/C。

        查表命中但值为 None，说明该选项还没对齐（pending_rewrite），
        故意返回 None 让调用方报错 —— **绝不退回正则瞎猜**，那正是错位的来源。
        """
        e = self.entry(story_id)
        if e:
            slot = choice_to_slot(str(choice_id or ""))
            opts = e.get("options") or {}
            if slot and slot in opts:
                val = opts[slot]
                return str(val) if val else None
            if e.get("align") == ALIGN_NON_SCORING:
                return None
        return choice_to_engine(str(choice_id or ""))

    def client_id(self, engine_key: str | None) -> str | None:
        """引擎键 → Godot 叙事 id（回包给客户端用）。"""
        if not engine_key:
            return None
        return self._engine_to_client.get(str(engine_key))

    # ---- 顺序
    def playable_engine_order(self) -> list[str]:
        return list(self._playable_engine)

    def is_playable(self, engine_key: str | None) -> bool:
        return bool(engine_key) and str(engine_key) in self._playable_engine

    def next_playable(self, done: set[str]) -> str | None:
        return next((k for k in self._playable_engine if k not in done), None)

    # ---- 对账
    def coverage(self) -> dict:
        return dict(self.raw.get("coverage") or {})
