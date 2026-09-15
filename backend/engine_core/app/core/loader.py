# -*- coding: utf-8 -*-
"""配置层：把 5 份 JSON 加载成唯一的 ConfigRegistry。

设计红线（算法册 §1）：
  - 数据文件是唯一口径，后端不得内置任何标定数值副本；
  - 前端只上报原始行为，所有计算在服务端；
  - scoring_cards 任何内容不得下发前端、不得进大模型 prompt。
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

def _default_data_dir() -> Path:
    """定位唯一口径的数据目录（不复制副本）。

    优先级：
      1. 环境变量 XZZ_DATA_DIR（任何部署形态都可显式指定）；
      2. <kun913>/data/story/   —— 2026-09 迁入 kun913 后的位置；
      3. <xiongxinzhuangzhi>/events/ —— 旧工程位置，保留兜底。
    """
    import os

    env = os.environ.get("XZZ_DATA_DIR")
    if env:
        return Path(env).resolve()

    parts = Path(__file__).resolve().parents
    candidates: list[Path] = []
    if len(parts) > 4:
        candidates.append(parts[4] / "data" / "story")
    if len(parts) > 3:
        candidates.append(parts[3] / "events")
    for p in candidates:
        if p.exists():
            return p
    return candidates[0] if candidates else Path(__file__).resolve().parent


DEFAULT_DATA_DIR = _default_data_dir()

FILES = {
    "cards": "scoring_cards.json",
    "free_time": "free_time_system.json",
    "monthly": "monthly_action_nodes.json",
    "crisis": "crisis_dialogue.json",
    "template": "task_001_tech_stack.json",
}


def _read(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"配置缺失：{path}")
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def iter_event_ids(cards: dict) -> list[str]:
    """打分卡里的 44 个节点，按 _index 官方顺序返回（E01..E35, C1..C5, E36..E39）。"""
    idx = cards.get("_index", {})
    if idx:
        return [k for k, _ in sorted(idx.items(), key=lambda kv: kv[1])]
    return [k for k in cards if k and k[0] in "EC" and k[1:].isdigit()]


@dataclass
class EventDef:
    """主线/成就节点（打分卡的封装视图）。"""

    event_id: str
    raw: dict
    index: int = 0

    @property
    def title(self) -> str:
        return self.raw.get("title", "")

    @property
    def act(self) -> int:
        return int(self.raw.get("act", 1))

    @property
    def situation(self) -> str:
        return self.raw.get("situation", "medium")

    @property
    def coef(self) -> float:
        return float(self.raw.get("coef", 0.75))

    @property
    def is_achievement(self) -> bool:
        return self.raw.get("type") == "achievement"

    @property
    def has_decision(self) -> bool:
        return bool(self.raw.get("options")) and not self.raw.get("no_decision")

    @property
    def models(self) -> list[str]:
        return list(self.raw.get("models", []))

    @property
    def options(self) -> dict[str, dict]:
        return dict(self.raw.get("options", {}))


@dataclass
class ConfigRegistry:
    """全部配置的唯一入口。所有引擎模块只通过它取数。"""

    data_dir: Path
    cards: dict[str, Any]
    free_time: dict[str, Any]
    monthly: dict[str, Any]
    crisis: dict[str, Any]
    template: dict[str, Any]

    events: dict[str, EventDef] = field(default_factory=dict)

    # ------------------------------------------------------------ 便捷访问
    @property
    def version(self) -> dict[str, str]:
        return {
            "scoring_cards": self.cards.get("version", "?"),
            "free_time": self.free_time.get("version", "?"),
            "monthly_action_nodes": self.monthly.get("version", "?"),
            "crisis_dialogue": self.crisis.get("version", "?"),
        }

    @property
    def loading_base(self) -> dict[str, float]:
        """大五 loading 回退表：C 0.60 / A 0.52 / N 0.50 / O 0.45 / E 0.43。"""
        return dict(self.cards.get("loading_base", {}))

    @property
    def anchor(self) -> dict:
        """锚点参数（生命/奖金/欠款/月度精力/强制休息）。"""
        return dict(self.cards.get("_anchor_params", {}))

    @property
    def flag_flow(self) -> dict:
        return dict(self.cards.get("_flag_flow", {}))

    @property
    def memory_tag_flow(self) -> dict:
        return dict(self.cards.get("_memory_tag_flow", {}))

    def mainline_events(self) -> list[EventDef]:
        """39 个主线事件（按官方顺序）。"""
        return [e for e in self.events.values() if not e.is_achievement]

    def achievement_events(self) -> list[EventDef]:
        return [e for e in self.events.values() if e.is_achievement]

    def decision_events(self) -> list[EventDef]:
        """41 个带决策的节点 = 39 主线 + C4 + C5（C1-C3 为纯演出）。"""
        return [e for e in self.events.values() if e.has_decision]

    @property
    def activities(self) -> list[dict]:
        return list(self.free_time.get("activities", []))

    def activity(self, activity_id: str) -> dict | None:
        for a in self.activities:
            if a.get("activity_id") == activity_id:
                return a
        return None

    @property
    def monthly_templates(self) -> dict[str, dict]:
        return dict(self.monthly.get("templates", {}))

    @property
    def npcs(self) -> dict[str, dict]:
        return dict(self.free_time.get("npcs", {}))

    def summary(self) -> dict:
        return {
            "版本": self.version,
            "节点总数": len(self.events),
            "主线事件": len(self.mainline_events()),
            "成就节点": len(self.achievement_events()),
            "带决策节点": len(self.decision_events()),
            "选项总数": sum(len(e.options) for e in self.events.values()),
            "自由活动": len(self.activities),
            "自由周末槽位": self.free_time.get("schedule", {}).get("total_slots"),
            "月度模板": list(self.monthly_templates),
            "flag 数": len([k for k in self.flag_flow if not k.startswith("_")]),
        }


def load(data_dir: str | Path | None = None) -> ConfigRegistry:
    """加载并组装配置。不做业务校验——校验在 validators 里单独跑。"""
    base = Path(data_dir) if data_dir else DEFAULT_DATA_DIR
    raw = {k: _read(base / name) for k, name in FILES.items()}
    reg = ConfigRegistry(data_dir=base, **raw)

    idx = raw["cards"].get("_index", {})
    for eid in iter_event_ids(raw["cards"]):
        reg.events[eid] = EventDef(event_id=eid, raw=raw["cards"][eid], index=idx.get(eid, 0))
    return reg
