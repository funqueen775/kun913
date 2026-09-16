# -*- coding: utf-8 -*-
"""常量层：六维、能力、大五、专题模型的键与中文名。

口径来源：
  - 剧情册《48个月剧情设计详细方案 V5.27》§四 双账本
  - 算法册《报告数据链路与算法设计 V2.3》§3 打分卡、§9 全局参数表
任何新增键都必须先进本文件，禁止在业务代码里散落字符串字面量。
"""

# ---------------------------------------------------------------- 六维（隐藏账本）
DIM_KEYS = ("S", "O", "N", "H", "D", "risk")
DIM_CN = {
    "S": "技能",
    "O": "产出",
    "N": "人脉",
    "H": "认知带宽",
    "D": "尊严",
    "risk": "风险",
}
RISK_KEY = "risk"          # 越小越好（与其他五维方向相反）
DIGNITY_KEY = "D"          # 只记 pending_dignity，月末结算
H_INIT = 10
H_MAX = 10
H_DANGER = 2               # 危险区：H<=2 时硬扛类消耗翻倍（算法册 §10 诚实边界）

# 选项 state_delta 里允许出现的特殊键（非六维）
STATE_DELTA_SPECIAL = ("life_rest",)   # 含 1 个休息点，实际恢复量查月度规则表

# ---------------------------------------------------------------- 能力（雷达）
COMPETENCY_KEYS = (
    "technical_decision", "collaboration", "pragmatism", "assertiveness",
    "resilience", "integrity", "initiative", "execution", "architecture",
    "communication", "ownership",
)

# 雷达六柱 → 能力键的映射。
# ⚠ 待策划确认：本映射为「语义默认值」，与算法册 §9「雷达满分口径」的
#   表值（40/33/33/31/23/14）无法完全对齐——两个原因叠加：
#     ① 表值是按 39 件实算的；② 24 件基准裁件后（scoring_cards v3.0）在册只有 23 张。
#   在册实算值（2026-09-16，validators.check_radar 复算）：
#     原则底线 23 / 执行交付 31 / 技术决策力 19 / 沟通协作 18 / 主动担当 17 / 抗压韧性 4
#   **归一化不受影响**：app/measure/radar.py 的满分是按在册卡动态实算的，
#   RADAR_CAP_IN_DOC 只用于文档对账。待办：把算法册 §9 表值同步改成实算值。
#   ⚠ 抗压韧性只剩 4 分上限（resilience 正分只出现在 3 张在册卡），
#     报告「抗压」柱的解释力显著下降 —— 需策划决定补标定还是该柱改由 H 行为记录补强。
RADAR_MAP = {
    "原则底线": ("integrity",),
    "执行交付": ("execution", "pragmatism"),
    "技术决策力": ("technical_decision", "architecture"),
    "沟通协作": ("collaboration", "communication"),
    "主动担当": ("initiative", "ownership", "assertiveness"),
    "抗压韧性": ("resilience",),
}
# 算法册 §9 记载的满分（待确认口径）
RADAR_CAP_IN_DOC = {
    "原则底线": 40, "执行交付": 33, "技术决策力": 33,
    "沟通协作": 31, "主动担当": 23, "抗压韧性": 14,
}

# ---------------------------------------------------------------- 大五
BIGFIVE_KEYS = ("O", "C", "E", "A", "N")   # 注意：大五的 N=情绪稳定，与六维 N=人脉不同名不同义
BIGFIVE_CN = {"O": "开放性", "C": "尽责性", "E": "外向性", "A": "宜人性", "N": "情绪稳定"}
BIGFIVE_MIN_EVIDENCE = 5    # 行为标记 n<5 时该特质只出自评条（算法册 §6）

# 情境系数：没人看着 1.0 / 一般场合 0.75 / 有人盯着 0.5
SITUATION_COEF = {"weak": 1.0, "medium": 0.75, "strong": 0.5}

# ---------------------------------------------------------------- 六个补充心理学模型
SDT_KEYS = ("autonomy", "competence", "relatedness")
SDT_CN = {"autonomy": "自主性", "competence": "胜任感", "relatedness": "归属感"}
MORAL_KEYS = ("care", "fairness", "loyalty", "authority", "sanctity", "liberty")
MORAL_CN = {
    "care": "关怀", "fairness": "公平", "loyalty": "忠诚",
    "authority": "权威", "sanctity": "圣洁（未标定，预留）", "liberty": "自由",
}
REGULATORY_FOCUS = ("promotion", "prevention")   # 促进 / 预防
COGNITION_KEYS = ("NFC", "CFC")                   # 认知需求 / 未来取向
ATTRIBUTION_KEYS = ("locus", "stability", "controllable")

# 各专题模型的展示门槛（算法册 §3.4 汇总表）
# ⚠ 2026-09-16（24 件基准裁件后）：下面这些门槛是**按 44 节点标定的**。
#   在册只剩 23 件 → 大部分模块的样本数会掉到门槛以下，报告会大面积「不出模块」。
#   这是裁件最直接的副作用。**本轮未改数值**（门槛是报告口径，属 Batch 3 / 报告层决定）。
#   待办：把 23 件下的实测样本数跑一遍（`app/report/__init__.py` 的 sample 统计），
#   要么整体下调门槛，要么明确砍掉拿不到样本的模块 —— 二选一，别让它静默不出。
TOPIC_MIN_EVIDENCE = {
    "sdt": 5,            # n>=5
    "regulatory_focus": 3,  # 每场景 n>=3
    "moral_foundation": 3,  # 单弦 n>=3
    "CFC": 4,            # n>=4
    "NFC": 3,            # n>=3
    "attribution": 1,    # E19 命中即引用；危机对话可下结论
}

# ---------------------------------------------------------------- 公开账本
LIFE_INIT = 10
LIFE_MAX = 10
LIFE_MONTHLY_REGEN = 1
BONUS_TIER = ("excellent", "achieved", "none")
MONEY_INIT = 0

# ---------------------------------------------------------------- 职级与晋升
LEVEL_MIN, LEVEL_MAX = 1, 7
PROMOTION_MONTHS = (6, 12, 18, 24, 30, 36, 42)   # 7 个考核窗
PROMOTION_WEIGHTS = {"cumulative": 0.70, "behavior": 0.20, "defense": 0.10}
FINAL_GRADE = {"传承者": (6, 7), "中坚者": (3, 5), "守界者": (1, 2)}

# 隐瞒类 flag —— 行为层与生存轨的输入（剧情册 §2.1）
CONCEAL_FLAGS = ("ai_undisclosed", "blame_shift", "data_risk")

# 守界者终局的两个专用计数器（算法册 §6）
# ⚠ 2026-09-16（24 件基准裁件后）：原各 3 个场合，归档 E07/E31/E21/E22 后各只剩 1 个在册。
#   **本行数值未改**（场合集合是产品语义，改动会直接影响终局文案里的「N 次里守住 M 次」，
#   不能由数据层单方面决定）。validators.check_counters 会把该项降级为「注意」并提示重定。
#   建议的重定方向（**待策划点头，勿自行落地**）：
#     甩锅族：E19（甩锅给模型）+ E17（翻车蒙过去）+ E41（指标粉饰）→ 计数面回到 3
#     无人监督族：E03（深夜没人在场）+ E42（无人复核就使用他人故事）→ 计数面回到 2
COUNTER_BLAME_SCENES = ("E07", "E19", "E31")     # 甩锅场合总数
COUNTER_NOSUPERVISION = ("E03", "E21", "E22")    # 无人监督场合总数

# ---------------------------------------------------------------- 生存轨
SURVIVAL_STATES = ("stable", "observation", "critical", "last_talk", "exited")
SURVIVAL_CN = {
    "stable": "稳定", "observation": "观察", "critical": "危急",
    "last_talk": "最后谈话", "exited": "已离场",
}
NEWBIE_PROTECT_MONTHS = 12      # 前 12 个月不进危急
SELF_HEAL_MONTHS = 6            # 连续 6 个月无新增失误 → 自动回升一级

# ---------------------------------------------------------------- 自由活动
FREE_TIME_CADENCE = 3
FREE_TIME_SLOTS = 16
WEATHER_DIST = {"sunny": 0.8, "rainy": 0.2}
AFFINITY_THRESHOLDS = ((80, 5), (60, 4), (40, 3), (20, 2), (0, 1))  # 高→低
AFFINITY_MAX = 100
DIMINISHING_SAME_NPC = 3        # 同 NPC 连续 3 次后倍率
DIMINISHING_MULTIPLIER = 0.5

# ---------------------------------------------------------------- 埋点（17 个）
TRACKING_EVENTS = (
    "profile_start", "profile_answer", "manual_read", "event_trigger",
    "node_enter", "option_hover", "option_click", "allocation_click",
    "explore_click", "survival_state_change", "crisis_talk_choice",
    "monthly_action_variant", "achievement_view", "zone_dwell",
    "ai_reaction_view", "task_complete", "report_view",
)

# 时间口径（算法册 §6）：所有统计用 seq，只有展示用 month
TOTAL_MONTHS = 48

# ---------------------------------------------------------------- M2 测量层（算法册 §4/§5/§3.4）
# 大五行为分：对 0-10 量表中点等比缩放。
#   行为分 = MID + DEV_MAX × mean(dir×coef) × loading_base[trait]
#   「行为分对中点的偏离随该特质载荷等比变化」（算法册 §4 口径说明）：
#   旧 C=1.00 时 3.5 → ×0.6 → 4.1，本公式同时复现两个数。
BAYES_MID = 5.0
BAYES_DEV_MAX = 5.0
BAYES_K_DENOM = 5            # K = n / (n + 5)
CONFLICT_THRESHOLD = 1.5     # 矛盾度超过 1.5 判定显著（算法册 §4）

# 调节焦点分场景（算法册 §3.4 模型二）：整体比例会说谎，必须拆平时 vs 事故
# ⚠ 2026-09-16：ARCHIVED = E06 / E30 / E16 已随裁件归档，在册只剩 E04/E23/E24 与 E09。
#   topics.py 会因样本不足而少出「调节焦点」模块（门槛 n>=3）。**本轮不改** ——
#   建议的重定（待策划点头）：DAILY 补 E40（继承者路线分歧），INCIDENT 补 E17（现场翻车）。
REGULATORY_DAILY = ("E04", "E06", "E23", "E24", "E30")     # 选型/架构/重构/技术栈/全自动
REGULATORY_INCIDENT = ("E09", "E16")                        # 成本爆/凌晨热修复

# 内在动机：work 型占比 × 自愿系数（自己想做=1.0，加班=0.6）
OVERTIME_ACTIVITIES = ("S4",)   # S4 周末加班 = 卷公司的活，自愿系数 0.6
VOLUNTEER_COEF = 1.0
OVERTIME_COEF = 0.6

# psych_drive 标记 → 报告文案（算法册 §6 表，命中即引用；预留标记无数据不下发）
PSYCH_DRIVE_LINES = {
    "avoid_conflict": "你怕的不是麻烦，是关系破裂。",
    "transfer_pressure": "比起解决问题，你更想先解决「这是谁的问题」。",
    "please_others": "你先想的是对方怎么想，然后才是你自己。",
    "relieve_guilt": "你选它不是为了好处，是为了晚上睡得着。",
}

# 雷达样本最薄的柱（抗压韧性仅约 10 处机会），报告须说明由 H 行为记录补强
RADAR_THIN_PILLAR = "抗压韧性"
