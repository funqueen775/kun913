extends CanvasLayer
## 周末手账册（设计说明《自由周末参与感设计说明 V1》§6.2，二期 D 件）。
##
## 16 页：free_time_system 的排期里一个自由周末 = 每 3 个月一页（3,6,…,48）。
##   已过的页 = 手账卡（区域 / 两格 / 投入结构 / 手写一句 / 关系短语）
##   没留手账的过去页 = 灰卡「这个周末没留下手账」
##   未到的页 = 空格子「还没到」——**空格不隐藏**，它是"这个月还有得盼"的视觉。
##
## 数据源：user://workplace_town_weekends.jsonl（WorkplaceTown 在手账收束时落盘）。
## 红线：手账卡与回声同规——**任何数字流水都不出现**，只给人话。
## 打开期间世界时钟停住（与记忆墙同一待遇，由 WorkplaceTown 负责）。

signal book_closed()

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const MONTHLY_LIFE := preload("res://scripts/MonthlyLife.gd")
const FREE_TIME_PANEL := preload("res://scripts/FreeTimePanel.gd")

const PAPER := Color("efe4cf")
const CARD_BG := Color("f6efdf")
const PAPER_BLANK := Color("e6ddc9")
const PAPER_FADED := Color("eae1cd")
const INK := Color("352b1e")
const INK_SOFT := Color("6d5c46")
const INK_FADED := Color("9b8b71")
const LINE := Color("b9a888")
const LINE_FADED := Color("cfc4ab")
const SEAL := Color("b5483a")
const SEAL_FADED := Color("c2b190")
const SEAL_TEXT := Color("f6eeda")
const BTN_INK := Color("3f3325")
const BTN_INK_HOVER := Color("574834")

## 纸质感资产包（ImageGen 生成 + PIL 后处理，见 scripts/ui/ledger_paper_kit.gd）。
const PAPER_KIT := preload("res://scripts/ui/ledger_paper_kit.gd")
## 手账标题字体（霞鹜文楷，OFL 可商用）。缺文件自动回落 Noto——运行时 load() 判，不进 preload。
## ⚠ 文件名带 Full：本机已存在文件无法覆盖，重下时必须换新文件名（2026-09-17 实测）。
const WENKAI_PATH := "res://assets/ui/ledger/LXGWWenKaiFull.ttf"

## 面板固定尺寸（1920x1080 下左右各留 260 / 上下各留 96）。
## 用常量而不用 panel.size —— 构建期 anchors 还没算，size.x 是 0。
const PANEL_W := 1400.0
const PANEL_H := 888.0

const WEATHER_TEXT := {"sunny": "晴", "rainy": "小雨"}

var _root: Control
var _scroll: ScrollContainer
var _list: GridContainer
var _count_label: Label

var _records: Array = []
var _wenkai: Font = null


func _ready() -> void:
	# 与记忆墙同层(170)：从小镇 HUD 打开时不能被剧情面板(150)/手册(160)遮住。
	layer = 170
	_wenkai = load(WENKAI_PATH) as Font if ResourceLoader.exists(WENKAI_PATH) else null
	_root = Control.new()
	_root.name = "WeekendLedgerBookOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_build_shell()
	_root.hide()


# ---------------------------------------------------------------- 对外

func is_open() -> bool:
	return _root != null and _root.visible


func open(records: Array, current_month: int) -> void:
	show_pages(records, current_month)


## 铺 16 页。records 为空 = 全是空格（新档也能看"48 个月的形状"）。
func show_pages(records: Array, current_month: int) -> void:
	_records = records
	for child in _list.get_children():
		child.queue_free()
	var pages := build_pages(records, current_month)
	var cards := 0
	for page in pages:
		_list.add_child(_make_page_row(page))
		if page["state"] == "card":
			cards += 1
	_count_label.text = "写过 %d 页 · 还没到 %d 页" % [cards, pages.size() - cards]
	_root.show()


func close() -> void:
	_root.hide()
	book_closed.emit()


# ---------------------------------------------------------------- 纯函数（探针可直接调）

## 自由周末排期：每 3 个月一页，共 16 页（3,6,…,48）。
static func weekend_months() -> Array:
	var months: Array = []
	for i in range(1, 17):
		months.append(i * 3)
	return months


## 16 页的形状。state: "card"（有手账）/ "past_blank"（过了没留）/ "future"（还没到）。
static func build_pages(records: Array, current_month: int) -> Array:
	var by_month := {}
	for rec in records:
		if rec is Dictionary:
			by_month[int(rec.get("month", 0))] = rec
	var pages: Array = []
	for m in weekend_months():
		if m > current_month:
			pages.append({"month": m, "state": "future", "record": {}})
		elif by_month.has(m):
			pages.append({"month": m, "state": "card", "record": by_month[m]})
		else:
			pages.append({"month": m, "state": "past_blank", "record": {}})
	return pages


# ---------------------------------------------------------------- UI

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.09, 0.14, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 260
	panel.offset_top = 96
	panel.offset_right = -260
	panel.offset_bottom = -96
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	PAPER_KIT.grain(panel, 0.5)
	PAPER_KIT.tape_center(panel, 132.0, 2.0)

	# —— 页眉：HBox 排版。旧版标题/统计手摆坐标 + autowrap，Label 最小宽度
	# 塌成单字宽，标题被挤成竖排（2026-09-17 截图问题），容器排版根治。——
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 36
	header.offset_right = -36
	header.offset_top = 20
	header.offset_bottom = 72
	header.add_theme_constant_override("separation", 18)
	panel.add_child(header)

	var title := _label("周末手账", 28, INK, false, _wenkai)
	header.add_child(title)

	_count_label = _label("", 15, INK_SOFT, false)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_count_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_button := _make_close_button()
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var rule := ColorRect.new()
	rule.color = LINE
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_left = 36
	rule.offset_right = -36
	rule.offset_top = 82
	rule.offset_bottom = 83
	panel.add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(36, 100)
	_scroll.size = Vector2(PANEL_W - 72.0, PANEL_H - 132.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)

	var vbar := _scroll.get_v_scroll_bar()
	vbar.custom_minimum_size = Vector2(8, 0)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = LINE
	grabber.set_corner_radius_all(4)
	vbar.add_theme_stylebox_override("grabber", grabber)
	var grabber_hl := grabber.duplicate() as StyleBoxFlat
	grabber_hl.bg_color = INK_SOFT
	vbar.add_theme_stylebox_override("grabber_highlight", grabber_hl)
	vbar.add_theme_stylebox_override("grabber_pressed", grabber_hl)

	_list = GridContainer.new()
	_list.columns = 2
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 16)
	_list.add_theme_constant_override("v_separation", 14)
	_scroll.add_child(_list)


func _make_close_button() -> Button:
	var close_button := Button.new()
	close_button.text = "合上"
	close_button.custom_minimum_size = Vector2(96, 44)
	close_button.add_theme_font_override("font", FONT)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.add_theme_color_override("font_color", SEAL_TEXT)
	close_button.add_theme_color_override("font_hover_color", SEAL_TEXT)
	close_button.add_theme_color_override("font_pressed_color", SEAL_TEXT)
	close_button.add_theme_color_override("font_focus_color", SEAL_TEXT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = BTN_INK
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BTN_INK_HOVER
	close_button.add_theme_stylebox_override("normal", normal)
	close_button.add_theme_stylebox_override("hover", hover)
	close_button.add_theme_stylebox_override("pressed", hover)
	close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return close_button


func _make_page_row(page: Dictionary) -> Control:
	var month := int(page.get("month", 0))
	var state := String(page.get("state", "future"))
	var record: Dictionary = page.get("record", {})

	if state == "future":
		return _make_future_row(month)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if state != "card":
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG if state == "card" else PAPER_BLANK
	style.set_border_width_all(1)
	style.border_color = LINE
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", style)
	PAPER_KIT.grain(card, 0.4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	if state == "card":
		PAPER_KIT.tape_tr(card)

	row.add_child(_seal(month, state == "card"))

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	row.add_child(box)

	if state != "card":
		box.add_child(_label("空页", 18, INK_SOFT, false))
		box.add_child(_label("这个周末过去了，没留下手账。", 14, INK_FADED))
		return card

	var weather := String(WEATHER_TEXT.get(String(record.get("weather", "")), ""))
	box.add_child(_label("第 %d 月%s" % [month, (" · " + weather) if not weather.is_empty() else ""], 18, INK, false))
	for slot in record.get("slots", []):
		if not (slot is Dictionary):
			continue
		var act_id := String(slot.get("activityId", ""))
		var act_name := String(FREE_TIME_PANEL.ACTIVITY_NAMES.get(act_id, act_id)) if not act_id.is_empty() else "留白"
		var names: Array = []
		var targets = slot.get("targets", [])
		if targets is Array:
			for npc_id in targets:
				var key := String(npc_id)
				names.append(String(MONTHLY_LIFE.NPC_NAMES.get(key, key)))
		var who := "、".join(names) if not names.is_empty() else "一个人"
		box.add_child(_label("%s　%s　%s" % [_slot_label(String(slot.get("slotId", ""))), act_name, who], 15, INK))
	var structure := String(record.get("structureLine", ""))
	if not structure.is_empty():
		box.add_child(_label(structure, 14, INK_SOFT, true, _wenkai))
	var note := String(record.get("playerNote", ""))
	if not note.is_empty():
		box.add_child(_label("「%s」" % note, 14, INK_SOFT, true, _wenkai))
	var phrases: Array = []
	for phrase in record.get("relations", []):
		if phrase is String and not (phrase as String).is_empty():
			phrases.append(String(phrase))
	if not phrases.is_empty():
		box.add_child(_label(" · ".join(phrases), 13, INK_FADED))
	return card


## 未到的页：压成一行细条——保留"还有得盼"的空格视觉，但不再占一整张卡的高度。
func _make_future_row(month: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER_FADED
	style.set_border_width_all(1)
	style.border_color = LINE_FADED
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	card.add_theme_stylebox_override("panel", style)
	PAPER_KIT.grain(card, 0.35)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = LINE_FADED
	dot_style.set_corner_radius_all(4)
	dot.add_theme_stylebox_override("panel", dot_style)
	row.add_child(dot)

	row.add_child(_label("第 %d 月" % month, 15, INK_FADED, false))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_label("还没到 · 这个周末还在路上", 13, INK_FADED, false))
	return card


## 页码印章：有手账的页盖朱红章，空页盖褪色章（贴图 + 调制，保留页码字）。
func _seal(month: int, vivid: bool) -> Panel:
	var seal := Panel.new()
	seal.custom_minimum_size = Vector2(48, 48)
	seal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	seal.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var tex := TextureRect.new()
	tex.texture = PAPER_KIT.SEAL_TEX
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.self_modulate = Color(0.96, 0.82, 0.8) if vivid else Color(0.8, 0.74, 0.64, 0.42)
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seal.add_child(tex)
	var text := _label("%d月" % month, 15, SEAL_TEXT, false, _wenkai)
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(text)
	return seal


func _slot_label(slot_id: String) -> String:
	match slot_id:
		"sat_am":
			return "周六上午"
		"sat_pm":
			return "周六下午"
	return slot_id


## wrap=false 时关闭 autowrap 并去掉 expand——脱离容器的手摆 Label 一旦开
## autowrap，最小宽度会塌成单字宽，整句被挤成竖排（本次事故根因）。
## font=null 时用正文 Noto；传 _wenkai 则标题/手写句走文楷。
func _label(text: String, size: int, color: Color, wrap := true, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font if font != null else FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
