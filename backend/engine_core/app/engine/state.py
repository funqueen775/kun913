# -*- coding: utf-8 -*-
"""对局状态：一本账两个层（公开账本 + 隐藏账本），外加进度、好感、生存轨。

红线（剧情册 §四 双账本）：
  - 公开层（life/prof/money/level/relation）与隐藏层（六维/能力/大五/专题）字段完全不同；
  - 公开生命 ≠ H 的人格证据；公开专业能力 ≠ S 的测评证据；
  - 两本账互不读写，杜绝从公开数值反推测评。
"""

from __future__ import annotations

import copy
from dataclasses import dataclass, field, asdict
from typing import Any

from ..core import constants as C


# ------------------------------------------------------------------ 决策记录
@dataclass
class DecisionRecord:
    """DecisionLog 的一行。时间口径双记号是硬要求（算法册 §6）。"""

    seq: int                      # 第 N 个决策点（相对序号）——统计与跨玩家对齐一律用它
    month: int                    # 游戏内月份（顺延后）——只用于剧情时间卡片与本玩家证据引用
    source: str                   # mainline / achievement / monthly / free_time / crisis
    node_id: str
    option_id: str
    option_text: str = ""
    rest_month: bool = False      # 是否发生在强制休息月（不进月度节奏统计）
    hesitation_ms: int | None = None   # 前端原始埋点，服务端不加工
    switch_count: int | None = None    # 选项间横跳次数
    snapshot_before: dict = field(default_factory=dict)
    snapshot_after: dict = field(default_factory=dict)
    flags_set: list[str] = field(default_factory=list)
    memory_tags: list[str] = field(default_factory=list)
    note: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


# ------------------------------------------------------------------ 对局状态
@dataclass
class GameState:
    user_id: str = "anonymous"
    seed: int = 0

    # ---------------- 时钟
    month: int = 0
    seq: int = 0
    rest_months: list[int] = field(default_factory=list)
    in_rest_month: bool = False

    # ---------------- 隐藏账本：六维
    S: int = 0
    O: int = 0
    N: int = 0
    H: int = C.H_INIT
    D: int = 0
    pending_dignity: int = 0      # D 只记 pending，月末结算
    risk_cumulative: int = 0      # 风险越小越好；累积过高引爆事故

    # ---------------- 隐藏账本：能力 / 大五证据 / 专题信号
    competency: dict[str, int] = field(default_factory=dict)
    bigfive_evidence: dict[str, list[dict]] = field(default_factory=dict)
    sdt: list[dict] = field(default_factory=list)
    regulatory_focus: list[dict] = field(default_factory=list)
    moral_foundation: list[dict] = field(default_factory=list)
    cognition: list[dict] = field(default_factory=list)
    attribution: list[dict] = field(default_factory=list)
    psych_drive: list[dict] = field(default_factory=list)   # 纯亏选项，命中即引用

    # ---------------- 叙事痕迹
    flags: list[str] = field(default_factory=list)
    memory_tags: list[dict] = field(default_factory=list)
    counter_blame_scenes: int = 0        # 守界者计数器：甩锅场合总数
    counter_blame_held: int = 0          # 其中守住的次数
    counter_nosupervision: int = 0       # 无人监督场合总数
    counter_nosupervision_held: int = 0

    # ---------------- 公开账本（只进游戏内经济，永不进测评）
    life: int = C.LIFE_INIT
    prof: int = 0
    money: int = 0
    debt: int = 0
    level: int = C.LEVEL_MIN
    bonus_total: int = 0

    # ---------------- 关系
    npc_affinity: dict[str, int] = field(default_factory=dict)
    npc_level: dict[str, int] = field(default_factory=dict)
    npc_last_slots: dict[str, list[int]] = field(default_factory=dict)
    intimate_done: list[str] = field(default_factory=list)
    npc_tags: dict[str, list[str]] = field(default_factory=dict)

    # ---------------- 进度
    events_done: list[str] = field(default_factory=list)
    decisions: list[DecisionRecord] = field(default_factory=list)
    promotion_windows: list[dict] = field(default_factory=list)
    consecutive_promotion_failures: int = 0
    crisis_talks: list[dict] = field(default_factory=list)

    # ---------------- 生存轨
    survival_state: str = "stable"
    survival_strikes: int = 0
    months_since_mistake: int = 0
    incidents: list[dict] = field(default_factory=list)

    # ---------------- 月度运行时（不落库）
    rest_points_used_this_month: int = 0
    window_cumulative: int = 0        # 本考核窗六维净累积
    window_flags: list[str] = field(default_factory=list)
    monthly_allocations: list[dict] = field(default_factory=list)
    burnout_active: bool = False      # H 归零进入倦怠期；恢复后（H>0）才允许再次触发

    # ------------------------------------------------------------ 工具方法
    @property
    def hidden_dims(self) -> dict[str, int]:
        return {"S": self.S, "O": self.O, "N": self.N,
                "H": self.H, "D": self.D, "risk": self.risk_cumulative}

    def snapshot(self) -> dict:
        """结算前后的六维快照——用于上线后校准标定表（差值即实测增量）。"""
        return {
            "S": self.S, "O": self.O, "N": self.N, "H": self.H,
            "D": self.D, "pending_dignity": self.pending_dignity,
            "risk_cumulative": self.risk_cumulative,
            "life": self.life, "prof": self.prof, "money": self.money,
            "level": self.level,
        }

    def add_flag(self, flag: str) -> None:
        if flag and flag not in self.flags:
            self.flags.append(flag)

    def has(self, flag: str) -> bool:
        return flag in self.flags

    def add_evidence(self, bucket: str, item: dict) -> None:
        """大五/专题证据累加。防污染第 2 条：只记玩家原本的选择一次，不因增益放大。"""
        getattr(self, bucket).append(item)

    def npc_add(self, npc: str, delta: int, reason: str) -> dict:
        if not delta:
            return {}
        before = self.npc_affinity.get(npc, 0)
        after = max(0, min(C.AFFINITY_MAX, before + delta))
        self.npc_affinity[npc] = after
        level = 1
        for threshold, lv in C.AFFINITY_THRESHOLDS:
            if after >= threshold:
                level = lv
                break
        prev_level = self.npc_level.get(npc, 1)
        self.npc_level[npc] = level
        return {
            "npc_id": npc, "delta": delta, "reason": reason,
            "score_after": after, "level_after": level,
            "level_changed": level != prev_level,
        }

    def clone(self) -> "GameState":
        return copy.deepcopy(self)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["decisions"] = [r.to_dict() for r in self.decisions]
        return d
