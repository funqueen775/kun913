class_name StoryEventPanel
extends CanvasLayer

signal choice_confirmed(event_id: String, choice_id: String, duration_minutes: int)
signal decision_opened(event_id: String)
signal choice_hovered(event_id: String, choice_id: String)

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

var _root: Control
var _event: Dictionary = {}
var _stage := "closed"


func _ready() -> void:
	layer = 150
	_root = Control.new()
	_root.name = "EventOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.hide()


func present(event: Dictionary) -> void:
	_event = event.duplicate(true)
	decision_opened.emit(String(_event.get("id", "")))
	_show_intro()


func dismiss() -> void:
	_stage = "closed"
	_root.hide()


func is_open() -> bool:
	return _root != null and _root.visible


func current_stage() -> String:
	return _stage


func _show_intro() -> void:
	_clear_content()
	_stage = "intro"
	_add_dim_background()
	var panel := Panel.new()
	panel.name = "StoryIntro"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-490, -315)
	panel.size = Vector2(980, 630)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("f6dfad"), Color("694027"), 6))
	_root.add_child(panel)
	var chapter := _label("第一幕 · 进入行业", 19, Color("8a5635"))
	chapter.position = Vector2(70, 48)
	chapter.size = Vector2(840, 30)
	panel.add_child(chapter)
	var location := String(_event.get("location", "%s 区" % _event.get("locationId", "")))
	var title := _label("%s  ·  %s" % [_event.get("title", "主线事件"), location], 36, Color("452919"))
	title.position = Vector2(70, 90)
	title.size = Vector2(840, 55)
	panel.add_child(title)
	var divider := ColorRect.new()
	divider.color = Color("b67b48")
	divider.position = Vector2(70, 158)
	divider.size = Vector2(840, 3)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)
	var story := _label(String(_event.get("story", "事件内容待补充。")), 25, Color("4a3324"))
	story.position = Vector2(70, 185)
	story.size = Vector2(840, 205)
	panel.add_child(story)
	var continue_button := Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "点击继续"
	continue_button.position = Vector2(70, 455)
	continue_button.size = Vector2(840, 82)
	_style_button(continue_button, 24)
	continue_button.pressed.connect(_show_choices, CONNECT_DEFERRED)
	panel.add_child(continue_button)
	var hint := _label(String(_event.get("hint", "点击继续查看行动选项")), 16, Color("8a6543"))
	hint.position = Vector2(70, 548)
	hint.size = Vector2(840, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)
	_root.show()


func _show_choices() -> void:
	_clear_content()
	_stage = "choices"
	_add_dim_background()
	var panel := Panel.new()
	panel.name = "StoryChoices"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-490, -340)
	panel.size = Vector2(980, 680)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("f6dfad"), Color("694027"), 6))
	_root.add_child(panel)
	var title := _label(String(_event.get("title", "主线事件")), 34, Color("452919"))
	title.position = Vector2(70, 45)
	title.size = Vector2(840, 52)
	panel.add_child(title)
	var prompt := _label(String(_event.get("prompt", "你会如何选择？")), 23, Color("6b432b"))
	prompt.position = Vector2(70, 115)
	prompt.size = Vector2(840, 42)
	panel.add_child(prompt)
	var choices: Array = _event.get("choices", [])
	for index in mini(choices.size(), 3):
		var choice: Dictionary = choices[index]
		_add_choice(panel, String(choice.get("id", "option_%d" % index)), String(choice.get("text", "")), 190.0 + index * 115.0)
	_root.show()


func _add_choice(panel: Panel, choice_id: String, text: String, y: float) -> void:
	var button := Button.new()
	button.name = "Choice_%s" % choice_id
	button.text = text
	button.position = Vector2(70, y)
	button.size = Vector2(840, 86)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_button(button, 20)
	var event_id := String(_event.get("id", ""))
	var duration_minutes := int(_event.get("durationMinutes", 45))
	button.mouse_entered.connect(func(): choice_hovered.emit(event_id, choice_id))
	button.pressed.connect(func(): choice_confirmed.emit(event_id, choice_id, duration_minutes))
	panel.add_child(button)


func _clear_content() -> void:
	for child in _root.get_children():
		child.free()


func _add_dim_background() -> void:
	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.03, 0.05, 0.08, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)


func _style_button(button: Button, font_size: int) -> void:
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color("fff4d4"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color("9f4c36"), Color("5a301f"), 4))
	button.add_theme_stylebox_override("hover", _panel_style(Color("bf6241"), Color("402316"), 4))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("7e3829"), Color("402316"), 4))


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _panel_style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 18
	style.content_margin_right = 18
	return style
