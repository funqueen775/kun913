# -*- coding: utf-8 -*-
"""ID 口径映射：契约 storyId/choiceId ↔ 引擎 event key/option key。

仓库里现存三套 ID（见 workspace 备忘「未决口径」）：
  契约 fixtures:  storyId="M1-E01"  choiceId="M1-E01-C02"（或 "E27-A"）
  前端 Godot:     eventId="M1-E01"  choiceId="option_b"
  引擎 scoring:   "E01"             选项键 "A"/"B"/"C"

统一策略：对外兼容三套写法，对内一律转成引擎口径再进 settle()。
映射是纯函数、无状态、可单测。
"""

from __future__ import annotations

import re

# "M1-E01" / "E01" → 引擎 key "E01"
_STORY_RE = re.compile(r"^(?:M\d+-)?([A-Z]\d+)$")

# 前端风格："option_a" / "optionA" → A
_FRONT_OPTION_RE = re.compile(r"^option[_-]?([abc])$", re.IGNORECASE)

# 契约序号风格："M1-E01-C02" → 2 → B（C01→A, C02→B, C03→C）。前缀允许连字符。
_SEQ_OPTION_RE = re.compile(r"^[\w]+(?:-[\w]+)*[-_.][Cc]0?([1-9])$")

# 契约字母风格："E27-A" / "M1-E01-A" → A
_LETTER_OPTION_RE = re.compile(r"^(?:[\w]+(?:-[\w]+)*[-_.])?([ABC])$")


def story_to_engine(story_id: str) -> str | None:
    """契约/前端 storyId → 引擎事件 key。'M1-E01'→'E01'，'E01'→'E01'。"""
    if not story_id:
        return None
    m = _STORY_RE.match(story_id.strip())
    return m.group(1) if m else None


def engine_to_story(engine_key: str, act_number: int = 1) -> str:
    """引擎 key → 契约 storyId。'E01' + act1 → 'M1-E01'。"""
    return f"M{act_number}-{engine_key}"


def choice_to_engine(choice_id: str) -> str | None:
    """三种 choiceId 写法 → 引擎选项键 A/B/C。认不出返回 None（调用方回 400）。"""
    if not choice_id:
        return None
    cid = choice_id.strip()
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
