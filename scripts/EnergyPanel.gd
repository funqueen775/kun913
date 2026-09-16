extends CanvasLayer
## 精力面板：每月 3 点精力的四方向分配（专业成长/工作产出/人际经营/休息恢复），
## 附公开数值行（专业能力/生命/产出/金钱）与月底结算反馈。
## 数值口径见 scripts/MonthlyLife.gd 头注释。布局风格对齐 WorldTimeHud。

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

## 按钮顺序 = 机制文档 §4.1 的四个行动方向。
const ACTIONS := [
	{"id": "grow", "label": "专业成长"},
	{"id": "produce", "label": "工作产出"},
	{"id": "social", "label": "人际经营"},
	{"id": "rest", "label": "休息恢复"},
]

var _life
var _pips: Label
var _status: Label
var _feedback: Label
var _buttons: Array[Button] = []
## 结算文案只在「变化的那一次」刷新到反馈栏，避免覆盖玩家刚点下的行动反馈。
var _seen_settlement := ""


func setup(life) -> void:
	_life = life
	if _life.has_signal("state_changed"):
		_life.state_changed.connect(_refresh)


func _ready() -> void:
	layer = 121
	# UI 建完再刷一次：setup 可能发生在 add_child 之前，那时控件还没建。
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-365, 215)
	panel.size = Vector2(350, 216)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var title := _label("本月精力", 16, Color("fff0c9"))
	title.position = Vector2(18, 10)
	title.size = Vector2(160, 24)
	panel.add_child(title)

	_pips = _label("●●●", 16, Color("ffe5a8"))
	_pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pips.position = Vector2(172, 10)
	_pips.size = Vector2(160, 24)
	panel.add_child(_pips)

	_status = _label("", 13, Color("fff8e8"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 314
	_status.position = Vector2(18, 36)
	_status.size = Vector2(314, 20)
	panel.add_child(_status)

	for i in ACTIONS.size():
		var action: Dictionary = ACTIONS[i]
		var button := Button.new()
		button.text = String(action["label"])
		button.position = Vector2(18 + (i % 2) * 161, 62 + (i / 2) * 44)
		button.size = Vector2(153, 38)
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", Color("fff0c9"))
		button.add_theme_stylebox_override("normal", _button_style(Color("7a4630")))
		button.add_theme_stylebox_override("hover", _button_style(Color("a35a3a")))
		button.add_theme_stylebox_override("disabled", _button_style(Color("4a3327")))
		var action_id := String(action["id"])
		button.pressed.connect(func(): _on_action_pressed(action_id))
		panel.add_child(button)
		_buttons.append(button)

	_feedback = _label("主线不耗精力。1 点精力只做一件事，月底产出折算奖金。", 12, Color("d5b77b"))
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.x = 314
	_feedback.max_lines_visible = 3
	_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback.position = Vector2(18, 152)
	_feedback.size = Vector2(314, 56)
	panel.add_child(_feedback)


func _on_action_pressed(action_id: String) -> void:
	if _life == null:
		return
	var result: Dictionary = _life.spend_energy(action_id)
	_feedback.text = String(result.get("text", ""))
	_refresh()


func _refresh() -> void:
	if _life == null or _pips == null:
		return
	var state: Dictionary = _life.snapshot()
	var energy := int(state["energy"])
	var filled := ""
	for i in int(state["energyMax"]):
		filled += "● " if i < energy else "○ "
	_pips.text = filled.strip_edges()
	_status.text = "专业能力 %d · 生命 %d/%d · 产出 %d · 金钱 ¥%d" % [
		int(state["skill"]), int(state["health"]), int(state["healthMax"]),
		int(state["output"]), int(state["money"]),
	]
	var settlement := String(_life.last_settlement)
	if settlement != _seen_settlement:
		_seen_settlement = settlement
		_feedback.text = settlement
	for button in _buttons:
		button.disabled = energy <= 0


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("23170f"))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("54321f", 0.92)
	style.border_color = Color("d49a4c")
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := _panel_style()
	style.bg_color = color
	style.border_color = Color("4a2619")
	return style
