extends Control

# 移植队友 web/ 的流程与素材：标题菜单 -> 三页小镇导览 -> Main.tscn。
#
# 【2026-09-15 左侧重构】标题页左列原来是用三块纯色 Panel 拼的（深木底横幅 + 木色菜单板 +
# 一个 ◆ 字符当宝石），字一律 18~21px —— 在 1280x720 的窗口里被缩到 0.67 倍，看着又脏又小。
# 现在改成：**直接用美术交付的空壳图 assets/ui/startup/startup_menu_shell.png 当底板**
# （832x732 的木框 + 羊皮纸 + 牌顶小屋顶和宝石，之前一直没被任何脚本引用），
# 文字与按钮叠在羊皮纸上，字号整体上调一档。牌顶的屋顶靠「宽度与原图一致、只拉伸高度」保住不变形。
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const TITLE_BG := preload("res://assets/ui/intro/title_bg.png")
const TOWN_ART := preload("res://assets/ui/intro/town_1.png")
const LIFE_ART := preload("res://assets/ui/intro/town_3.png")
const PLAQUE_SHELL := preload("res://assets/ui/startup/startup_menu_shell.png")
const PROFILE_PATH := "user://workplace_town_profile.json"
# Batch 3（2026-09-17）：「我的报告」接通 —— 面板按需实例化，报告只在服务端算。
const REPORT_PANEL := preload("res://scripts/ReportPanel.gd")

const PAPER := Color("f6e6bd")
const INK := Color("4a2b1a")
const WOOD := Color("5b321f")
const BRICK := Color("b95035")
const BRICK_HOVER := Color("cf6247")
const BRICK_PRESSED := Color("8f3a26")
const EDGE := Color("2e1a12")
const CREAM_TXT := Color("fff4d5")
const SUB_TXT := Color("8a4a2e")
const CHIP_BG := Color("f0d9a8")
const CHIP_BG_HOVER := Color("ffeec4")
const SECOND_BG := Color("f1ddb0")
const SECOND_BG_HOVER := Color("fff0cc")
const SECOND_EDGE := Color("9a6a42")
const EXIT_BG := Color("70452c")
const EXIT_BG_HOVER := Color("88593a")
const EXIT_TXT := Color("f3dfbe")

## 左侧木牌：位置 / 尺寸 / 九宫格四角保护区（按原图 832x732 量出的木框厚度）
const PLAQUE_POS := Vector2(96, 132)
const PLAQUE_W := 832.0
const PLAQUE_H := 790.0
const CUT_LEFT := 66
const CUT_RIGHT := 66
const CUT_TOP := 120
const CUT_BOTTOM := 50
## 牌内内容列：宽 576、水平居中（两侧各留 128），从牌顶往下 130 起（避开横梁）
const CONTENT_W := 576.0
const CONTENT_TOP := 130.0

## 导览三页共用的内容区（相对 frame）：切页不跳版靠它
## 高度从 460 提到 540 —— 原来页面底部空着 128px，正文因此一直写不长。
const CONTENT_RECT := Rect2(94, 252, 1512, 540)

## 导览三页文案 —— 口径来源：《剧情设计详细方案 V5.27》一/二/三章 + 十一（自由活动）
## 「八组团」「三条空间线」「48 个月」「24 主线（六幕）/ 19 自由活动」都是文档里的硬数据，不是形容词。
## 2026-09-16 口径修正：事件基准 = 24 件六幕（一局跑完 48 个月，不分局），原「39 件」「五个阶段」作废。
const PAGES := [
	{"tab":"小镇介绍", "kicker":"欢迎来到这里", "title":"从第一天入职开始",
	 "body":"小熊镇以一湖、两环、八组团铺开：湖心办庆典、冲突与结局，东岸智研线走技术与决策，西岸成长生活线走关系、恢复与夜间支线。\n\n八个组团各有各的作息——熊起东方总部管入职与重大决策，云栖科技丘做技术协作，创意水巷对接客户，树影书院负责培训复盘，松风训练谷做团建与信任测试，观澜会展码头办路演，暖邻康护院管员工关怀，慢生活园留给休息和桌游。你会在这些地方经历路演、协作、培训与关怀，也会慢慢认识每天和你一起上班的人。",
	 "facts":[["8", "个组团"], ["3", "条空间线"], ["4", "位常驻同事"]], "art":TOWN_ART},
	{"tab":"人物名单", "kicker":"你会遇到的人", "title":"同事各有各的工作",
	 "body":"他们不是围着玩家转的角色——每人有自己的区域与节奏；靠近、交流、一起解决问题，才会慢慢建立联系。陈工是事务型上级，不进关系系统。",
	 "cast":true},
	{"tab":"开始旅程", "kicker":"怎么走完这一程", "title":"选择会留下记录",
	 "body":"整条旅程横跨 48 个月，职级从 L1 走到 L7：每 6 个月有一次晋升考核窗，不升职，项目就会被别人推进。\n\n主线跟着一个客服 Agent 走完六幕——进入行业、真实需求与成本压力、事故与责任、重构与传承、边界与答辩、传承与新局，24 个事件全部必遇；另有 19 项自由活动（独处、双人、团建与工作型）由你自己安排。你的选择、停留与交流会被服务端记录，最终汇成一份只属于你的成长报告。",
	 "facts":[["48", "个月的旅程"], ["24", "个主线事件"], ["19", "项自由活动"]], "art":LIFE_ART},
]

## 演员表唯一来源 data/town/npcs.json（V5.27 口径）。旧 8 区 NPC（艾米/林总/周岚/宁宁…）
## 已于 2026-09-13 作废，别再往回填。每行 = 姓名 / 身份 / 常驻区域 / 头像色 / 一句话性格。
const CAST := [
	["王哥", "技术 · 你的导师", "B 区 · 云栖科技丘", "7198b6", "爱泼冷水，但认可扎实的调研。"],
	["陈工", "邻组 Leader", "A 区 · 熊起东方总部", "5f6b7a", "话少，只问结论和成本。"],
	["小林", "产品", "C 区 · 创意水巷", "bc825e", "被客户催着走，先塞需求再一起想办法。"],
	["老周", "资深", "D 区 · 树影书院", "8a786b", "在听，等着看谁认领。"],
]

## 标题页菜单：三个主按钮的文案（从上到下）。各自接什么行为见 _title_screen() 内的 match。
## 【2026-09-18 诚实化】原来三项的「是否可进入」全是 true 且全接 _start_intro，
## 「继续 / 加载」点下去和新游戏一模一样。现在行为按有没有存档区分，见主按钮循环。
const MAIN_MENU := ["继续游戏", "开始新游戏", "加载游戏"]
const SUB_MENU := [
	["我的报告", true],
	["游戏设置", false],
]

var _mode := "title"
var _page := 0
var _fonts: Dictionary = {}
var _report_panel: CanvasLayer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rebuild()

func _rebuild() -> void:
	for child in get_children(): child.queue_free()
	_background()
	if _mode == "title":
		_title_screen()
	elif _mode == "avatar":
		_avatar_screen()
	else:
		_intro_screen()

func _background() -> void:
	var bg := TextureRect.new()
	bg.texture = TITLE_BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.09, 0.12, 0.34 if _mode == "title" else 0.60)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

# ------------------------------------------------------------------ 标题屏

func _title_screen() -> void:
	_topbar()
	# 一块整牌：标题 + 副标题 + 菜单全在同一张木框里，不再是「两块板子叠着」。
	# ⚠ 宽度必须等于原图宽度（832）：九宫格的左右保护区都是 66，中间区缩放比正好 1，
	#   骑在牌顶的屋顶/宝石才不会横向被压扁；高度拉到 PLAQUE_H 只是把中间那截纯色羊皮纸拉长。
	var plaque := NinePatchRect.new()
	plaque.texture = PLAQUE_SHELL
	plaque.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plaque.patch_margin_left = CUT_LEFT
	plaque.patch_margin_right = CUT_RIGHT
	plaque.patch_margin_top = CUT_TOP
	plaque.patch_margin_bottom = CUT_BOTTOM
	plaque.position = PLAQUE_POS
	plaque.size = Vector2(PLAQUE_W, PLAQUE_H)
	add_child(plaque)

	var column := VBoxContainer.new()
	column.position = Vector2(PLAQUE_POS.x + (PLAQUE_W - CONTENT_W) * 0.5, PLAQUE_POS.y + CONTENT_TOP)
	column.custom_minimum_size.x = CONTENT_W
	column.size = Vector2(CONTENT_W, 0)
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var title := _label("职 场 小 镇", 62, INK, 3.0, 0.30)
	title.custom_minimum_size.y = 90
	column.add_child(title)
	column.add_child(_spacer(2))
	var sub := _label("从第一天入职开始", 26, SUB_TXT, 0.0, 0.16)
	sub.custom_minimum_size.y = 38
	column.add_child(sub)
	column.add_child(_spacer(16))
	column.add_child(_divider())
	column.add_child(_spacer(26))

	# 三个主按钮：等宽竖排。
	# 【2026-09-18 诚实化】行为按钮位区分，不再三个全接 _start_intro：
	#   继续游戏   → 有存档（profile 文件在）才亮：跳过导览直接进小镇；没存档置灰。
	#   开始新游戏 → 恒亮：走导览三页再进小镇。
	#   加载游戏   → 恒灰：还没有读档系统（多存档位），tooltip 说明。
	# ⚠ 置灰按钮不连 pressed —— disabled 状态下 Godot 本来就不派发点击，连了也没用。
	var has_save := FileAccess.file_exists(PROFILE_PATH)
	for i in MAIN_MENU.size():
		var main_btn := _button(String(MAIN_MENU[i]), "primary")
		match i:
			0:
				main_btn.disabled = not has_save
				if has_save:
					main_btn.pressed.connect(_continue_game)
				else:
					main_btn.tooltip_text = "还没有存档，先开始一局新游戏"
			1:
				main_btn.pressed.connect(_start_intro)
			2:
				main_btn.disabled = true
				main_btn.tooltip_text = "读档暂未开放"
		if i > 0:
			column.add_child(_spacer(16))
		column.add_child(main_btn)
	column.add_child(_spacer(20))

	# 两个次级按钮：并排一行。第一个 = 我的报告（Batch 3 接通）。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for i in SUB_MENU.size():
		var sub_item: Array = SUB_MENU[i]
		var sub_btn := _button(sub_item[0], "secondary")
		sub_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_btn.pressed.connect(_open_report if i == 0 else _placeholder)
		row.add_child(sub_btn)
	column.add_child(row)

	# 退出：单独一行，木色，和上面两组拉开
	column.add_child(_spacer(12))
	var exit_btn := _button("退出游戏", "exit")
	exit_btn.pressed.connect(_quit_game)
	column.add_child(exit_btn)

func _topbar() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.add_theme_constant_override("separation", 12)
	top.position = Vector2(-468, 34)
	top.size = Vector2(426, 56)
	add_child(top)
	for text in ["我的报告", "游戏设置", "帮助"]:
		var chip := _button(text, "chip")
		chip.custom_minimum_size = Vector2(134, 56)
		chip.pressed.connect(_open_report if text == "我的报告" else _placeholder)
		top.add_child(chip)


## 打开「我的报告」面板（按需实例化，ReportPanel 自己管拉取与失败文案）。
func _open_report() -> void:
	if _report_panel == null:
		_report_panel = REPORT_PANEL.new()
		add_child(_report_panel)
	_report_panel.open()

# ------------------------------------------------------------------ 导览三页
# 【2026-09-15 排版重排】三个坑一起修掉，动这块之前先读完：
#  1. **属性顺序**：`Label.size` 必须写在 `autowrap_mode` **之后**；`TextureRect.size` 必须写在
#     `expand_mode` **之后**。反了的话，设 size 那一刻的最小尺寸还是"整行宽度 / 纹理原始尺寸"，
#     size 会被顶大、之后再也不会重算 —— 正文 620 实测变 838（压住右侧插图 104px）、插图 636×454
#     实测变 660×495（溢出木框），两个 bug 都是这个顺序错。
#  2. **正文不许写死高度**：Label 高度按行数自适应（行高 ≈ 1.5×字号）。写死 245 再垂直居中，
#     两行字就悬在框正中、上下各空一大块 —— 这就是"留白太多"的主因。
#  3. **`_label()` 默认垂直居中，只适合单行标题**，段落必须自己改回 TOP。

func _intro_screen() -> void:
	var frame := Panel.new()
	frame.position = Vector2(110, 56)
	frame.size = Vector2(1700, 968)
	frame.add_theme_stylebox_override("panel", _style(PAPER, WOOD, 8, 8))
	add_child(frame)

	# 顶栏：返回 / 标题 / 副标题
	var back := _button("返回", "secondary")
	back.position = Vector2(36, 34)
	back.size = Vector2(132, 60)
	back.pressed.connect(_back)
	frame.add_child(back)

	var heading := _label("认识职场小镇", 34, INK)
	heading.position = Vector2(300, 34)
	heading.size = Vector2(1100, 51)
	frame.add_child(heading)

	var sub := _label("先了解这里怎么过，再决定怎么开始", 18, Color("7a5533"))
	sub.position = Vector2(300, 90)
	sub.size = Vector2(1100, 27)
	frame.add_child(sub)

	# 页签：三页居中排一行（原来靠左，和居中的标题不搭）
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(140, 152)
	tabs.size = Vector2(1400, 64)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	frame.add_child(tabs)
	for index in PAGES.size():
		var tab := _button(String(PAGES[index]["tab"]), "tab_on" if index == _page else "tab")
		tab.custom_minimum_size = Vector2(210, 64)
		tab.pressed.connect(func(): _go_page(index))
		tabs.add_child(tab)

	var page: Dictionary = PAGES[_page]
	if page.get("cast", false): _cast_content(frame, page)
	else: _text_content(frame, page)
	_footer(frame)

func _text_content(frame: Panel, page: Dictionary) -> void:
	var card := Panel.new()
	card.position = CONTENT_RECT.position
	card.size = CONTENT_RECT.size
	card.add_theme_stylebox_override("panel", _style(Color("fff5db", 0.78), Color("c69458"), 2, 6))
	frame.add_child(card)

	# 右边插图：540×405 木框，垂直居中于加高后的卡片
	var art_box := Panel.new()
	art_box.position = Vector2(CONTENT_RECT.size.x - 24.0 - 540.0, (CONTENT_RECT.size.y - 405.0) * 0.5)
	art_box.size = Vector2(540.0, 405.0)
	art_box.add_theme_stylebox_override("panel", _style(WOOD, Color("3a2115"), 5, 5))
	card.add_child(art_box)
	if page.has("art"):
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE            # ⚠ 先设 expand_mode
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.texture = page["art"] as Texture2D
		art.position = Vector2(12, 12)
		art.size = art_box.size - Vector2(24, 24)                   # ⚠ 再设 size
		art_box.add_child(art)

	# 左栏：眉题 / 标题 / 关键数字 / 正文，四层竖排
	var kicker := _label(str(page["kicker"]), 22, BRICK)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	kicker.position = Vector2(56, 76)
	kicker.size = Vector2(860, 32)
	card.add_child(kicker)

	var title := _label(str(page["title"]), 42, INK, 0.0, 0.30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector2(56, 112)
	title.size = Vector2(860, 62)
	card.add_child(title)

	var facts := _facts_row(card, page.get("facts", []), Vector2(56, 188), 860.0)

	var body := _label(str(page["body"]), 22, Color("634330"))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART             # ⚠ 先开 autowrap
	body.position = Vector2(56, 272)
	body.size = Vector2(860, 0)                                     # ⚠ 再给宽度，高度交给它自己算
	card.add_child(body)

	# 整块左栏在卡片里做垂直居中：三页正文长短不一，靠这个让视觉重心统一在卡片中线上
	# （右栏插图本来就是居中的），否则短的那页底下会空一大块。
	# 块「内」仍保持自上而下排列，动的只是整块的位置。
	var top := 76.0
	var used := body.position.y + body.size.y - top
	var shift := maxf((CONTENT_RECT.size.y - used) * 0.5 - top, 40.0 - top)
	for node in [kicker, title, facts, body]:
		if node != null:
			(node as Control).position.y += shift

## 关键数字条：正文上方一排小牌，先把「多少个月 / 多少个事件」这类硬信息摆出来，
## 顺便把标题和正文之间那段空档填掉。返回这一排本身，好让调用方参与整块的居中。
func _facts_row(parent: Control, facts: Array, at: Vector2, total_w: float) -> Control:
	if facts.is_empty():
		return null
	var row := HBoxContainer.new()
	row.position = at
	row.size = Vector2(total_w, 62)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var plate_w := (total_w - 14.0 * float(facts.size() - 1)) / float(facts.size())
	for item in facts:
		var plate := Panel.new()
		plate.custom_minimum_size = Vector2(plate_w, 62)
		plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plate.add_theme_stylebox_override("panel", _style(Color("f7e3b4"), Color("c69458"), 2, 5))
		row.add_child(plate)

		var number := _label(str(item[0]), 28, BRICK, 0.0, 0.30)
		number.position = Vector2(0, 4)
		number.size = Vector2(plate_w, 34)
		plate.add_child(number)

		var caption := _label(str(item[1]), 15, Color("7a5533"))
		caption.position = Vector2(0, 36)
		caption.size = Vector2(plate_w, 22)
		plate.add_child(caption)
	return row

func _cast_content(frame: Panel, page: Dictionary) -> void:
	# 和另两页共用同一张内层卡与同一套「眉题 / 标题 / 导语」节奏，
	# 三页切来切去不会跳版（原来这页直接在羊皮纸上摆标题，是唯一的例外）。
	var card := Panel.new()
	card.position = CONTENT_RECT.position
	card.size = CONTENT_RECT.size
	card.add_theme_stylebox_override("panel", _style(Color("fff5db", 0.78), Color("c69458"), 2, 6))
	frame.add_child(card)

	var kicker := _label(str(page["kicker"]), 22, BRICK)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	kicker.position = Vector2(56, 58)
	kicker.size = Vector2(860, 30)
	card.add_child(kicker)

	var title := _label(str(page["title"]), 42, INK, 0.0, 0.30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector2(56, 94)
	title.size = Vector2(1200, 58)
	card.add_child(title)

	# 导语放在标题下方、卡片行上方：居中的长句排在卡片底下会把整页压到底边。
	# 压成一行（fs16 × 1400 宽约放得下 87 字），省下的高度全部让给卡片行。
	var note := _label(str(page.get("body", "")), 16, Color("7a5533"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.position = Vector2(56, 166)
	note.size = Vector2(CONTENT_RECT.size.x - 112.0, 0)
	card.add_child(note)

	# 卡片行左右各内缩 24 —— 铺满整宽时第一张的左框会跟内层卡的边框叠在一起，看着像画歪了。
	# 宽度按内缩后的可用宽均分算死：只给 EXPAND_FILL 的话最后一张会多摊一点，五张不等宽。
	var card_w := (CONTENT_RECT.size.x - 48.0 - 16.0 * float(CAST.size() - 1)) / float(CAST.size())
	var cards := HBoxContainer.new()
	cards.position = Vector2(24, 216)
	cards.size = Vector2(CONTENT_RECT.size.x - 48.0, 294)
	cards.add_theme_constant_override("separation", 16)
	card.add_child(cards)
	for person in CAST:
		var person_card := Panel.new()
		person_card.custom_minimum_size = Vector2(card_w, 294)
		person_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		person_card.add_theme_stylebox_override("panel", _style(Color("fff4d8"), Color("865139"), 3, 5))
		cards.add_child(person_card)

		# 头像圆牌：里面塞首字（Label 默认居中，正好）
		var portrait := Panel.new()
		portrait.position = Vector2((card_w - 88.0) * 0.5, 20)
		portrait.size = Vector2(88, 88)
		portrait.add_theme_stylebox_override("panel", _style(Color(str(person[3])), WOOD, 4, 44))
		person_card.add_child(portrait)
		var initial := _label(String(person[0]).left(1), 40, PAPER)
		initial.position = Vector2(12, 0)
		initial.size = Vector2(64, 88)
		portrait.add_child(initial)

		var name := _label(String(person[0]), 25, INK, 0.0, 0.20)
		name.position = Vector2(0, 118)
		name.size = Vector2(card_w, 37)
		person_card.add_child(name)

		var role := _label(String(person[1]), 16, BRICK)
		role.position = Vector2(0, 158)
		role.size = Vector2(card_w, 24)
		person_card.add_child(role)

		var place := _label(String(person[2]), 14, Color("7a5533"))
		place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART        # ⚠ 先开 autowrap
		place.position = Vector2(14, 188)
		place.size = Vector2(card_w - 28.0, 0)                      # ⚠ 再给宽度
		person_card.add_child(place)

		# 细横线，把「身份信息」和「性格一句话」分开，卡片下部不再空着
		var rule := _divider()
		rule.position = Vector2(22, 236)
		rule.size = Vector2(card_w - 44.0, 3)
		person_card.add_child(rule)

		var line := _label(String(person[4]), 13, Color("8a6a4e"))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.position = Vector2(14, 252)
		line.size = Vector2(card_w - 28.0, 0)
		person_card.add_child(line)

func _footer(frame: Panel) -> void:
	var counter := _plate(_label("第 %d / %d 页" % [_page + 1, PAGES.size()], 18, Color("7a5533")), 180, 60)
	counter.position = Vector2(102, 828)
	frame.add_child(counter)

	var hint := _label("先认识小镇，再开始上班", 18, Color("7a5533"))
	hint.position = Vector2(510, 828)
	hint.size = Vector2(550, 60)
	frame.add_child(hint)

	var previous := _button("上一页", "secondary")
	previous.position = Vector2(1170, 828)
	previous.size = Vector2(135, 60)
	previous.disabled = _page == 0
	previous.pressed.connect(func(): _go_page(_page - 1))
	frame.add_child(previous)

	var skip := _button("跳过", "secondary")
	skip.position = Vector2(1315, 828)
	skip.size = Vector2(120, 60)
	skip.pressed.connect(_start_avatar_selection)
	frame.add_child(skip)

	var next := _button("选择形象" if _page == PAGES.size() - 1 else "继续")
	next.position = Vector2(1445, 828)
	next.size = Vector2(200, 60)
	next.pressed.connect(_start_avatar_selection if _page == PAGES.size() - 1 else func(): _go_page(_page + 1))
	frame.add_child(next)

func _start_intro() -> void: _mode = "intro"; _page = 0; _rebuild()

## 继续游戏：跳过导览直接进小镇，不重写 profile（保留上次开局留下的文件）。
## ⚠ 当前存档粒度只有「玩过没有」——真正的进度续玩（currentNodeId / 月份 / 精力落盘）
##   是方案 B 的活，别把这条当成已经能续上中途进度。
func _continue_game() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")

func _back() -> void: _mode = "title"; _rebuild()
func _go_page(index: int) -> void: _page = clampi(index, 0, PAGES.size() - 1); _rebuild()
func _placeholder() -> void: pass

## 真正退出程序。之前这里挂的是 _placeholder，按钮点下去毫无反应。
func _quit_game() -> void:
	get_tree().quit()

func _enter_town() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"sessionId":"local-" + str(Time.get_unix_time_from_system()), "avatarId":PlayerProfile.get_selected_avatar_id(), "contentVersion":"v1", "currentNodeId":"M1-E01", "unlockedRegionIds":["A", "H"]}))
	get_tree().change_scene_to_file("res://Main.tscn")


func _start_avatar_selection() -> void:
	_mode = "avatar"
	_rebuild()


func _avatar_screen() -> void:
	var frame := Panel.new()
	frame.position = Vector2(110, 56)
	frame.size = Vector2(1700, 968)
	frame.add_theme_stylebox_override("panel", _style(PAPER, WOOD, 8, 8))
	add_child(frame)

	var back := _button("返回", "secondary")
	back.position = Vector2(36, 34)
	back.size = Vector2(132, 60)
	back.pressed.connect(func() -> void: _mode = "intro"; _page = PAGES.size() - 1; _rebuild())
	frame.add_child(back)

	var kicker := _label("准备入职", 22, BRICK)
	kicker.position = Vector2(250, 54)
	kicker.size = Vector2(1200, 32)
	frame.add_child(kicker)
	var heading := _label("选择你的形象", 44, INK, 0.0, 0.30)
	heading.position = Vector2(250, 88)
	heading.size = Vector2(1200, 66)
	frame.add_child(heading)
	var description := _label("进入小镇后，地图、室内和宿舍都会使用这套形象。", 19, Color("7a5533"))
	description.position = Vector2(250, 154)
	description.size = Vector2(1200, 32)
	frame.add_child(description)

	var cards := HBoxContainer.new()
	cards.position = Vector2(115, 238)
	cards.size = Vector2(1470, 410)
	cards.add_theme_constant_override("separation", 18)
	frame.add_child(cards)
	for avatar_value in PlayerProfile.AVATARS:
		var avatar := avatar_value as Dictionary
		var avatar_id := String(avatar.get("id", ""))
		var card := Button.new()
		card.custom_minimum_size = Vector2(279, 410)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.add_theme_stylebox_override("normal", _style(Color("fff4d8"), BRICK if avatar_id == PlayerProfile.get_selected_avatar_id() else Color("865139"), 4 if avatar_id == PlayerProfile.get_selected_avatar_id() else 2, 6, 4))
		card.add_theme_stylebox_override("hover", _style(Color("fff9e9"), BRICK, 4, 6, 5))
		card.add_theme_stylebox_override("pressed", _style(Color("ead39f"), BRICK, 4, 6, 0))
		card.pressed.connect(_select_avatar.bind(avatar_id))
		cards.add_child(card)

		var portrait := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/characters/paper_doll_64/compiled/%s_walk_64.png" % avatar_id) as Texture2D
		atlas.region = Rect2(0, 0, 64, 80)
		portrait.texture = atlas
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.position = Vector2(55, 46)
		portrait.size = Vector2(170, 215)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)

		var name := _label(String(avatar.get("name", "")), 28, INK, 0.0, 0.22)
		name.position = Vector2(0, 284)
		name.size = Vector2(279, 42)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name)
		var selected := _label("当前选择" if avatar_id == PlayerProfile.get_selected_avatar_id() else "点击选择", 17, BRICK if avatar_id == PlayerProfile.get_selected_avatar_id() else Color("7a5533"))
		selected.position = Vector2(0, 332)
		selected.size = Vector2(279, 28)
		selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(selected)

	var confirm := _button("带着这个形象进入小镇", "primary")
	confirm.position = Vector2(625, 770)
	confirm.size = Vector2(450, 68)
	confirm.pressed.connect(_enter_town)
	frame.add_child(confirm)


func _select_avatar(avatar_id: String) -> void:
	if PlayerProfile.set_selected_avatar_id(avatar_id):
		_rebuild()

# ------------------------------------------------------------------ 零件

## 伪粗体：工程里只有 Noto Sans CJK 的 Regular 一个字重，中文在小字号下偏虚，
## 用 FontVariation 的 embolden 补一点分量（不是换字体文件，是给同一份字体加变体）。
func _font_weighted(amount: float) -> Font:
	if amount <= 0.0:
		return FONT
	var key := int(round(amount * 100.0))
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = FONT
		fv.variation_embolden = amount
		_fonts[key] = fv
	return _fonts[key]

func _label(value: String, font_size: int, color: Color, outline := 0.0, weight := 0.0) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _font_weighted(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0.0:
		# 描边颜色跟底色走（浅底深字用深描边），别一律白描边 —— 在米黄羊皮纸上会显脏
		label.add_theme_color_override("font_outline_color", Color(PAPER, 0.85))
		label.add_theme_constant_override("outline_size", int(outline))
	return label

func _spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = height
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.42, 0.26, 0.13, 0.45)
	line.custom_minimum_size.y = 3
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

## 小牌：给页码这类小信息裹一圈底盘。
## ⚠ 不能直接往 Label 上 override("normal") —— "normal" 是 Button 的 stylebox 名，
##   Label 只认 "normal" 之外的那套（其实 Label 根本没有 stylebox），所以当年那个框一直没画出来。
func _plate(child: Control, w: float, h: float) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(w, h)
	wrap.size = Vector2(w, h)
	wrap.add_theme_stylebox_override("panel", _style(Color("ead19c"), Color("865139"), 2, 5))
	wrap.add_child(child)
	return wrap

func _button(value: String, kind := "primary") -> Button:
	var button := Button.new()
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _font_weighted(0.16))
	button.add_theme_color_override("font_outline_color", EDGE)
	button.add_theme_constant_override("outline_size", 4)
	match kind:
		"primary":
			button.custom_minimum_size = Vector2(0, 68)
			button.add_theme_font_size_override("font_size", 30)
			button.add_theme_color_override("font_color", CREAM_TXT)
			button.add_theme_color_override("font_hover_color", Color("fffdf2"))
			button.add_theme_stylebox_override("normal", _style(BRICK, EDGE, 3, 6, 5))
			button.add_theme_stylebox_override("hover", _style(BRICK_HOVER, EDGE, 3, 6, 6))
			button.add_theme_stylebox_override("pressed", _style(BRICK_PRESSED, EDGE, 3, 6, 0))
		"secondary":
			button.custom_minimum_size = Vector2(0, 58)
			button.add_theme_font_size_override("font_size", 24)
			button.add_theme_color_override("font_color", INK)
			button.add_theme_color_override("font_hover_color", INK)
			button.add_theme_stylebox_override("normal", _style(SECOND_BG, SECOND_EDGE, 3, 6, 4))
			button.add_theme_stylebox_override("hover", _style(SECOND_BG_HOVER, SECOND_EDGE, 3, 6, 5))
			button.add_theme_stylebox_override("pressed", _style(Color("e2c894"), SECOND_EDGE, 3, 6, 0))
		"exit":
			button.custom_minimum_size = Vector2(0, 58)
			button.add_theme_font_size_override("font_size", 24)
			button.add_theme_color_override("font_color", EXIT_TXT)
			button.add_theme_color_override("font_hover_color", Color("fff1d8"))
			button.add_theme_stylebox_override("normal", _style(EXIT_BG, EDGE, 3, 6, 4))
			button.add_theme_stylebox_override("hover", _style(EXIT_BG_HOVER, EDGE, 3, 6, 5))
			button.add_theme_stylebox_override("pressed", _style(Color("5c3823"), EDGE, 3, 6, 0))
		"tab":
			# 导览页顶部页签：未选中
			button.custom_minimum_size = Vector2(0, 64)
			button.add_theme_font_size_override("font_size", 21)
			button.add_theme_color_override("font_color", Color("7a5533"))
			button.add_theme_color_override("font_hover_color", INK)
			button.add_theme_stylebox_override("normal", _style(Color("f8e9c6"), Color("865139"), 2, 5, 4))
			button.add_theme_stylebox_override("hover", _style(Color("fff6dc"), Color("865139"), 2, 5, 5))
			button.add_theme_stylebox_override("pressed", _style(Color("e6d3a4"), Color("865139"), 2, 5, 0))
		"tab_on":
			# 导览页顶部页签：选中（底色更深 + 边更粗）
			button.custom_minimum_size = Vector2(0, 64)
			button.add_theme_font_size_override("font_size", 21)
			button.add_theme_color_override("font_color", INK)
			button.add_theme_color_override("font_hover_color", INK)
			button.add_theme_stylebox_override("normal", _style(Color("e9cf98"), Color("7a4a2b"), 3, 5, 4))
			button.add_theme_stylebox_override("hover", _style(Color("f4e2b2"), Color("7a4a2b"), 3, 5, 5))
			button.add_theme_stylebox_override("pressed", _style(Color("dcc28a"), Color("7a4a2b"), 3, 5, 0))
		_:
			# chip：右上角那三个小方钮
			button.custom_minimum_size = Vector2(0, 52)
			button.add_theme_font_size_override("font_size", 22)
			button.add_theme_color_override("font_color", INK)
			button.add_theme_color_override("font_hover_color", INK)
			button.add_theme_stylebox_override("normal", _style(CHIP_BG, SECOND_EDGE, 3, 8, 4))
			button.add_theme_stylebox_override("hover", _style(CHIP_BG_HOVER, SECOND_EDGE, 3, 8, 5))
			button.add_theme_stylebox_override("pressed", _style(Color("dfc594"), SECOND_EDGE, 3, 8, 0))
	button.add_theme_stylebox_override("disabled", _style(Color(0.84, 0.78, 0.65), Color("a9977c"), 3, 6))
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.4, 0.34))
	return button

## bevel：底边那层「厚度」（CSS 的 0 Npx 0）。用无模糊阴影偏移近似，比纯描边更有实体感。
func _style(background: Color, border: Color, width: int, radius: int, bevel := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	if bevel > 0:
		style.shadow_color = Color(border.r, border.g, border.b, 0.5)
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, bevel)
	return style
