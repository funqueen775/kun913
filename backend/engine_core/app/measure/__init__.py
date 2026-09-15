# -*- coding: utf-8 -*-
"""M2 测量层：把结算链攒下的证据变成「可下结论的数」。

四个模块（算法册 V2.3 §3.4-§6）：
  bayes       大五贝叶斯后验（自评先验 + 行为证据）
  topics      六专题模型聚合（SDT/调节焦点/道德基础/归因/CFC/NFC）+ 门槛降级
  radar       能力六柱归一化（满分按事件口径实算）
  investment  投入结构与内在动机（work 占比 × 自愿系数）

口径红线：六个专题只进报告专题模块，不进大五、不给综合分；证据不足就不说。
"""

from . import bayes, investment, radar, topics  # noqa: F401
