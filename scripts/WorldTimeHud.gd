class_name WorldTimeHud
extends CanvasLayer

signal advance_requested(days: int)

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

var _title: Label
var _date: Label
var _clock: Label
var _next_event: Label

func _ready() -> void:
	layer = 120
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-365, 26)
	panel.size = Vector2(350, 177)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	_title = _label("第一幕 · 进入行业", 18, Color("fff0c9"))
	_title.position = Vector2(18, 12)
	_title.size = Vector2(314, 28)
	panel.add_child(_title)
	_date = _label("第 1 月 1 日", 20, Color("ffe5a8"))
	_date.position = Vector2(18, 46)
	_date.size = Vector2(160, 31)
	panel.add_child(_date)
	_clock = _label("09:00 · 白天", 18, Color("fff8e8"))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.position = Vector2(155, 46)
	_clock.size = Vector2(177, 31)
	panel.add_child(_clock)
	_next_event = _label("主线：第 1 月中旬", 14, Color("f3d59a"))
	_next_event.position = Vector2(18, 81)
	_next_event.size = Vector2(314, 23)
	panel.add_child(_next_event)
	var advance := Button.new()
	advance.text = "推进 5 天"
	advance.position = Vector2(18, 112)
	advance.size = Vector2(314, 47)
	advance.add_theme_font_override("font", FONT)
	advance.add_theme_font_size_override("font_size", 19)
	advance.add_theme_color_override("font_color", Color("fff0c9"))
	advance.add_theme_stylebox_override("normal", _button_style(Color("a34a32")))
	advance.add_theme_stylebox_override("hover", _button_style(Color("c5603e")))
	advance.pressed.connect(func(): advance_requested.emit(5))
	panel.add_child(advance)
	var hint := _label("探索和活动也会推进时间", 13, Color("d5b77b"))
	hint.position = Vector2(18, 161)
	hint.size = Vector2(314, 16)
	panel.add_child(hint)

func set_time(snapshot: Dictionary) -> void:
	if _date == null:
		return
	_date.text = "第 %d 月 %d 日" % [int(snapshot["month"]), int(snapshot["day"])]
	_clock.text = "%s · %s" % [snapshot["clock"], snapshot["phaseName"]]
	var next_event := WorldClock.next_main_event()
	if next_event.is_empty():
		_next_event.text = "第一幕主线事件已完成"
	else:
		_next_event.text = "下一主线：第 %d 月中旬 · %s" % [int(next_event["month"]), next_event["title"]]

func show_event_gate(event: Dictionary) -> void:
	_next_event.text = "主线待完成：%s" % event["title"]

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
