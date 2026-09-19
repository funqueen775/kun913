# -*- coding: utf-8 -*-
"""岗位适配：理想点模型（算法设计 V2.3 §5）。

三步中的第 2、3 步落地：
  六型 → 岗位向量（内置策划口径岗位画像，真实 JD 语料接入后按词频重建）→
  匹配 = 理想点模型：单维贡献 = 权重 × (1 − |实际 − 理想| ÷ 容忍度)，clamp ≥ 0。

红线（诚实边界 §10）：
  - 只做排序，不做「你适合/不适合」断言，禁止「只能做 X」；
  - 大五证据不足的维度（posterior=None）不参与该维贡献，不硬编、不假设。
"""

from __future__ import annotations

import json
from pathlib import Path

TRAIT_CN = {"O": "开放性", "C": "尽责性", "E": "外向性", "A": "宜人性", "N": "情绪稳定"}
TRAITS = "OCEAN"


def load_profiles(path: str | Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def match(posterior: dict, job: dict, tolerance: float | None = None,
          evidence: dict | None = None) -> dict:
    """单岗位理想点匹配。posterior: {trait: float|None}。

    证据不足的维度（None）计权重但不给贡献分——不假设玩家在该维合拍，
    避免「缺维越多分越高」的虚高（外向型岗位不会因为玩家没外向证据而白赚）。

    evidence: {trait: 行为证据条数}，随 dims 下发供报告展示证据强度。
    available 表示该维实际参与了匹配（有后验分），阈值数字不下发（呈现铁律）。
    """
    tol = tolerance or float(job.get("tolerance") or 2.0)
    weights = job.get("weight") or {}
    ideal = job["ideal"]
    total_w, total_s = 0.0, 0.0
    dims = []
    for t in TRAITS:
        w = float(weights.get(t, 1.0))
        total_w += w
        actual = posterior.get(t)
        cnt = int((evidence or {}).get(t, 0))
        if actual is None:
            dims.append({"trait": t, "traitCn": TRAIT_CN[t], "actual": None,
                         "ideal": ideal.get(t, 5.0), "gap": None, "contrib": 0.0,
                         "evidenceCount": cnt, "available": False})
            continue
        gap = abs(actual - ideal.get(t, 5.0))
        contrib = max(0.0, 1.0 - gap / tol)
        total_s += w * contrib
        dims.append({"trait": t, "traitCn": TRAIT_CN[t], "actual": round(actual, 2),
                     "ideal": ideal.get(t, 5.0), "gap": round(gap, 2),
                     "contrib": round(contrib, 2), "evidenceCount": cnt,
                     "available": True})
    score = total_s / total_w if total_w else 0.0
    return {"jobId": job["id"], "title": job["title"], "score": round(score * 100, 1),
            "dims": dims}


def rank(posterior: dict, profiles: dict, top: int | None = None,
         evidence: dict | None = None) -> list[dict]:
    results = [match(posterior, j, evidence=evidence) for j in profiles["jobs"]]
    results.sort(key=lambda r: r["score"], reverse=True)
    return results[:top] if top else results


def _advice_line(result: dict, job: dict) -> str:
    real = [d for d in result["dims"] if d["gap"] is not None]
    missing = len(result["dims"]) - len(real)
    if not real:
        return "这一份的证据还不够定位你与岗位的关系，参考就好。"
    best = max(real, key=lambda d: d["contrib"])
    worst = max(real, key=lambda d: d["gap"])
    parts = [f"最看重「{job['emphasisPhrase']}」（{job['emphasis']}）"]
    if best["gap"] <= 0.5:
        parts.append(f"你的{TRAIT_CN[best['trait']]}和它合拍")
    elif best["gap"] <= 1.0:
        parts.append(f"你的{TRAIT_CN[best['trait']]}接近它的要求")
    if worst["gap"] >= 1.5:
        parts.append(f"你的{TRAIT_CN[worst['trait']]}和它差一截")
    elif all(d["gap"] <= 0.5 for d in real):
        parts.append("你和它几乎处处合拍")
    if missing >= 2:
        parts.append(f"{missing} 个维度证据不足，仅按现有维度参考")
    return "；".join(parts)


def build_career_advice(posterior: dict, profiles: dict, top: int = 3,
                        evidence: dict | None = None) -> list[dict]:
    """Top N 岗位 + 每岗一句话（岗位要什么 / 你合在哪 / 差在哪）+ 五维明细。"""
    by_id = {j["id"]: j for j in profiles["jobs"]}
    out = []
    for r in rank(posterior, profiles, top, evidence=evidence):
        job = by_id[r["jobId"]]
        out.append({**r, "emphasis": job["emphasis"],
                    "emphasisPhrase": job["emphasisPhrase"],
                    "line": _advice_line(r, job)})
    return out
