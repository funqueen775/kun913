class_name WorldTimeHud
extends CanvasLayer

## 右上角时间面板：以「时段」为单位显示一天的进度（早上 → 上班后 → 下班 → 夜晚）。
## 2026-09-16：「推进到下月」按钮已删除 —— 时间不再由玩家手动跳。
## 2026-09-17（24 件基准拍板 #7）：时间推进双驱动 = 睡觉跨天 + 主线事件结算推进一拍；
## 养成行动（月度 3 点精力）不再承担推进职责。

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
## 一天的时段数，与 WorldClock.PHASES 一一对应（进度点用它铺）。
const PHASE_COUNT := 4

var _title: Label
var _date: Label
var _clock: Label
var _phase: Label
var _progress: Label
var _next_event: Label

func _ready() -> void:
	layer = 120
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-365, 26)
	# 2026-09-17 UI 打磨两轮：用户反馈「字太小」，字号再上调一档，面板加高到 208
	# （设计分辨率 1920×1080，窗口 1280×720 下还会缩 0.667，字要够大才可读）；
	# 下面依次是功能圆钮排（y 250）与精力条（y 334），间距见 WorkplaceTown._build_hud_button_row。
	panel.size = Vector2(350, 208)
	panel.add_theme_stylebox_override("panel", _panel_style())
	# 面板现在纯展示、没有可点的按钮了：放行鼠标，别挡住右上角的地图拖动/缩放。
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_title = _label("第一幕 · 进入行业", 24, Color("fff0c9"))
	_title.position = Vector2(18, 12)
	_title.size = Vector2(314, 32)
	panel.add_child(_title)
	# 用户拍板（2026-09-17）：日期不显示「日」，只留「第 N 月」。
	_date = _label("第 1 月", 26, Color("ffe5a8"))
	_date.position = Vector2(18, 52)
	_date.size = Vector2(220, 36)
	panel.add_child(_date)
	_clock = _label("07:00", 24, Color("fff8e8"))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.position = Vector2(234, 52)
	_clock.size = Vector2(98, 36)
	panel.add_child(_clock)
	# 当前时段 + 今天走到第几拍：进度点用实心/空心区分已过与未到。
	_phase = _label("早上", 25, Color("ffd98a"))
	_phase.position = Vector2(18, 96)
	_phase.size = Vector2(180, 32)
	panel.add_child(_phase)
	_progress = _label("●○○○", 22, Color("fff0c9"))
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress.position = Vector2(168, 96)
	_progress.size = Vector2(164, 32)
	panel.add_child(_progress)
	_next_event = _label("主线：第 1 月初", 19, Color("f3d59a"))
	_next_event.position = Vector2(18, 136)
	_next_event.size = Vector2(314, 28)
	# 事件标题可能很长（「下一主线：第 16 月 · 连续加班后心悸」），超宽裁剪省略。
	_next_event.clip_text = true
	_next_event.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	panel.add_child(_next_event)
	var hint := _label("睡觉跨天 · 主线结算推进时间", 17, Color("d5b77b"))
	hint.position = Vector2(18, 170)
	hint.size = Vector2(314, 24)
	panel.add_child(hint)

func set_time(snapshot: Dictionary) -> void:
	if _date == null:
		return
	# 只显示月份（用户拍板：不要「日」）。
	_date.text = "第 %d 月" % int(snapshot["month"])
	_clock.text = String(snapshot["clock"])
	var phase_index := int(snapshot.get("phaseIndex", 0))
	_phase.text = String(snapshot.get("phaseName", ""))
	var marks := ""
	for i in PHASE_COUNT:
		marks += "●" if i <= phase_index else "○"
	_progress.text = marks
	var next_event := WorldClock.next_main_event()
	if next_event.is_empty():
		_next_event.text = "第一幕主线事件已完成"
	else:
		_next_event.text = "下一主线：第 %d 月 · %s" % [int(next_event["month"]), next_event["title"]]

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
