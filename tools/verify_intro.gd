extends SceneTree
## 开场验收脚本（headless 跑一遍，两屏三页全构建一次）
##
## 用法：
##   Godot_v4.3-stable_win64_console.exe --headless --path <工程目录> --script res://tools/verify_intro.gd
##
## 退出码 0 = 全通过，1 = 有 FAIL。
## 它不渲染、不点击，只验证「数据读得到、节点建得出来、资源真的存在」。
##
## ⚠ 两条踩过的坑，改本文件前必读：
##   1. **不能写 `await process_frame`**。`--script`（SceneTree 模式）下这个信号不会
##      被发出，协程永久停在 await 那一行 → Godot 挂死不退出（实测挂了 20 分钟无输出）。
##   2. **不能靠 `add_child(inst)` 触发 `_ready()`**。在 `_initialize()` 里加进树，
##      `_ready()` 会被推迟到下一帧才跑；而上一条又禁止我们等帧。
##      所以这里手动按 `_ready()` 的顺序驱动一遍（set_anchors → _load_data → _show_title）。
##      `IntroSequence` 的这几个方法都不依赖 SceneTree，手动调用等价。

const SCENE := "res://Intro.tscn"
const DATA_PATH := "res://data/story/intro.json"
const NPCS_PATH := "res://data/town/npcs.json"
const NEXT_SCENE := "res://Main.tscn"
const EXPECT_CAST := 5
const EXPECT_PAGES := 3
const EXPECT_PALETTE := 16

var _pass := 0
var _fails: Array[String] = []
var _warns: Array[String] = []


func _initialize() -> void:
	# _run() 中途若抛错会返回 null —— 那种情况必须算失败，不能默认 0。
	var raw: Variant = _run()
	var code: int = raw if typeof(raw) == TYPE_INT else 1
	if typeof(raw) != TYPE_INT:
		print("  FAIL  验收脚本中途异常终止（见上方 SCRIPT ERROR）")
	print("================================")
	print("通过 %d 项；失败 %d 项；警告 %d 项" % [_pass, _fails.size(), _warns.size()])
	if not _fails.is_empty():
		print("失败清单：")
		for f in _fails:
			print("  - %s" % f)
	if not _warns.is_empty():
		print("警告（不阻断，多为美术图未到位）：")
		for w in _warns:
			print("  - %s" % w)
	print("结果：%s" % ("全部通过" if _fails.is_empty() else "有失败"))
	quit(code)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fails.append(label)
		print("  FAIL  %s" % label)


func _warn(cond: bool, label: String) -> void:
	if not cond:
		_warns.append(label)
		print("  WARN  %s" % label)


func _count_descendants(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		total += 1 + _count_descendants(c)
	return total


## 数一数挂了某个脚本的节点有多少个（装饰件 IntroDeco 用；脚本没有 class_name，
## 只能按脚本路径后缀认）
func _count_kind(n: Node, script_name: String) -> int:
	var total := 0
	for c in n.get_children():
		var s: Variant = c.get_script()
		if s != null and str(s.resource_path).ends_with("/%s.gd" % script_name):
			total += 1
		total += _count_kind(c, script_name)
	return total


func _run() -> int:
	print("=========== 开场验收 ===========")

	# ---------- 1. 数据文件 ----------
	print("[1] 数据文件（三个关键文件必须都在）")
	_ok(FileAccess.file_exists(DATA_PATH), "存在 %s" % DATA_PATH)
	_ok(FileAccess.file_exists(NPCS_PATH), "存在 %s（人物单一来源）" % NPCS_PATH)
	_ok(ResourceLoader.exists(NEXT_SCENE), "存在 %s（开场结束的去处）" % NEXT_SCENE)

	# ---------- 2. 场景加载 ----------
	print("[2] 场景加载")
	var packed: PackedScene = load(SCENE)
	_ok(packed != null, "Intro.tscn 能加载")
	if packed == null:
		return 1
	var inst: Control = packed.instantiate()
	_ok(inst != null, "Intro.tscn 能实例化")
	if inst == null:
		return 1

	# 手动驱动一遍 _ready()（见文件头 ⚠ 第 2 条）
	inst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inst._load_data()
	var parsed_d: Dictionary = inst.get("_d")
	_ok(not parsed_d.is_empty(), "intro.json 解析成功")
	inst._show_title()

	# ---------- 3. 脚本内部状态 ----------
	print("[3] 脚本内部状态")
	var d: Dictionary = inst.get("_d")
	var cast: Array = inst.get("_cast")
	var pal: Dictionary = inst.get("_pal")
	var font_obj: Variant = inst.get("_font")

	_ok(not d.is_empty(), "intro.json 读进来了（_d 非空）")
	_ok(cast.size() == EXPECT_CAST, "人物名单 %d 位（实际 %d）" % [EXPECT_CAST, cast.size()])
	_ok(pal.size() == EXPECT_PALETTE, "色板 %d 色（实际 %d）" % [EXPECT_PALETTE, pal.size()])
	_ok(font_obj != null, "字体已加载（res://assets/fonts/NotoSansCJKsc-Regular.otf）")

	# 色板有没有解析失败的（Color.html 遇到非法值返回 MAGENTA）
	var bad_colors: Array[String] = []
	for k in pal.keys():
		var c: Color = pal[k]
		if c.is_equal_approx(Color.MAGENTA):
			bad_colors.append(str(k))
	_ok(pal.size() > 0 and bad_colors.is_empty(), "色板全部解析成合法颜色（异常键：%s）" % [bad_colors])

	# 人物字段完整度（缺字段会渲染成空标签，不报错但页面会空一块）
	var missing: Array[String] = []
	for who in cast:
		for f in ["name", "role", "place", "line", "loadout"]:
			if str(who.get(f, "")) == "":
				missing.append("%s.%s" % [who.get("id", "?"), f])
	_ok(cast.size() == EXPECT_CAST and missing.is_empty(),
		"人物字段齐全（缺：%s）" % [missing])

	# 头像图集真的存在
	var pd: Dictionary = d.get("paperDoll", {})
	var pat := str(pd.get("atlasPattern", ""))
	var miss_art: Array[String] = []
	for who in cast:
		var p := pat.replace("{loadout}", str(who.get("loadout", "")))
		if not ResourceLoader.exists(p):
			miss_art.append("%s -> %s" % [who.get("name", "?"), p])
	_ok(cast.size() == EXPECT_CAST and miss_art.is_empty(),
		"五张头像图集都存在（缺：%s）" % [miss_art])
	_ok((pd.get("portraitRegion", []) as Array).size() == 4, "portraitRegion 是 4 个数的矩形")

	# ---------- 4. 标题屏 ----------
	print("[4] 标题屏")
	var stage: Variant = inst.get("_stage")
	var ok_stage: bool = stage != null and is_instance_valid(stage)
	_ok(ok_stage, "标题屏容器已创建")
	if ok_stage:
		_ok(_count_descendants(stage) > 0, "标题屏建出了节点（%d 个）" % _count_descendants(stage))
	var ts: Dictionary = d.get("titleScreen", {})
	_ok(not str(ts.get("title", "")).is_empty(), "标题文案：%s" % ts.get("title", ""))
	var menu: Array = ts.get("menu", [])
	_ok(menu.size() >= 6, "菜单项 %d 个（至少 6：3 主 + 2 次级 + 退出）" % menu.size())
	var has_exit := false
	for item in menu:
		if str(item.get("id", "")) == "exit":
			has_exit = true
	_ok(has_exit, "菜单里有「退出游戏」（绿色 exit 变体）")
	# 标题底图是**必需**的：缺了整屏退成纯色底，就是参考图对不上的主因
	var bg := str(ts.get("background", ""))
	_ok(bg != "" and ResourceLoader.exists(bg), "标题底图已就位：%s" % bg)
	# 装饰件（瓦顶 / 宝石）是节点画出来的，数量对不上说明版式退了
	_ok(_count_kind(stage, "IntroDeco") >= 2,
		"标题屏装饰件（瓦顶 + 宝石）已建出（%d 个）" % _count_kind(stage, "IntroDeco"))

	# ---------- 5. 开场屏三页 ----------
	print("[5] 开场屏三页")
	var pages: Array = (d.get("introScreen", {}) as Dictionary).get("pages", [])
	_ok(pages.size() == EXPECT_PAGES, "共 %d 页（实际 %d）" % [EXPECT_PAGES, pages.size()])
	for i in pages.size():
		var page: Dictionary = pages[i]
		inst._goto_intro(i)
		var st: Variant = inst.get("_stage")
		var built: bool = st != null and is_instance_valid(st) and _count_descendants(st) > 0
		_ok(built, "第 %d 页「%s」构建成功（%d 个节点）"
			% [i + 1, page.get("tab", "?"), _count_descendants(st) if built else 0])
		if not built:
			continue
		# 外壳：木框 + 钟楼 + 三处藤叶（参考图第 2 屏的关键件）
		_ok(_count_kind(st, "IntroDeco") == 4,
			"第 %d 页有钟楼 + 3 处藤叶（实际 %d 个装饰件）" % [i + 1, _count_kind(st, "IntroDeco")])
		# 递归找 Parchment（它不是 _stage 的直接子节点，见 IntroSequence 里的注释）
		var parchment: Node = st.find_child("Parchment", true, false)
		_ok(parchment != null, "第 %d 页有羊皮纸容器 Parchment" % (i + 1))
		if parchment == null or parchment.get_child_count() == 0:
			continue
		var col_node: Node = parchment.get_child(0)
		# 内容列 5 段：顶栏 / 页签 / 主体 / 页码 / 页脚
		_ok(col_node.get_child_count() == 5,
			"第 %d 页结构完整：顶栏 + 页签 + 主体 + 页码 + 页脚（实际 %d 个）"
			% [i + 1, col_node.get_child_count()])
		if bool(page.get("cast", false)) and col_node.get_child_count() >= 3:
			var body_rows: Node = col_node.get_child(2)     # 主体外面包了一层 margin 容器
			var body: Node = body_rows.get_child(0) if body_rows.get_child_count() > 0 else null
			_ok(body != null and body.get_child_count() == cast.size(),
				"人物名单页卡片数 == 名单人数（%d vs %d）"
				% [body.get_child_count() if body != null else -1, cast.size()])
		# 该页的插图配置（有就检查文件在不在）
		var art: Dictionary = page.get("art", {})
		if art.has("image"):
			_warn(ResourceLoader.exists(str(art["image"])), "第 %d 页插图未就位：%s" % [i + 1, art["image"]])

	print("=========== 验收结束 ===========")
	return 0 if _fails.is_empty() else 1
