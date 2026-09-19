# -*- coding: utf-8 -*-
"""六专题模型聚合（算法册 V2.3 §3.4）。

每个模型走同一条链：累加成什么数 → 展示门槛 → 不够怎么办。
红线：只进报告专题模块，不进大五、不给综合分；每个结论必须引用 ≥3 条行为证据，
不够就不说（displayable=False，报告层整体不渲染）。

归因是双层测量：E19 全员必遇（命中即引用，不下习惯结论）；连续晋升失败者的
危机对话叠加后凑成两处观测，两处解释的落差本身就是指纹，可下结论。
"""

from __future__ import annotations

from ..core import constants as C
from ..engine.state import GameState

# E19 归因三维 → 心理学含义（算法册 §3.4 模型四表）
# 注意：打分卡里 controllable 是布尔值，键必须按布尔匹配，否则永远落兜底分支
_ATTRIBUTION_MEANING = {
    ("external", "unstable", False): "外归因但有据：先定位到规则或环境，不急着归咎自己",
    ("internal", "unstable", True): "内-行为归因：认的是可修的流程做法，最健康",
    ("external", "stable", False): "稳定且不可控的外归因：与「我天生不行」同构，最需要警惕",
}


def _decisions_by_seq(state: GameState) -> dict[int, object]:
    return {d.seq: d for d in state.decisions}


def _refs(state: GameState, items: list[dict], limit: int = 3) -> list[dict]:
    """从证据条目（带 seq）取最多 limit 条，转成 EvidenceRef 形状。"""
    by_seq = _decisions_by_seq(state)
    out = []
    for it in items:
        d = by_seq.get(it.get("seq"))
        if d is None:
            continue
        out.append({
            "seq": d.seq, "month": d.month, "rest_month": d.rest_month,
            "node_id": d.node_id, "option_id": d.option_id,
            "hesitation_ms": d.hesitation_ms, "switch_count": d.switch_count,
            "snippet": d.option_text or d.node_id,
        })
        if len(out) >= limit:
            break
    return out


def _module(key: str, title: str, n: int, threshold: int, summary: str,
            bullets: list[dict], items: list[dict], state: GameState) -> dict:
    return {
        "key": key, "title": title, "n": n, "threshold": threshold,
        "displayable": n >= threshold,
        "summary": summary if n >= threshold else "",
        "bullets": bullets if n >= threshold else [],
        "evidence": _refs(state, items) if n >= threshold else [],
    }


# ---------------------------------------------------------------- 模型一 SDT
def sdt(state: GameState) -> dict:
    items = state.sdt
    n = len(items)
    bullets = []
    for k in C.SDT_KEYS:
        vals = [float(i.get(k, 0)) for i in items]
        mean = sum(vals) / n if n else 0.0
        band = "强" if mean >= 0.5 else ("弱" if mean <= -0.5 else "中")
        bullets.append({"label": C.SDT_CN[k], "value": band})
    summary = ""
    if n:
        auto = sum(float(i.get("autonomy", 0)) for i in items) / n
        rel = sum(float(i.get("relatedness", 0)) for i in items) / n
        if auto >= 0.5 and rel < 0.5:
            summary = "靠热爱和成就感驱动，不太靠关系驱动。"
        elif rel >= 0.5 and auto < 0.5:
            summary = "你做事的动力更多来自「有人在乎」。"
        elif auto >= 0.5 and rel >= 0.5:
            summary = "想做得好，也在乎一起做的人。"
        else:
            summary = "动力信号偏弱：多数选择不是你想做的。"
    return _module("sdt", "内在动机与适配信号", n,
                   C.TOPIC_MIN_EVIDENCE["sdt"], summary, bullets, items, state)


# ---------------------------------------------------------------- 模型二 调节焦点
def regulatory_focus(state: GameState) -> dict:
    items = state.regulatory_focus
    n = len(items)
    daily = [i for i in items if i.get("node") in C.REGULATORY_DAILY]
    incident = [i for i in items if i.get("node") in C.REGULATORY_INCIDENT]

    def _count(group: list[dict]) -> tuple[int, int]:
        promo = sum(1 for i in group if i.get("focus") == "promotion")
        return promo, len(group) - promo

    dp, dq = _count(daily)
    ip, iq = _count(incident)
    bullets = [
        {"label": "促进 vs 预防（日常）", "value": f"促进 {dp} 次 · 预防 {dq} 次"},
        {"label": "促进 vs 预防（事故）", "value": f"促进 {ip} 次 · 预防 {iq} 次"},
    ]
    # 某场景 n<3 → 只报另一场景（算法册 §3.4）
    if len(daily) < C.TOPIC_MIN_EVIDENCE["regulatory_focus"]:
        bullets = bullets[1:]
    elif len(incident) < C.TOPIC_MIN_EVIDENCE["regulatory_focus"]:
        bullets = bullets[:1]

    summary = ""
    if n:
        if dp > dq and iq >= ip:
            summary = "机会面前敢押，出了事先止损——你不是保守，是知道什么时候该保守。"
        elif dq > dp and iq >= ip:
            summary = "平时求稳，出事更求稳——你盯住的是「别出事」。"
        elif ip > iq and dp > dq:
            summary = "什么时候都在追收益——注意别把止损当认输。"
        else:
            summary = "整体偏预防型：先守住，再谈赢。"
    return _module("regulatory_focus", "决策风格（调节焦点）", n,
                   C.TOPIC_MIN_EVIDENCE["regulatory_focus"], summary, bullets, items, state)


# ---------------------------------------------------------------- 模型三 道德基础
def moral_foundation(state: GameState) -> dict:
    items = state.moral_foundation
    strings: dict[str, dict] = {}
    for it in items:
        for k, v in it.items():
            if k in ("seq", "month", "node", "option") or not isinstance(v, (int, float)):
                continue
            s = strings.setdefault(k, {"net": 0, "n": 0})
            s["net"] += int(v)
            s["n"] += 1
    passing = [(k, s) for k, s in strings.items()
               if abs(s["net"]) >= 3 and s["n"] >= C.TOPIC_MIN_EVIDENCE["moral_foundation"]
               and k in C.MORAL_KEYS and k != "sanctity"]
    passing.sort(key=lambda kv: kv[1]["net"], reverse=True)
    n_total = len(items)
    bullets = [{"label": C.MORAL_CN.get(k, k), "value": f"净分 {s['net']:+d}（{s['n']} 次）"}
               for k, s in passing]
    summary = ""
    if passing:
        top, top_s = passing[0]
        bottom, bottom_s = passing[-1]
        if bottom_s["net"] < 0 < top_s["net"]:
            summary = (f"你在{C.MORAL_CN[top]}和{C.MORAL_CN[bottom]}之间，"
                       f"把{C.MORAL_CN[top]}排在了前面。")
        else:
            summary = f"你最响的一根弦是{C.MORAL_CN[top]}。"
    # displayable 看是否有弦过门槛，而不是总数
    mod = _module("moral_foundation", "价值观（道德基础）", n_total,
                  C.TOPIC_MIN_EVIDENCE["moral_foundation"], summary, bullets, items, state)
    mod["displayable"] = bool(passing)
    if not passing:
        mod["summary"] = ""
        mod["bullets"] = []
        mod["evidence"] = []
    return mod


# ---------------------------------------------------------------- 模型四 归因
def attribution(state: GameState) -> dict:
    """双层：E19 全员（命中即引用）+ 危机对话（卡住玩家）。两处落差即指纹。"""
    items = state.attribution
    crisis = list(state.crisis_talks)
    n = len(items) + len(crisis)
    bullets: list[dict] = []
    summary = ""

    def _meaning(attr: dict | None) -> str:
        if not attr:
            return "回避"
        if attr.get("locus") in (None, "avoid"):
            return "回避"
        hit = _ATTRIBUTION_MEANING.get((attr.get("locus"), attr.get("stability"),
                                        attr.get("controllable")))
        if hit:
            return hit
        # 兜底：只给方向词，绝不外泄内部结构
        parts = []
        if attr.get("locus") == "internal":
            parts.append("内归因")
        elif attr.get("locus") == "external":
            parts.append("外归因")
        if attr.get("stability") == "stable":
            parts.append("稳定")
        elif attr.get("stability") == "unstable":
            parts.append("不稳定")
        if attr.get("controllable") is True:
            parts.append("可控")
        elif attr.get("controllable") is False:
            parts.append("不可控")
        return "归因方向：" + "、".join(parts) if parts else "回避"

    for it in items:
        bullets.append({"label": f"事故当场（{it.get('node')}）", "value": _meaning(it)})
    for c in crisis:
        bullets.append({"label": f"复盘（第 {c.get('month')} 月危机对话）", "value": _meaning(c.get("attribution"))})

    if len(items) + len(crisis) >= 2 and items and crisis:
        m1 = _meaning(items[0])
        m2 = _meaning(crisis[0].get("attribution"))
        if m1 == m2:
            summary = "事故当场和坐下来复盘，你解释失败的方式一致——这个归因方式可信。"
        else:
            summary = "事故当场和复盘时，你解释失败的方式不一样——压力越大，解释越往外，落差本身就是信号。"
    elif items:
        summary = "这是你在事故当场的第一反应（单次观测，引用不下习惯结论）。"

    return _module("attribution", "归因方式", n,
                   C.TOPIC_MIN_EVIDENCE["attribution"], summary, bullets, items + [
                       {"seq": None, "node": c.get("option_id")} for c in crisis], state)


# ---------------------------------------------------------------- 模型五/六 CFC / NFC
def cognition(state: GameState) -> list[dict]:
    """cognition 记录可能同时带 CFC 与 NFC，拆成两个模块（门槛不同）。"""
    items = state.cognition
    by_seq = _decisions_by_seq(state)
    cfc_items = []
    nfc_items = []
    for it in items:
        d = by_seq.get(it.get("seq"))
        hes = d.hesitation_ms if d is not None else None
        if "CFC" in it:
            cfc_items.append({**it, "_val": it["CFC"], "_hesitation": hes})
        if "NFC" in it:
            nfc_items.append({**it, "_val": it["NFC"], "_hesitation": hes})

    out: list[dict] = []

    def _mean(vals: list[float]) -> float:
        return sum(vals) / len(vals) if vals else 0.0

    # CFC：均值 −2~+2，报告只给档位不给点值（算法册 §3.4 模型五）
    n = len(cfc_items)
    summary = ""
    mode = ""
    if n:
        m = _mean([i["_val"] for i in cfc_items])
        if m >= 0.5:
            mode = "偏长远"
            summary = "你愿意为以后牺牲眼前。"
        elif m <= -0.5:
            mode = "偏眼前"
            summary = "你更看重眼前——远期的账，你不太算。"
        else:
            mode = "远近摇摆"
            summary = "摇摆型：大的远见有，小的偷懒也多——你的远见是有尺寸的。"
    bullets = [{"label": "未来取向", "value": mode}] if n else []
    out.append(_module("cfc", "未来取向", n, C.TOPIC_MIN_EVIDENCE["CFC"],
                       summary, bullets, cfc_items, state))

    # NFC：均值 + 与犹豫时长交叉（算法册 §3.4 模型六）
    n = len(nfc_items)
    with_h = [i for i in nfc_items if i.get("_hesitation") is not None]
    summary = ""
    mode = ""
    if n:
        m = _mean([i["_val"] for i in nfc_items])
        pos = [i for i in nfc_items if i["_val"] > 0]
        neg = [i for i in nfc_items if i["_val"] < 0]
        if m >= 0.3:
            mode = "偏高（爱啃难题）"
            summary = "你爱难题本身，不只看结果。"
        elif m <= -0.3:
            mode = "偏低（能省则省）"
            summary = "能省则省——难题对你更多是负担。"
        else:
            mode = "时有时无"
            summary = "对难题的兴趣时有时无。"
    bullets = [{"label": "认知需求", "value": mode}] if n else []
    if with_h and pos and neg:
        bullets.append({"label": "爱啃的题上犹豫时长",
                        "value": f"{round(sum((i.get('_hesitation') or 0) for i in pos) / len(pos) / 1000, 1)} 秒（对比 {round(sum((i.get('_hesitation') or 0) for i in neg) / len(neg) / 1000, 1)} 秒）"})
    out.append(_module("nfc", "思维方式（认知需求）", n, C.TOPIC_MIN_EVIDENCE["NFC"],
                       summary, bullets, nfc_items, state))
    return out


# ---------------------------------------------------------------- 纯亏选项（§6 最强证据）
def psych_drive(state: GameState) -> list[dict]:
    """命中即高光引用；一处都没选到 → 空列表，不做补偿性推断。"""
    by_seq = _decisions_by_seq(state)
    out = []
    for p in state.psych_drive:
        line = C.PSYCH_DRIVE_LINES.get(p.get("tag"))
        if not line:
            continue
        d = by_seq.get(p.get("seq"))
        out.append({
            "tag": p.get("tag"),
            "line": line,
            "evidence": None if d is None else {
                "seq": d.seq, "month": d.month, "rest_month": d.rest_month,
                "node_id": d.node_id, "option_id": d.option_id,
                "hesitation_ms": d.hesitation_ms, "switch_count": d.switch_count,
                "snippet": d.option_text or d.node_id,
            },
        })
    return out


def build_topics(state: GameState) -> list[dict]:
    """六个专题模块 + 归因。displayable=False 的模块报告层不渲染。"""
    mods = [sdt(state), regulatory_focus(state), moral_foundation(state), attribution(state)]
    mods.extend(cognition(state))
    return mods
