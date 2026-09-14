# 旧工程归档（只读）

2026-09-13 从 `E:/workbuddy/2026-09-07-12-07-39/xiongxinzhuangzhi/` 整体迁入。
**这里的东西是历史资产与权威文档的存档，不是运行时依赖**；除下面「仍在用的数据」外，改动它们不会影响游戏运行。

目录根有一份 `.gdignore`，告诉 Godot 跳过整个 `docs/legacy/`，不要扫描里面的 PNG/JPG 生成 `.import`。

## 子目录

| 目录 | 内容 | 状态 |
| --- | --- | --- |
| `交付文档/` | 12 份 docx：剧情册 V5.27、算法册 V2.1～V2.3、事件场景与人物对照表 V2、核对清单 V2、后端开发方案 V1、美术需求单 V2、给机制/美术负责人的待对齐清单 | **现行口径**（剧情册 V5.27 + 算法册 V2.3） |
| `交付文档/归档_已合并/` | 20+ 份旧版 docx | 文件名已标「旧版勿用」，仅留档 |
| `产品设计/` | 世界观与场景设计 V1.1、美术设计方案 V2.2、0909 游戏机制 V1、小红书岗位研究 | 参考 |
| `离线网页/` | 6 个 standalone html（algo / design / freetime / integration / scene / story） | 可直接双击打开看 |
| `开场三屏参考图/` | 第 1/2 屏的参考版式 PNG、无 UI 版标题背景 | 美术对版用 |
| `events_bak/` | `scoring_cards` 的 v2.2～v2.6 历史版本 | 只做回滚用 |
| `我的占位稿/` | AI 生成的占位图：`title_background.jpg`（月夜小熊镇标题底图） | **不是美术资产**，仅供对照，别搬回 `assets/` |

## 仍在用的数据（已迁到 `data/story/`，不在本目录）

`scoring_cards.json`（v2.7+）、`free_time_system.json`、`monthly_action_nodes.json`、`crisis_dialogue.json`、`task_001_tech_stack.json`
—— 这 5 份是**唯一口径**，已放到 `data/story/`，Python 引擎内核（`backend/engine_core/`）直接读那里。

## 口径提醒

存档里有两份文档**已被废弃，不要照着改代码**：

- 《游戏引擎与数据机制详细设计 V1.9》—— 主册已废（2026-09-11），数据库表清单已收编进算法册 §9。
- 算法册 V2.1 / V2.2 —— 以 V2.3 为准。

## 未迁入的文件

旧目录 `data/0427标准数据5000条做研报实验.xlsx` 与本游戏无关，未搬。
