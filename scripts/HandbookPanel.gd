class_name HandbookPanel
extends CanvasLayer

## 《新员工手册》阅读器（V5.27 · E01 核心可交互物）。
##
## 设计要点：
##  1. 这是一本**真的能读的册子**，不是三选一的选项文案——玩家看得到条款原文。
##  2. 册子边上有前任留下的铅笔批注（margin），读到章末才会浮出来：
##     让"手册"变成"有人用过的物件"，玩家读的是痕迹，不是说明书。
##  3. 埋点按 V5.27 要求：各章阅读时长 + 跳过行为。关闭时一次性交回。
##
## 视觉上刻意与对话层相反：对话是黑底白字的撕裂气泡，手册是米黄纸质 + 深褐油墨。
##
## 布局注意（踩过的坑）：Label 开了 autowrap 之后，它的最小高度是按**当时**的 size.x
## 算的。所以每个 Label 在创建时就要给对宽度，否则容器按窄宽度算高度、正文被底边切掉。
## 同理，内容区必须放在 ScrollContainer 里——手册是真有字数的，一屏放不下。

signal handbook_closed(records: Dictionary)

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const CONTENT_PATH := "res://data/story/employee_handbook.json"

const PAGE_W := 1348.0
const PAGE_H := 848.0
const RAIL_W := 272.0
const PAD := 64.0
const SCROLLBAR := 14.0
## 正文可用宽度：页面宽 - 左目录 - 左右内边距 - 滚动条
const CONTENT_W := PAGE_W - RAIL_W - PAD * 2.0 - SCROLLBAR

const PAPER := Color("efe4cf")
const PAPER_DARK := Color("e2d4b8")
const INK := Color("352b1e")
const INK_SOFT := Color("6d5c46")
const PENCIL := Color("7d6a52")
const RULE := Color("c8b694")

## 停留不足这个时长就翻走 = 跳过（V5.27 埋点项）
const SKIP_THRESHOLD_MS := 1600

var _root: Control
var _rail: VBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _page_label: Label
var _data: Dictionary = {}
var _chapters: Array = []
var _current := ""
var _tab_buttons: Dictionary = {}
var _visited: Dictionary = {}
var _dwell_ms: Dictionary = {}
var _enter_ms := 0
var _open_ms := 0


func _ready() -> void:
	layer = 160
	_root = Control.new()
	_root.name = "HandbookOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_build_shell()
	_root.hide()


func open(data: Dictionary = {}) -> void:
	_data = data if not data.is_empty() else _load_default()
	_chapters = _data.get("chapters", []) as Array
	_visited.clear()
	_dwell_ms.clear()
	_open_ms = Time.get_ticks_msec()
	_enter_ms = _open_ms
	_current = ""
	_build_rail()
	var first := ""
	if not _chapters.is_empty():
		first = String(Dictionary(_chapters[0]).get("id", ""))
	_select_chapter(first)
	_root.show()


func close() -> void:
	if not _root.visible:
		return
	_settle_current()
	_root.hide()
	handbook_closed.emit(_records())


func is_open() -> bool:
	return _root != null and _root.visible


func chapter_ids() -> Array:
	var ids: Array = []
	for chapter in _chapters:
		ids.append(String(Dictionary(chapter).get("id", "")))
	return ids


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
	var size := _view_size()
	page.position = Vector2(round((size.x - PAGE_W) * 0.5), round((size.y - PAGE_H) * 0.5))

	# 装订线：册子中间那道折痕。有它才像"册子"，没它就是"弹窗"。
	var spine := ColorRect.new()
	spine.color = Color(0.0, 0.0, 0.0, 0.10)
	spine.position = Vector2(RAIL_W, 0)
	spine.size = Vector2(2, PAGE_H)
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(spine)
	var spine_hi := ColorRect.new()
	spine_hi.color = Color(1, 1, 1, 0.22)
	spine_hi.position = Vector2(RAIL_W + 2, 0)
	spine_hi.size = Vector2(2, PAGE_H)
	spine_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(spine_hi)

	_rail = VBoxContainer.new()
	_rail.name = "Rail"
	_rail.position = Vector2(24, 96)
	_rail.size = Vector2(RAIL_W - 48, PAGE_H - 200)
	_rail.add_theme_constant_override("separation", 10)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_rail)

	_scroll = ScrollContainer.new()
	_scroll.name = "ContentScroll"
	_scroll.position = Vector2(RAIL_W + PAD, 54)
	_scroll.size = Vector2(PAGE_W - RAIL_W - PAD * 2, PAGE_H - 148)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_theme_constant_override("scrollbar_width", 10)
	page.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)

	_page_label = _label("", 17, INK_SOFT, false, 460.0)
	_page_label.position = Vector2(RAIL_W + PAD, PAGE_H - 62)
	_page_label.size = Vector2(460, 28)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page.add_child(_page_label)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "合上手册"
	close_button.size = Vector2(190, 56)
	close_button.position = Vector2(PAGE_W - 190 - PAD, PAGE_H - 74)
	_style_close(close_button)
	close_button.pressed.connect(close)
	page.add_child(close_button)


func _build_rail() -> void:
	for child in _rail.get_children():
		child.queue_free()
	_tab_buttons.clear()
	var head := _label("目 录", 18, INK_SOFT, false, RAIL_W - 48.0)
	head.custom_minimum_size = Vector2(RAIL_W - 48, 34)
	_rail.add_child(head)
	for chapter in _chapters:
		var data := Dictionary(chapter)
		var id := String(data.get("id", ""))
		var button := Button.new()
		button.name = "Tab_%s" % id
		button.text = "第 %d 章　%s" % [int(data.get("index", 0)), String(data.get("title", ""))]
		button.custom_minimum_size = Vector2(RAIL_W - 48, 62)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_style_tab(button, false)
		button.pressed.connect(func(): _select_chapter(id))
		_rail.add_child(button)
		_tab_buttons[id] = button
	var hint := _label(String(_data.get("marginHint", "")), 15, PENCIL, false, RAIL_W - 48.0)
	hint.custom_minimum_size = Vector2(RAIL_W - 48, 90)
	_rail.add_child(hint)


# ---------------------------------------------------------------- 章节

func _select_chapter(chapter_id: String) -> void:
	if chapter_id.is_empty() or chapter_id == _current:
		return
	_settle_current()
	_current = chapter_id
	_enter_ms = Time.get_ticks_msec()
	_visited[chapter_id] = true
	if not _dwell_ms.has(chapter_id):
		_dwell_ms[chapter_id] = 0
	for key in _tab_buttons.keys():
		var button: Button = _tab_buttons[key]
		if is_instance_valid(button):
			_style_tab(button, String(key) == chapter_id)
	_render_chapter(_chapter_data(chapter_id))
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0
	if is_instance_valid(_page_label):
		var index := _chapters.find(_chapter_data(chapter_id))
		_page_label.text = "第 %d 章 · 共 %d 章　|　%s　|　%s" % [
			index + 1, _chapters.size(), String(_data.get("title", "")), String(_data.get("edition", "")),
		]


func _settle_current() -> void:
	if _current.is_empty():
		return
	var spent := Time.get_ticks_msec() - _enter_ms
	_dwell_ms[_current] = int(_dwell_ms.get(_current, 0)) + spent


func _chapter_data(chapter_id: String) -> Dictionary:
	for chapter in _chapters:
		var data := Dictionary(chapter)
		if String(data.get("id", "")) == chapter_id:
			return data
	return {}


func _render_chapter(chapter: Dictionary) -> void:
	for child in _content.get_children():
		# 先摘出树再释放：只 queue_free 的话，同一帧内 get_children 仍返回旧节点，
		# 会和刚建好的新内容叠在一起显示一帧。
		_content.remove_child(child)
		child.queue_free()
	if chapter.is_empty():
		return
	var title := _label(String(chapter.get("title", "")), 34, INK, true, CONTENT_W)
	title.custom_minimum_size = Vector2(CONTENT_W, 50)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_content.add_child(title)
	var sub := _label(String(chapter.get("subtitle", "")), 19, INK_SOFT, false, CONTENT_W)
	sub.custom_minimum_size = Vector2(CONTENT_W, 30)
	_content.add_child(sub)
	var lead := _label(String(chapter.get("lead", "")), 19, INK_SOFT, false, CONTENT_W)
	lead.custom_minimum_size = Vector2(CONTENT_W, 28)
	_content.add_child(lead)
	_content.add_child(_rule())

	for clause in chapter.get("clauses", []) as Array:
		_content.add_child(_build_clause(Dictionary(clause)))

	# 铅笔批注：读到章末才出现。它是"有人用过这本册子"的证据。
	var margin := String(chapter.get("margin", ""))
	if not margin.is_empty():
		_content.add_child(_rule())
		_content.add_child(_build_margin_note(margin, String(_data.get("marginOwner", ""))))


func _build_clause(clause: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var number := _label("§%s" % String(clause.get("id", "")), 19, INK_SOFT, false, 58.0)
	number.custom_minimum_size = Vector2(58, 30)
	head.add_child(number)
	# 右端留白给铅笔批注。批注是【玩家可见】的一句人话（不含任何事件编号）。
	# HBox 列宽必须刚好等于 CONTENT_W：§号 58 + 间距 12×2 + 标题 + 批注 300。
	# 之前少减了 52px，批注被挤出内容区、压到滚动条上。
	var name_width := CONTENT_W - 382.0
	var name := _label(String(clause.get("title", "")), 22, INK, true, name_width)
	name.custom_minimum_size = Vector2(name_width, 30)
	head.add_child(name)
	var pencil := String(clause.get("pencil", ""))
	if not pencil.is_empty():
		# 15px：比正文（19）小一号才像旁注，再小在 1080p 下就糊成一片
		var tag := _label(pencil, 15, PENCIL, false, 300.0)
		tag.custom_minimum_size = Vector2(300, 30)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		head.add_child(tag)
	box.add_child(head)
	var body_width := CONTENT_W - 70.0
	var body := _label(String(clause.get("body", "")), 19, INK, false, body_width)
	body.custom_minimum_size = Vector2(body_width, 0)
	body.add_theme_constant_override("line_spacing", 8)
	box.add_child(body)
	return box


func _build_margin_note(text: String, owner_name: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := _label("［%s 的铅笔字］" % owner_name, 15, PENCIL, false, CONTENT_W)
	head.custom_minimum_size = Vector2(CONTENT_W, 24)
	box.add_child(head)
	var body_width := CONTENT_W - 70.0
	var body := _label(text, 19, PENCIL, false, body_width)
	body.custom_minimum_size = Vector2(body_width, 0)
	body.add_theme_constant_override("line_spacing", 8)
	box.add_child(body)
	return box


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = RULE
	line.custom_minimum_size = Vector2(CONTENT_W, 1)
	line.size = Vector2(CONTENT_W, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


# ---------------------------------------------------------------- 埋点

func _records() -> Dictionary:
	var chapters := {}
	for chapter in _chapters:
		var id := String(Dictionary(chapter).get("id", ""))
		var dwell := int(_dwell_ms.get(id, 0))
		var seen := bool(_visited.get(id, false))
		chapters[id] = {
			"visited": seen,
			"dwellMs": dwell,
			"skipped": (not seen) or dwell < SKIP_THRESHOLD_MS,
		}
	return {
		"totalMs": Time.get_ticks_msec() - _open_ms,
		"chapters": chapters,
	}


# ---------------------------------------------------------------- 零件

func _load_default() -> Dictionary:
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		push_warning("HandbookPanel: 读不到 %s" % CONTENT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return Dictionary(parsed)
	return {}


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1920, 1080)
	return vp.get_visible_rect().size


func _bold(font: Font, weight: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_embolden = weight
	return variation


## wrap_width 必须在创建时就给对：autowrap 的最小高度按当时的 size.x 算，
## 先给 320 再被容器拉到 900 的话，高度会按 320 算，正文被底边切掉。
func _label(value: String, font_size: int, color: Color, bold: bool = false, wrap_width: float = 320.0) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(wrap_width, 40)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _bold(FONT, 0.6) if bold else FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color(0.28, 0.22, 0.15, 0.85)
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style


func _style_tab(button: Button, active: bool) -> void:
	button.add_theme_font_override("font", _bold(FONT, 0.6) if active else FONT)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", PAPER if active else INK)
	button.add_theme_color_override("font_hover_color", PAPER if active else Color("171208"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.0) if not active else Color("4a3b28")
	normal.border_color = Color(1, 1, 1, 0.0) if not active else Color("2a2115")
	normal.set_border_width_all(0 if not active else 2)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 14
	normal.content_margin_right = 10
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("5d4a31") if active else PAPER_DARK
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)


func _style_close(button: Button) -> void:
	button.add_theme_font_override("font", _bold(FONT, 0.5))
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("171208"))
	button.add_theme_stylebox_override("normal", _close_box(PAPER_DARK))
	button.add_theme_stylebox_override("hover", _close_box(Color("d6c5a3")))
	button.add_theme_stylebox_override("pressed", _close_box(Color("c9b795")))


func _close_box(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.32, 0.25, 0.17, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style
