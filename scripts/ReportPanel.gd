extends CanvasLayer
## 「我的报告」全屏面板（Batch 3，2026-09-17）。
## 数据链路红线：报告只在服务端算（loader.py L7「scoring_cards 不得下发前端」），
## 这里**只渲染** ApiClient.fetch_report() 拉回来的 JSON，本地不算任何分。
## 拉取流程：open() → 状态条「正在生成…」→ ApiClient.fetch_report() →
##   report_ready(report) → render(report)；report_failed(reason) → 状态条说明原因 + 可重试。
## 版式口径与 StartupFlow / EnergyPanel 一致：木框 + 羊皮纸 + 米色便签。
## 探针：build/probe_report_panel.gd（喂 contracts/fixtures/report-ready.json 验渲染）。

signal closed

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

# 与 EnergyPanel 同源的木色 / 羊皮纸配色（无 tokens 文件，色值集中在这几行）。
const COLOR_DIM := Color(0.05, 0.07, 0.05, 0.55)
const COLOR_WOOD := Color("54321f")
const COLOR_BORDER := Color("d49a4c")
const COLOR_PAPER := Color("f5ecd7")
const COLOR_INK := Color("4a3a20")
const COLOR_SUB := Color("7a6547")
const COLOR_TITLE := Color("ffe5a8")
const COLOR_ACCENT := Color("ef9f27")
const COLOR_GOOD := Color("3f7d4e")
const COLOR_BAD := Color("9c4a38")

const PANEL_RECT := Rect2(210, 60, 1500, 940)

var _report: Dictionary = {}
var _dim: ColorRect
var _panel: Panel
var _scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _retry_btn: Button
var _close_btn: Button

func _ready() -> void:
	layer = 200
	visible = false
	_build_static()
	# 只连一次；处理器里用 visible 判断是否消费，避免面板关着时收包。
	ApiClient.report_ready.connect(_on_report_ready)
	ApiClient.report_failed.connect(_on_report_failed)


# ------------------------------------------------------------------ 开合

func open() -> void:
	visible = true
	_report = {}
	_set_status("正在生成报告……（报告由服务端结算，走完的剧情都在里面）", true)
	_rebuild_list()
	ApiClient.fetch_report()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()


# ------------------------------------------------------------------ 静态骨架

func _build_static() -> void:
	_dim = ColorRect.new()
	_dim.color = COLOR_DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = Panel.new()
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size
	_panel.add_theme_stylebox_override("panel", _style(COLOR_PAPER, COLOR_WOOD, 10, 6))
	add_child(_panel)

	var title := _label("我 的 报 告", 30, COLOR_INK)
	title.position = Vector2(30, 18)
	title.size = Vector2(500, 40)
	_panel.add_child(title)

	_status = _label("", 16, COLOR_SUB)
	_status.position = Vector2(30, 62)
	_status.size = Vector2(PANEL_RECT.size.x - 220, 26)
	_panel.add_child(_status)

	_retry_btn = _button("重新拉取")
	_retry_btn.position = Vector2(PANEL_RECT.size.x - 300, 22)
	_retry_btn.size = Vector2(130, 44)
	_retry_btn.pressed.connect(open)
	_panel.add_child(_retry_btn)

	_close_btn = _button("关闭")
	_close_btn.position = Vector2(PANEL_RECT.size.x - 158, 22)
	_close_btn.size = Vector2(130, 44)
	_close_btn.pressed.connect(close)
	_panel.add_child(_close_btn)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(24, 100)
	_scroll.size = PANEL_RECT.size - Vector2(48, 124)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.x = _scroll.size.x - 24
	_list.add_theme_constant_override("separation", 18)
	_scroll.add_child(_list)


## 清空内容区；loading / 失败 / 渲染三种状态都从这里起步。
func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()


# ------------------------------------------------------------------ 数据入口

func _on_report_ready(report: Dictionary) -> void:
	if not visible:
		return
	_report = report
	_set_status("", false)
	render(report)


func _on_report_failed(reason: String) -> void:
	if not visible:
		return
	_set_status(String(reason), true)


## 渲染整份报告（也供探针直接喂 fixture，不走网络）。
func render(report: Dictionary) -> void:
	_rebuild_list()
	if report.is_empty() or not report.has("layers"):
		_set_status("报告内容为空。", true)
		return
	var persona: Dictionary = report.get("layers", {}).get("persona", {})

	_header(report)
	_section_sketch(persona)
	_section_radar(persona.get("radar", []))
	_section_bigfive(persona.get("bigfive", []))
	_section_topics(persona.get("topics", []))
	_section_promotion(persona.get("promotionTrack", {}))
	_section_hints(report.get("layers", {}).get("crossHints", {}).get("hints", []))


# ------------------------------------------------------------------ 各节渲染

func _header(report: Dictionary) -> void:
	var head := "共 %d 次选择" % int(report.get("decisionCount", 0))
	if report.get("scoringVersion", "") != "":
		head += " · 口径 %s" % String(report["scoringVersion"])
	if report.get("generatedAt", "") != "":
		head += " · 生成于 %s" % String(report["generatedAt"]).replace("T", " ")
	_list.add_child(_card(head, COLOR_SUB, 15))


func _section_sketch(persona: Dictionary) -> void:
	var sketch := String(persona.get("personaSketch", ""))
	if sketch.is_empty():
		return
	_list.add_child(_title("人格速写"))
	_list.add_child(_para(sketch, 20, COLOR_INK))


func _section_radar(rows: Array) -> void:
	if rows.is_empty():
		return
	_list.add_child(_title("能力六柱（按在册事件实算满分归一化）"))
	for row in rows:
		var pillar := String(row.get("pillar", ""))
		var score := int(row.get("score", 0))
		var cap := int(row.get("cap", 0))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var name_label := _label(pillar, 17, COLOR_INK)
		name_label.custom_minimum_size.x = 130
		line.add_child(name_label)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = score
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(560, 22)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.modulate = COLOR_ACCENT
		line.add_child(bar)
		var value := _label("%d / 100" % score, 16, COLOR_SUB)
		value.custom_minimum_size.x = 90
		line.add_child(value)
		var card := _card("", COLOR_INK, 15)
		_card_body(card).add_child(line)
		if cap > 0 and cap < 15:
			_card_text(card).text = "样本机会少（满分上限 %d 分）" % cap
		_list.add_child(card)


func _section_bigfive(rows: Array) -> void:
	if rows.is_empty():
		return
	_list.add_child(_title("性格五维（自评 vs 48 个月的行为）"))
	for row in rows:
		var cn := String(row.get("traitCn", ""))
		var line_text := ""
		if bool(row.get("behaviorAvailable", false)):
			# self/behavior 服务端给的是 0-10 分（数字）；老契约若给档位词也能直接显示。
			line_text = "自评 %s · 行为落在 %s（0-10 分）" % [
				_score_text(row.get("self", "")), _score_text(row.get("behavior", ""))]
			if bool(row.get("conflictSignificant", false)):
				line_text += "　⚠ 自评与行为有显著落差"
		else:
			line_text = "行为证据不足（%d 条），仅供参考" % int(row.get("evidenceCount", 0))
		var note := String(row.get("note", ""))
		var card := _card("%s：%s" % [cn, line_text], COLOR_INK, 16)
		if not note.is_empty():
			_card_text(card).text += "\n" + note
		_list.add_child(card)


## 分数显示：数字 → 一位小数；已经是文字（档位词）→ 原样。
func _score_text(value) -> String:
	if value is float or value is int:
		return "%.1f" % float(value)
	return str(value)


func _section_topics(mods: Array) -> void:
	var shown := 0
	for m in mods:
		if not bool(m.get("displayable", false)):
			continue
		shown += 1
		if shown == 1:
			_list.add_child(_title("行为专题"))
		var card := _card(String(m.get("title", "")), COLOR_INK, 17)
		var body := String(m.get("summary", ""))
		for bullet in (m.get("bullets", []) as Array):
			# 契约里 bullet = {label, value}（如「自主性均值：0.9 / 2」）；兼容纯字符串。
			if bullet is Dictionary:
				body += "\n· %s：%s" % [String((bullet as Dictionary).get("label", "")),
					String((bullet as Dictionary).get("value", ""))]
			else:
				body += "\n· " + str(bullet)
		var detail := _label(body, 15, COLOR_SUB)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_card_body(card).add_child(detail)
		_list.add_child(card)
	if shown == 0:
		_list.add_child(_card("行为专题：这一局的证据还不够下结论——证据不足的话题宁可不说话。", COLOR_SUB, 15))


func _section_promotion(track: Dictionary) -> void:
	var windows: Array = track.get("windows", [])
	var grade: Dictionary = track.get("finalGrade", {})
	if windows.is_empty() and grade.is_empty():
		return
	_list.add_child(_title("晋升轨迹"))
	if not windows.is_empty():
		var chips := ""
		for w in windows:
			var mark := "✓升" if bool(w.get("passed", false)) else "·"
			chips += "第 %d 月 %s　" % [int(w.get("month", 0)), mark]
		_list.add_child(_card(chips.trim_suffix("　"), COLOR_INK, 16))
	if not grade.is_empty():
		var line := "终局：%s（L%d %s）" % [
			String(grade.get("label", "")), int(grade.get("level", 1)), String(grade.get("grade", ""))]
		var extra := String(grade.get("line", ""))
		if not extra.is_empty():
			line += "\n" + extra
		_list.add_child(_card(line, COLOR_INK, 16))


func _section_hints(hints: Array) -> void:
	if hints.is_empty():
		return
	_list.add_child(_title("值得回头看的地方"))
	for h in hints:
		var line := String(h.get("line", ""))
		if line.is_empty():
			continue
		_list.add_child(_card(line, COLOR_INK, 16))


# ------------------------------------------------------------------ 小构件

func _set_status(text: String, show_retry: bool) -> void:
	_status.text = text
	_retry_btn.visible = show_retry


func _title(text: String) -> Label:
	var label := _label(text, 21, COLOR_INK)
	label.custom_minimum_size.y = 30
	return label


func _card(text: String, color: Color, font_size: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.55)
	style.border_color = Color(COLOR_BORDER, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	# PanelContainer 的多个子节点会互相叠住 —— 内容一律装进这层 VBox，
	# 要往卡里追加行就 _card_body(panel).add_child(...)。
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	return panel


## 卡片的内容层（VBox）。第一行是 _card 里的主文案 Label。
func _card_body(card: PanelContainer) -> VBoxContainer:
	return card.get_child(0) as VBoxContainer


## 卡片的主文案。
func _card_text(card: PanelContainer) -> Label:
	return (_card_body(card).get_child(0) as Label)


func _para(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _list.custom_minimum_size.x - 40
	return label


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 17)
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_WOOD
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = COLOR_WOOD.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = COLOR_WOOD.darkened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", COLOR_TITLE)
	return button


func _style(bg: Color, border: Color, margin: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style
