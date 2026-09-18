class_name StandingPanel
extends CanvasLayer

## 「你的处境」常驻页（V5.27 §2.4 明示原则 —— 剧情册里标注的**最高优先级红线**）。
##
## 这一页存在的唯一理由：玩家必须死得明明白白。
##   ① 随时能查：不必等结算、不必触发事件，任何时候都能翻开这一页。
##   ② 说得出原因：每次处境变化都留一条记录，用行为语言写、带着具体月份。
##   ③ 知道还剩多少余地：进危急就明示「再一次重大失误将触发正式谈话」，
##      **不存在跳变死亡**。
##
## 两条硬红线贯穿全页：
##   - §2.3「阈值数字永不出现」→ 页面上一个分数都没有。职级也只用**称谓**
##     （「独立负责一块」），不写 L3，更不提任何门槛。
##   - §2.4「用文字，不用数字和血条」→ 处境就是一句话：没有进度条、
##     没有 strike 计数、连自我修复的进度也只给一句人话，不给倒计时。
##
## 数值**全部来自服务端下发**（2026-09-17 拍板：口径只留一份，Godot 本地不算）。
## 接不到服务端时必须如实说「读不到」，绝不本地估一个看起来像的值糊上去 ——
## 一个编出来的「稳定」，比没有这一页更糟。

signal standing_closed

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

const PAGE_W := 1180.0
const PAGE_H := 880.0
const PAD := 64.0
const CONTENT_W := PAGE_W - PAD * 2.0

const PAPER := Color("efe4cf")
const PAPER_EDGE := Color("e2d4b8")
const INK := Color("352b1e")
const INK_SOFT := Color("6d5c46")
const INK_FAINT := Color("8b7860")
const RULE := Color("c8b694")
const CALM := Color("4a6b4f")
const ALERT := Color("a8452f")
const ACCENT := Color("9a6b2f")

## 职级 → 「你现在能碰到的活」（V5.27 §2.2 项目阶段 × 职级解锁）。
## 表里的说法照抄设计文档那张表的「玩家角色」列 —— 职级门槛一个字都不提。
const ROLE_BY_LEVEL := {
	1: "打下手",
	2: "打下手，快能独立了",
	3: "独立负责一块",
	4: "核心组里的人",
	5: "牵头人",
	6: "说了算的人之一",
	7: "说了算的人",
}

## 成长轨 / 生存轨的分工，写在这一页的最底下。
## 必要性：玩家很容易把「没升职」读成「要被开了」—— 而按 §2.4 这两条线
## **互相独立**：四年不升但踏实干活的人不会被触碰，两年埋三次雷的才会。
const TWO_TRACKS_NOTE := "晋升和去留是两条不相干的线：一直升不上去不会被开，" \
	+ "但埋了雷就会被记住。这一页的下半部分是后者。"

var _root: Control
var _content: VBoxContainer
var _state: Dictionary = {}
var _month := 0


func _ready() -> void:
	layer = 170
	_root = Control.new()
	_root.name = "StandingOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_build_shell()
	_root.hide()


## state = 服务端下发的会话状态（ApiClient.server_state()）；month = 游戏内当前月份。
func open(state: Dictionary, month := 0) -> void:
	_state = state.duplicate(true)
	_month = month
	_render()
	_root.show()


func close() -> void:
	if _root == null or not _root.visible:
		return
	_root.hide()
	standing_closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


# ---------------------------------------------------------------- 骨架

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var page := Panel.new()
	page.name = "Page"
	page.size = Vector2(PAGE_W, PAGE_H)
	page.add_theme_stylebox_override("panel", _paper_style())
	_root.add_child(page)
	var size := Vector2(get_viewport().get_visible_rect().size)
	if size.x <= 0.0:
		size = Vector2(1920, 1080)
	page.position = Vector2(round((size.x - PAGE_W) * 0.5), round((size.y - PAGE_H) * 0.5))

	var title := _label("你的处境", 34, INK, false, 520.0)
	title.position = Vector2(PAD, 46)
	title.size = Vector2(520, 46)
	page.add_child(title)

	var subtitle := _label("随时能翻到的一页 —— 现在站在哪里、为什么，都写在这儿。",
		17, INK_SOFT, false, 620.0)
	subtitle.position = Vector2(PAD, 100)
	subtitle.size = Vector2(620, 26)
	page.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(PAD, 148)
	scroll.size = Vector2(CONTENT_W, PAGE_H - 148 - 112)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_content)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "合上这一页"
	close_button.size = Vector2(190, 56)
	close_button.position = Vector2(PAGE_W - 190 - PAD, PAGE_H - 76)
	close_button.add_theme_font_override("font", FONT)
	close_button.add_theme_font_size_override("font_size", 19)
	close_button.add_theme_color_override("font_color", Color("fdf6e6"))
	close_button.add_theme_color_override("font_hover_color", Color("ffffff"))
	close_button.add_theme_color_override("font_pressed_color", Color("e8d5ac"))
	close_button.add_theme_stylebox_override("normal", _box(Color(0.329, 0.196, 0.122, 0.96), CALM))
	close_button.add_theme_stylebox_override("hover", _box(Color(0.40, 0.24, 0.15), Color("6fa073")))
	close_button.add_theme_stylebox_override("pressed", _box(Color(0.27, 0.16, 0.10), CALM))
	close_button.pressed.connect(close)
	page.add_child(close_button)


# ---------------------------------------------------------------- 渲染

func _render() -> void:
	for child in _content.get_children():
		child.queue_free()
	if _state.is_empty():
		_render_unknown()
		return
	_render_rank()
	_content.add_child(_rule_box(24))
	_render_survival()
	_content.add_child(_rule_box(24))
	var note := _label(TWO_TRACKS_NOTE, 16, INK_FAINT, true, CONTENT_W)
	_content.add_child(note)


## 接不到服务端时**如实说**。这是刻意的：绝不本地估算一个「看起来像」的职级或处境。
func _render_unknown() -> void:
	_content.add_child(_section_head("现在还读不到"))
	_content.add_child(_body("职级和处境是后台算出来的，这一局还没跟它对上账。"
		+ "连上后台（或过了开场的第一次节点）再翻这一页，这里就会写上。", 19, INK))
	_content.add_child(_body("这一页宁可空着，也不会拿一个估的数字顶上 —— "
		+ "编出来的「稳定」比什么都看不到更糟。", 17, INK_SOFT))


func _render_rank() -> void:
	_content.add_child(_section_head("你现在能碰到什么活"))
	var level := int(_state.get("level", 0))
	if level <= 0:
		_content.add_child(_body("后台还没给出职级。", 19, INK_SOFT))
	else:
		var role := String(ROLE_BY_LEVEL.get(clampi(level, 1, 7), ""))
		var role_line := _label(role, 40, INK, false, CONTENT_W)
		_content.add_child(role_line)
		_content.add_child(_body(_month_line(), 19, INK_SOFT))
	var next_month := int(_state.get("nextAssessmentMonth", 0))
	if next_month > 0:
		_content.add_child(_body("下一次考评在第 %d 月。" % next_month, 18, ACCENT))
	else:
		_content.add_child(_body("七个考核窗都走完了 —— 剩下的，就是最后那一场答辩。",
			18, ACCENT))


func _render_survival() -> void:
	_content.add_child(_section_head("你的处境"))
	var view := Dictionary(_state.get("survivalState", {}))
	if view.is_empty():
		_content.add_child(_body("后台还没给出处境。", 19, INK_SOFT))
		return

	var label := String(view.get("label", ""))
	# 状态本身就是一句话，不加也不渲染任何进度条 —— §2.4「用文字，不用数字和血条」。
	var state_line := _label(label, 40, _state_color(String(view.get("state", ""))), false, CONTENT_W)
	_content.add_child(state_line)

	var warning := String(view.get("warning", ""))
	if not warning.is_empty():
		_content.add_child(_body(warning, 21, ALERT))

	var healing := String(view.get("healingLine", ""))
	if not healing.is_empty():
		_content.add_child(_body(healing, 18, INK_SOFT))

	var reasons := Array(view.get("reasons", [])).duplicate()
	_content.add_child(_rule_box(14))
	if reasons.is_empty():
		_content.add_child(_body("到现在为止，没有要记在账上的事。", 18, INK_SOFT))
	else:
		var head := _label("为什么走到这里", 18, INK_SOFT, false, CONTENT_W)
		_content.add_child(head)
		for reason in reasons:
			_content.add_child(_body("·  " + String(reason), 18, INK))


func _month_line() -> String:
	if _month > 0:
		return "现在是第 %d 月。" % _month
	return ""


## 处境配色：稳定用沉绿，其余逐级转暖到红。
## ⚠ 颜色只是快读的辅助，语义永远有文字兜着 —— 色盲玩家读到的句子是一样的。
func _state_color(state_name: String) -> Color:
	match state_name:
		"stable":
			return CALM
		"observation":
			return ACCENT
		_:
			return ALERT


# ---------------------------------------------------------------- 零件

func _section_head(text: String) -> Label:
	var head := _label(text, 22, INK_SOFT, false, CONTENT_W)
	head.custom_minimum_size = Vector2(CONTENT_W, 34)
	return head


func _rule_box(height: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(CONTENT_W, height)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = RULE
	line.size = Vector2(CONTENT_W, 1)
	line.position = Vector2(0, height * 0.5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box


func _body(text: String, size: int, color: Color) -> Label:
	var label := _label(text, size, color, true, CONTENT_W)
	label.custom_minimum_size = Vector2(CONTENT_W, size + 16)
	return label


## ⚠ 踩过的坑（同 HandbookPanel）：Label 开了 autowrap 时，它的最小高度按**当时**
## 的 size.x 算。所以创建时就要给对宽度，否则容器按窄宽度算高度、正文被底边切掉。
func _label(text: String, size: int, color: Color, wrap: bool, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(width, size + 12)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = PAPER_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	return style


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style
