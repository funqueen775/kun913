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
entry/                  ArkTS 鸿蒙外壳，不写游戏评分逻辑
docs/                   开发依据和协作规范
tools/                  可重复执行的资源处理工具
```

## 本地运行

在 Godot 4.3+ 中导入本目录，打开 `project.godot`，按 F6/F5 运行。

操作：WASD 或方向键移动；手机/模拟器用左下角摇杆；靠近 NPC 后按 E、空格或点击交互按钮。

## 地图数据

运行时读取 `data/town/regions.json`、`data/town/collision.json` 与 `data/town/navigation.json`。`scripts/WorkplaceTown.gd` 负责将其转换为区域触发器、碰撞多边形和可行走区域。

区域对应：A 熊起东方总部、B 云栖科技丘、C 创意水巷、D 树影书院、E 松风训练谷、F 观澜会展码头、G 暖邻康护院、H 慢生活园。

底图：`assets/town/workplace_town_reference.png`。

## 自己绘制碰撞

在 Godot 中打开 `tools/CollisionEditor.tscn`，按 F6 运行。左键逐点勾轮廓，右键撤销最后一个点；选中已有轮廓后可重画或删除。点击“保存到 collision.json”后，运行主场景并按 F3 即可检查红色轮廓。
