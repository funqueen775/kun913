extends CanvasLayer
## 设置弹窗（2026-09-17 UI 打磨批次）。
## 入口：右上角「设置」圆钮。职责：操作说明 + 继续游戏 / 退出游戏。
## 风格基线：暖木底 + 金边圆角大卡 + 入场缩放/淡入 + 按压回弹 + 点背景/ESC 关闭。
## 之后要把别的弹窗统一成这套质感时，照这里抄。
## 刻意不引用任何 autoload（WorldClock / ApiClient）：探针可以直接 new 出来测。

signal settings_closed()
signal quit_requested()

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

const COLOR_BACKDROP := Color(0.02, 0.03, 0.06, 0.55)
## 暖木主色 54321f（带 0.985 透明度，压在夜景上也不发闷）。
const COLOR_BG := Color(0.329, 0.196, 0.122, 0.985)
const COLOR_BORDER := Color("d49a4c")
const COLOR_TITLE := Color("ffe5a8")
const COLOR_TEXT := Color("fff0c9")
const COLOR_SUB := Color("d5b77b")
const COLOR_CHIP := Color("ef9f27")
const COLOR_CHIP_TEXT := Color("3a2410")
const COLOR_LINE := Color(0.831, 0.604, 0.298, 0.35)
const COLOR_PRIMARY := Color("ef9f27")
const COLOR_PRIMARY_HOVER := Color("ffb548")
const COLOR_PRIMARY_PRESSED := Color("d98a1a")
const COLOR_DANGER_TEXT := Color("ffb09a")
const COLOR_DANGER_BORDER := Color("c96b4a")

const CARD_SIZE := Vector2(560, 500)

## 操作说明四行（键位 chip + 说明文字）。
const KEY_ROWS := [
	{"chip": "走", "text": "移动：WASD / 方向键 / 左下摇杆"},
	{"chip": "E", "text": "互动：交谈 · 进出区域 · 宿舍门口与床边"},
	{"chip": "Q", "text": "返回小镇（在建筑里时）"},
	{"chip": "滚", "text": "地图缩放：滚轮 / ± / 双指捏合 · 按住拖动平移"},
]

var _root: Control
var _dim: ColorRect
var _card: Panel
var _open_flag := false
var _tween: Tween


func _ready() -> void:
	layer = 200
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = COLOR_BACKDROP
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 背景点击关闭交给 center 的 gui_input；这里放行，别把点击吞在 dim 上。
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.gui_input.connect(_on_center_gui_input)
	_root.add_child(center)
	_card = Panel.new()
	_card.custom_minimum_size = CARD_SIZE
	_card.size = CARD_SIZE
	_card.add_theme_stylebox_override("panel", _card_style())
	center.add_child(_card)
	_build_content()


func open() -> void:
	if _open_flag:
		return
	_open_flag = true
	_root.visible = true
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.pivot_offset = CARD_SIZE / 2.0
	_card.scale = Vector2(0.92, 0.92)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_dim, "modulate:a", 1.0, 0.18)
	_tween.tween_property(_card, "modulate:a", 1.0, 0.22)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _open_flag:
		return
	_open_flag = false
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_dim, "modulate:a", 0.0, 0.16)
	_tween.tween_property(_card, "modulate:a", 0.0, 0.16)
	_tween.tween_property(_card, "scale", Vector2(0.94, 0.94), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_hide_root)
	settings_closed.emit()


func is_open() -> bool:
	return _open_flag


func _unhandled_input(event: InputEvent) -> void:
	if not _open_flag:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## ---------- 内容搭建 ----------

func _build_content() -> void:
	var title_font := FontVariation.new()
	title_font.base_font = FONT
	title_font.variation_embolden = 0.5

	var title := _label("设置", 30, COLOR_TITLE)
	title.position = Vector2(32, 24)
	title.size = Vector2(220, 44)
	title.add_theme_font_override("font", title_font)
	_card.add_child(title)

	# 标题下的金色小短条：一眼把「标题区」和「内容区」分开。
	var underline := Panel.new()
	underline.position = Vector2(34, 74)
	underline.size = Vector2(56, 4)
	var underline_style := StyleBoxFlat.new()
	underline_style.bg_color = COLOR_CHIP
	underline_style.set_corner_radius_all(2)
	underline.add_theme_stylebox_override("panel", underline_style)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(underline)

	var subtitle := _label("熊心壮职 · 职业测评小镇", 14, COLOR_SUB)
	subtitle.position = Vector2(104, 66)
	subtitle.size = Vector2(300, 24)
	_card.add_child(subtitle)

	var close_button := _make_circle_close_button()
	close_button.position = Vector2(CARD_SIZE.x - 40.0 - 22.0, 22)
	close_button.pressed.connect(close)
	_card.add_child(close_button)

	var section := _label("操作方式", 17, COLOR_TITLE)
	section.position = Vector2(32, 116)
	section.size = Vector2(220, 28)
	section.add_theme_font_override("font", title_font)
	_card.add_child(section)

	for i in KEY_ROWS.size():
		var row: Dictionary = KEY_ROWS[i]
		var y := 156.0 + 48.0 * i
		var chip := Panel.new()
		chip.position = Vector2(32, y)
		chip.size = Vector2(34, 34)
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = COLOR_CHIP
		chip_style.set_corner_radius_all(17)
		chip.add_theme_stylebox_override("panel", chip_style)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(chip)
		var chip_label := _label(String(row["chip"]), 17, COLOR_CHIP_TEXT)
		chip_label.position = Vector2(0, 0)
		chip_label.size = Vector2(34, 34)
		chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(chip_label)
		var text := _label(String(row["text"]), 17, COLOR_TEXT)
		text.position = Vector2(82, y + 1)
		text.size = Vector2(446, 32)
		_card.add_child(text)

	var divider := ColorRect.new()
	divider.color = COLOR_LINE
	divider.position = Vector2(32, 366)
	divider.size = Vector2(CARD_SIZE.x - 64.0, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(divider)

	var resume_button := Button.new()
	resume_button.position = Vector2(32, 388)
	resume_button.size = Vector2(316, 56)
	resume_button.text = "继续游戏"
	resume_button.add_theme_font_override("font", title_font)
	resume_button.add_theme_font_size_override("font_size", 20)
	resume_button.add_theme_color_override("font_color", COLOR_CHIP_TEXT)
	resume_button.add_theme_color_override("font_hover_color", COLOR_CHIP_TEXT)
	resume_button.add_theme_color_override("font_pressed_color", COLOR_CHIP_TEXT)
	resume_button.add_theme_stylebox_override("normal", _button_style(COLOR_PRIMARY, COLOR_PRIMARY, 14))
	resume_button.add_theme_stylebox_override("hover", _button_style(COLOR_PRIMARY_HOVER, COLOR_PRIMARY_HOVER, 14))
	resume_button.add_theme_stylebox_override("pressed", _button_style(COLOR_PRIMARY_PRESSED, COLOR_PRIMARY_PRESSED, 14))
	resume_button.pivot_offset = resume_button.size / 2.0
	resume_button.pressed.connect(_on_button_press.bind(resume_button))
	_card.add_child(resume_button)

	var quit_button := Button.new()
	quit_button.position = Vector2(364, 388)
	quit_button.size = Vector2(164, 56)
	quit_button.text = "退出游戏"
	quit_button.add_theme_font_override("font", title_font)
	quit_button.add_theme_font_size_override("font_size", 20)
	quit_button.add_theme_color_override("font_color", COLOR_DANGER_TEXT)
	quit_button.add_theme_color_override("font_hover_color", Color("ffd0c0"))
	quit_button.add_theme_color_override("font_pressed_color", COLOR_DANGER_TEXT)
	quit_button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.05, 0.04, 0.4), COLOR_DANGER_BORDER, 14))
	quit_button.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.08, 0.05, 0.6), Color("e8896b"), 14))
	quit_button.add_theme_stylebox_override("pressed", _button_style(Color(0.05, 0.03, 0.02, 0.6), COLOR_DANGER_BORDER, 14))
	quit_button.pivot_offset = quit_button.size / 2.0
	quit_button.pressed.connect(_on_button_press.bind(quit_button))
	quit_button.pressed.connect(func(): quit_requested.emit())
	_card.add_child(quit_button)

	var footer := _label("精力每月初发 3 点、不可结转；23:00 宵禁，记得回宿舍。", 13, COLOR_SUB)
	footer.position = Vector2(32, 458)
	footer.size = Vector2(CARD_SIZE.x - 64.0, 24)
	_card.add_child(footer)


func _make_circle_close_button() -> Button:
	var button := Button.new()
	button.size = Vector2(40, 40)
	button.text = "×"
	button.tooltip_text = "关闭"
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", COLOR_SUB)
	button.add_theme_color_override("font_hover_color", COLOR_TITLE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0.18), Color(0.831, 0.604, 0.298, 0.4), 20))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.42, 0.25, 0.15, 0.9), COLOR_BORDER, 20))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.28, 0.16, 0.09, 0.9), COLOR_BORDER, 20))
	button.pivot_offset = button.size / 2.0
	button.pressed.connect(_on_button_press.bind(button))
	return button


## 点背景（卡片外）关闭。
func _on_center_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## 按压回弹：scale 1 → 0.94 → 1（旋转中心在控件中心）。
func _on_button_press(button: Button) -> void:
	button.pivot_offset = button.size / 2.0
	var bounce := create_tween()
	bounce.tween_property(button, "scale", Vector2(0.94, 0.94), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(button, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## ---------- 样式工具 ----------

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 26
	return style


func _button_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _hide_root() -> void:
	_root.visible = false
