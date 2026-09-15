# -*- coding: utf-8 -*-
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import validators  # noqa: E402
from app.core.loader import load  # noqa: E402


def main() -> int:
    reg = load()
    reports = validators.run_all(reg)
    bad = 0
    for rep in reports:
        print(rep.render())
        print()
        bad += rep.failed
    print("=" * 60)
    print("结论：" + ("全部通过" if bad == 0 else f"{bad} 项失败，见上方 [失败] 行"))
    print("注意：" + ("无" if not any(r.warns for r in reports)
                     else f"{sum(len(r.warns) for r in reports)} 条待确认（见 [注意] 行）"))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
