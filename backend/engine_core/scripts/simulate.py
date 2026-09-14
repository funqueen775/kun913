# -*- coding: utf-8 -*-
"""48 个月端到端跑批。用于验证引擎无崩溃、数值自洽，并给后续对账做基线。

用法：
  python scripts/simulate.py                      # 默认 index 策略
  python scripts/simulate.py --policy utility     # 功利策略（压力测试）
  python scripts/simulate.py --policy random --seed 7
  python scripts/simulate.py --policy utility --json out.json
  python scripts/simulate.py --trace 30           # 打印前 30 个月的逐月轨迹
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.loader import load  # noqa: E402
from app.engine import simulation as sim  # noqa: E402
from app.engine.timeline import build_schedule  # noqa: E402

POLICIES = {
    "index": sim.IndexPolicy,
    "random": sim.RandomPolicy,
    "utility": sim.UtilityPolicy,
}


def render_summary(s: dict) -> str:
    L = []
    L.append("─" * 62)
    L.append(f"决策点数 {s['决策点数']}（{s['按来源']}）")
    L.append(f"核心选择数 {s['核心选择数_算法册口径']}（算法册 §1 口径 =39 主线 +48 月度 +16 自由周末=103）")
    L.append(f"月份推进到第 {s['月份']} 月    职级 L{s['职级']}")
    L.append(f"六维（隐藏账本）：{s['六维']}   月末待结算 D={s['pending_dignity']}")
    L.append(f"公开账本：{s['公开账本']}")
    L.append(f"强制休息月：{s['强制休息月'] or '无'}")
    L.append("考核窗：" + " | ".join(f"M{m}:{'升' if p else '未升'}→L{lv}"
                                     for m, p, lv in s["考核窗"]))
    L.append(f"连续未达标 {s['连续未达标']} 次    危机对话 {s['危机对话次数']} 次")
    L.append(f"存活状态 {s['生存轨']}   失误 streak {s['失误数_当前streak']} / 累计 {s['失误数_累计']}"
             f"   倦怠 {s['倦怠事件次数']} 次   危险区决策次数 {s['危险区决策次数']}")
    if s["事故清单"]:
        L.append("事故清单：" + " | ".join(s["事故清单"]))
    L.append(f"flags：{s['flags'] or '无'}")
    L.append(f"大五证据条数：{s['大五证据条数']}")
    L.append(f"大五加权和：{s['大五加权和']}")
    L.append(f"能力：{s['能力']}")
    L.append(f"专题条数：SDT {s['SDT条数']} / 调节焦点 {s['调节焦点条数']} / "
             f"道德 {s['道德条数']} / 归因 {s['归因条数']} / CFC·NFC {s['CFC/NFC条数']}")
    L.append(f"psych_drive 命中：{s['psych_drive'] or '无'}")
    b = s["守界者计数器"]
    L.append(f"守界者计数器：甩锅场合 {b['甩锅场合'][1]}/{b['甩锅场合'][0]} 守住，"
             f"无人监督场合 {b['无人监督场合'][1]}/{b['无人监督场合'][0]} 守住")
    L.append(f"好感度：{s['好感度']}")
    L.append(f"记忆标签 {s['记忆标签数']} 条")
    L.append(f"终局：{s['终局']}")
    L.append("─" * 62)
    return "\n".join(L)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", default="index", choices=list(POLICIES))
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--user", default="sim")
    ap.add_argument("--json", dest="json_out", default=None)
    ap.add_argument("--trace", type=int, default=0, help="打印前 N 个月的逐月轨迹")
    args = ap.parse_args()

    reg = load()
    sched = build_schedule(reg)
    print(f"配置版本：{reg.version}")
    print(f"排期：{len(sched)} 个节点排进 {sched[0][0]}–{sched[-1][0]} 月"
          f"（{sched[0][1]} … {sched[-1][1]}）")
    print(f"策略：{args.policy}    seed={args.seed}")

    policy = POLICIES[args.policy](seed=args.seed) if args.policy == "random" \
        else POLICIES[args.policy]()
    result = sim.run(reg, policy, seed=args.seed, user_id=args.user, schedule=sched)
    summary = sim.summarize(reg, result)
    print(render_summary(summary))

    if args.trace:
        print("\n逐月轨迹（前 %d 月）：" % args.trace)
        for rec in result.log.months[:args.trace]:
            bits = []
            if rec["rest_month"]:
                bits.append("[强制休息月]")
            for e in rec["events"]:
                bits.append(f"{e['event_id']}·{e.get('option_id', 'view')}")
            if rec["monthly"]:
                bits.append(f"月度{rec['monthly']['option_id']}")
            if rec["free_weekend"]:
                bits.append(f"周末{rec['free_weekend']['activity_id']}")
            if rec["promotion"]:
                bits.append("考核" + ("升" if rec["promotion"]["promoted"] else "未升"))
            if rec["crisis"]:
                bits.append(f"危机{rec['crisis']['option_id']}")
            if rec["survival"] and rec["survival"]["changed"]:
                bits.append(f"状态→{rec['survival']['to']}")
            print(f"  第 {rec['month']:2d} 月  " + "  ".join(bits))

    if args.json_out:
        payload = {"summary": summary, "state": result.state.to_dict()}
        Path(args.json_out).write_text(
            json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"\n已写出 {args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
