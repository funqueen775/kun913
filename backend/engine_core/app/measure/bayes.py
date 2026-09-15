# -*- coding: utf-8 -*-
"""大五贝叶斯后验（算法册 V2.3 §4 核心算法）。

医生比喻：自评是先验（病人自述），行为分是证据（化验单），后验是诊断。

公式（逐符号见 build_posteriors 的 docstring）：
    后验 = 自评 + K × (行为分 − 自评)，K = n / (n + 5)
    行为分 = MID + DEV_MAX × mean(dir×coef) × loading_base[trait]
    矛盾度 = |自评 − 后验|，超过 CONFLICT_THRESHOLD 判显著

行为分的缩放假设（算法册 §4 口径说明）：行为分对中点的偏离随该特质载荷等比变化
——旧 loading_base C=1.00 时 3.5 → ×0.6 → 4.1，本实现同时复现两个数。

证据不足（n < BIGFIVE_MIN_EVIDENCE）→ 只保留自评条；自评也缺 → 只出行为条。
跨情境一致性：把证据按情境系数分「没人看着(1.0)」与「有人盯着(0.5)」两组，
两组均值同号 → consistent；异号 → situational（「你的 X 是有条件的」）；
任一组 n<3 → 无法判定（None）。
"""

from __future__ import annotations

from ..core import constants as C
from ..engine.state import GameState

_SCENARIOS = (
    ("alone", 1.0),      # 没人看着（coef>=1.0）
    ("watched", 0.5),    # 有人盯着（coef<=0.5）
)


def _behavior_score(evidence: list[dict], base: dict) -> float | None:
    """行为分。evidence 为该特质的加权证据列表（settlement ③ 产出）。"""
    if not evidence:
        return None
    ratios = [float(e.get("dir", 1)) * float(e.get("coef", 0.75)) for e in evidence]
    mean_ratio = sum(ratios) / len(ratios)                 # ∈ [-1, 1]
    trait = evidence[0].get("trait")
    loading = float(base.get(trait, 1.0))
    return round(C.BAYES_MID + C.BAYES_DEV_MAX * mean_ratio * loading, 2)


def _behavior_std(evidence: list[dict]) -> float | None:
    """加权载荷的标准差（算法册中等级修正：「行为分附标准差」）。"""
    vals = [float(e.get("weighted", 0.0)) for e in evidence]
    if len(vals) < 2:
        return None
    mean = sum(vals) / len(vals)
    var = sum((v - mean) ** 2 for v in vals) / (len(vals) - 1)
    return round(var ** 0.5, 3)


def _consistency(evidence: list[dict]) -> str | None:
    """跨情境一致性（信度检查）。两组各自按 dir 均值判方向。"""
    groups: dict[str, list[int]] = {"alone": [], "watched": []}
    for e in evidence:
        coef = float(e.get("coef", 0.75))
        if coef >= 0.9:
            groups["alone"].append(int(e.get("dir", 1)))
        elif coef <= 0.6:
            groups["watched"].append(int(e.get("dir", 1)))
    means = {}
    for name, dirs in groups.items():
        if len(dirs) < 3:
            return None                        # 任一组样本不足 → 不下信度结论
        means[name] = sum(dirs) / len(dirs)
    a, b = means["alone"], means["watched"]
    if a == 0 or b == 0:
        return None
    return "consistent" if (a > 0) == (b > 0) else "situational"


def build_posteriors(state: GameState, loading_base: dict,
                     self_ratings: dict[str, float] | None = None) -> list[dict]:
    """逐特质产出报告层需要的对照条数据。

    self_ratings：建档自评（profile_answer 埋点落库后传入），0-10 分制，键为大五字母。
    缺省（未建档/跑批）按 None 处理，对应特质不出后验与矛盾度。
    """
    self_ratings = self_ratings or {}
    out: list[dict] = []
    for trait in C.BIGFIVE_KEYS:
        evidence = state.bigfive_evidence.get(trait, [])
        n = len(evidence)
        enough = n >= C.BIGFIVE_MIN_EVIDENCE
        behavior = _behavior_score(evidence, loading_base) if enough else None
        std = _behavior_std(evidence) if enough else None
        consistency = _consistency(evidence) if enough else None
        self_score = self_ratings.get(trait)
        self_score = float(self_score) if self_score is not None else None

        posterior = None
        conflict = None
        conflict_significant = False
        if self_score is not None and behavior is not None:
            k = n / (n + C.BAYES_K_DENOM)
            posterior = round(self_score + k * (behavior - self_score), 2)
            conflict = round(abs(self_score - posterior), 2)
            conflict_significant = conflict > C.CONFLICT_THRESHOLD

        out.append({
            "trait": trait,
            "trait_cn": C.BIGFIVE_CN[trait],
            "self": self_score,
            "behavior": behavior,
            "behavior_std": std,
            "posterior": posterior,
            "conflict": conflict,
            "conflict_significant": conflict_significant,
            "evidence_count": n,
            "behavior_available": behavior is not None,
            "consistency": consistency,
            # 阈值数字永不进报告；这里只给事实，措辞由报告层翻译
            "_threshold_note": None if enough else f"行为证据不足（{n}<{C.BIGFIVE_MIN_EVIDENCE}），仅供参考",
        })
    return out


def significant_conflicts(trait_rows: list[dict]) -> list[dict]:
    """显著矛盾点列表（报告「自评 vs 行为矛盾」模块）。"""
    return [r for r in trait_rows if r["conflict_significant"]]
