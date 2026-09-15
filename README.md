# 职场小镇

这是一个以剧情选择和自由活动完成职业测评的 2D 像素风小镇原型。当前以 Godot 验证地图、触控、NPC 和剧情体验；后端独立负责会话、存档、评分与报告。鸿蒙工程仅作为 Godot Web 导出包的运行外壳，不承载游戏规则。

## 协作入口

- 产品剧情与美术需求：`docs/职场小镇开发文档V1.docx`
- 前后端边界、接口和 Git 规范：`docs/前后端协作架构与开发规范.md`
- 可执行接口契约：`contracts/openapi.yaml`
- 前端本地联调样例：`contracts/fixtures/`

先以 `contracts/openapi.yaml` 为准讨论和修改接口。前端与后端不得只在聊天记录中约定字段。

## 目录

```text
assets/                 地图、角色和其他可提交的美术资源
data/                   小镇区域、碰撞、导航及后续剧情配置
scripts/                Godot 前端交互代码
contracts/              前后端共用的 OpenAPI 契约和 Mock 数据
backend/                后端服务目录，由后端同学实现
backend/engine_core/    Python 引擎内核（M0+M1，2026-09-13 迁入），读 data/story/
entry/                  ArkTS 鸿蒙外壳，不写游戏评分逻辑
docs/                   开发依据和协作规范
docs/legacy/            旧工程归档（交付文档/离线网页/参考图/数据历史版本），只读，Godot 已 .gdignore
tools/                  可重复执行的资源处理工具
web/                    Web 版开场原型（React + Vite），设计验证用，不是游戏本体
```

## 本地运行

在 Godot 4.3+ 中导入本目录，打开 `project.godot`，按 F6/F5 运行。

操作：WASD 或方向键移动；手机/模拟器用左下角摇杆；靠近 NPC 后按 E、空格或点击交互按钮。

### Godot 开场（`Intro.tscn`，2026-09-14 已对齐参考图）

开场两屏（标题主菜单 → 认识小熊镇三页）是**可交互**的：菜单按钮 / 页签 / 上一页 / 跳过 / 进入小镇都能点，
版式、色板、文案全部来自 `data/story/intro.json`；瓦顶、宝石、钟楼、藤叶这些装饰件是
`scripts/ui/IntroDeco.gd` 用代码画的矢量（不用图片素材），坐标 = web 的 CSS 设计值 ×1.2。
标题底图与两张插图目前是**临时占位**（见 `assets/ui/intro/README.md`），美术交付后同名覆盖即可。

```bash
# 结构验收（headless，改完 intro.json / 场景必跑）
Godot --headless --path <工程> --script res://tools/verify_intro.gd
# 截图自检（真渲染，四屏各存一张 PNG，肉眼对照 docs/legacy/开场三屏参考图/）
Godot --path <工程> --resolution 1920x1080 res://tools/shot_intro.tscn -- --shots title,0,1,2 --shot-dir <输出目录>
```

## Web 版开场原型（`web/`）

`web/` 是一份独立的 React + Vite 工程，**只用来验证开场三屏的版式、文案与美术方向**，
不是游戏本体——游戏本体是 Godot。它与 Godot 运行时互不影响：

- 目录内放了一份空的 `.gdignore`，告诉 Godot **跳过整个 `web/`**，不要把里面的图片当资源导入；
- `web/.gitignore` 已忽略 `node_modules` 与 `dist`。

```bash
cd web
npm install
npm run dev        # http://localhost:5173
```

深链可直接定位屏幕与页码，例如 `/?screen=town&page=2`、`/?screen=title`。

开场三屏的版式约定、文案口径与踩过的坑都写在 `web/README.md`。
它的底图裁自本工程的 `assets/town/workplace_town_reference.png`，属同一份美术来源。

## 地图数据

运行时读取 `data/town/regions.json`、`data/town/npcs.json`、`data/town/collision.json` 与 `data/town/navigation.json`。`scripts/WorkplaceTown.gd` 负责将其转换为区域触发器、碰撞多边形、可行走区域和 NPC。

区域对应：A 熊起东方总部、B 云栖科技丘、C 创意水巷、D 树影书院、E 松风训练谷、F 观澜会展码头、G 暖邻康护院、H 慢生活园。

底图：`assets/town/workplace_town_reference.png`。

## 自己绘制碰撞

在 Godot 中打开 `tools/CollisionEditor.tscn`，按 F6 运行。左键逐点勾轮廓，右键撤销最后一个点；选中已有轮廓后可重画或删除。点击“保存到 collision.json”后，运行主场景并按 F3 即可检查红色轮廓。

## NPC 演员表

`data/town/npcs.json` 是**演员表的唯一来源：开场三屏和地图内 NPC 都读它**（`IntroSequence.gd` 与 `WorkplaceTown.gd` 各读一次）。改演员只改这个 JSON，不要改脚本——两份脚本里的同名数组都只是读不到 JSON 时的兜底。

当前五人（E 松风训练谷 / F 观澜会展码头 / G 暖邻康护院 暂无 NPC）：

| 区 | 姓名 | 职衔 | 关系系统 |
| --- | --- | --- | --- |
| A 熊起东方总部 | 陈工 | 邻组 Leader | **否**——事务型直属上级，无好感度、无熊友卡、不参与邀约 |
| B 云栖科技丘 | 王哥 | 技术 · 你的导师 | 是 |
| C 创意水巷 | 小林 | 产品 | 是 |
| D 树影书院 | 老周 | 资深 | 是 |
| H 慢生活园 | 小赵 | 实习生 | 是 |

### 两条已定的口径（2026-09-13）

1. **角色是「熊」**。现在 `loadout` 填的是 kun913 现成的人类纸娃娃（`elder_man` / `skirt_woman` / `suit_man` / `neutral_hoodie` / `energetic_ponytail` / `street_creator`），**只是临时占位**；等美术出熊的纸娃娃图集后整体替换，字段名不变。
2. **只用这 5 只熊**。原先 `WorkplaceTown.gd` 里的 8 个区域 NPC（艾米 / 陈工 / 林总 / 周岚 / 小莫 / 阿哲 / 宁宁 / 乐乐）已作废删除。

## 剧情数据与引擎内核（2026-09-13 迁入）

`data/story/` 除了开场用的 `intro.json`，现在还有 5 份**唯一口径**的剧情/算法数据：

```text
data/story/scoring_cards.json         打分卡（39 主线事件 + 5 成就 = 123 选项）
data/story/free_time_system.json      自由活动配置（19 活动 / 16 次机会 / 好感度）
data/story/monthly_action_nodes.json  月度精力分配模板（4 模板 × 4 选项）
data/story/crisis_dialogue.json       危机对话
data/story/task_001_tech_stack.json   技术栈模板
```

`backend/engine_core/` 是从旧工程搬来的 Python 引擎内核（FastAPI M0+M1，纯标准库、零第三方依赖）。
它**不复制数据副本**，直接读上面的 `data/story/`（查找顺序：环境变量 `XZZ_DATA_DIR` → `<kun913>/data/story/` → 旧位置兜底）。

```bash
cd backend/engine_core
python scripts/validate_config.py            # 构建期校验，改完 JSON 必跑
python scripts/simulate.py --policy index    # 跑批（index / utility / random）
```

校验器仍会报 12 条 `[注意]`，都是策划待确认项（雷达满分口径 40/37/35/34/30/8 vs 文档记载、调节焦点 5 个选项未标等），**不影响通过**。

历史交付文档、离线网页、开场三屏参考图与数据历史版本都归档在 `docs/legacy/`，清单见 `docs/legacy/README.md`。
