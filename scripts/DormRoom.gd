class_name DormRoom
extends CanvasLayer

## 宿舍：玩家每天出发、每天结束的地方。
##
## 排版（2026-09-16 重做）：左侧「慢生活园」美术图卡片（完整不裁切），
## 右侧信息栏（眉题 / 标题 / 分隔线 / 描述 / 主按钮），暖色羊皮纸系配色。
## 家园装饰系统整体后置（见 docs/家园系统设计说明_V1.md），
## 届时本屏是"宿舍场景 + 陈列层"的底座。
##
## 两种状态：
##   · 平时    —— 唯一选项「离开宿舍」，点了出门开始一天
##   · 23:00 后 —— 唯一选项「睡觉」，点了直接睡到第二天早上

signal leave_requested
signal sleep_requested

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
## 美术交付宿舍图后填这里（留空 = 纯黑屏）。
## 2026-09-16：接「慢生活园」整图当宿舍背景。家园装饰系统后置，
## 届时玩家房间需美术出空房版再分层（设计说明 §3）。
const DORM_IMAGE_PATH := "res://assets/town/dorm_slow_life.jpg"
const CURFEW_HOUR := 23
const WAKE_UP_HOUR := 7

## 配色（与记忆墙/手册同一羊皮纸系）
const INK_BG := Color("0b0812")
const CARD_BG := Color("14100c")
const CARD_BORDER := Color("4a2619")
const PARCHMENT := Color("f6e6c2")
const PARCHMENT_SOFT := Color("e8d3ac")
const KICKER := Color("c9a97a")
const ACCENT := Color("9f4c36")
const ACCENT_HOVER := Color("bf6241")
const OUTLINE := Color("23170f")

## 左侧图卡与右侧信息栏的版面基准（1920×1080）
const CARD_RECT := Rect2(100, 70, 960, 940)
const CARD_PAD := 18.0
const COL_X := 1160.0
const COL_W := 660.0

var _root: Control
var _photo: TextureRect
var _kicker: Label
var _title: Label
var _desc: Label
var _button: Button
var _curfew := false


func _ready() -> void:
	layer = 110
	name = "DormRoom"
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = INK_BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	_build_photo_card()
	_build_text_column()

	_root.hide()


## 左侧：圆角卡片包住整张宿舍图（KEEP_ASPECT_CENTERED，不再裁上下）。
func _build_photo_card() -> void:
	var card := Panel.new()
	card.position = CARD_RECT.position
	card.size = CARD_RECT.size
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = CARD_BG
	card_style.border_color = CARD_BORDER
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card_style.shadow_color = Color(0, 0, 0, 0.45)
	card_style.shadow_size = 22
	card_style.shadow_offset = Vector2(0, 6)
	card.add_theme_stylebox_override("panel", card_style)
	_root.add_child(card)

	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo.position = Vector2(CARD_PAD, CARD_PAD)
	_photo.size = CARD_RECT.size - Vector2(CARD_PAD, CARD_PAD) * 2.0
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.texture = _load_texture(DORM_IMAGE_PATH)
	card.add_child(_photo)


## 右侧：眉题 → 标题 → 分隔线 → 描述 → 主按钮，整体在信息栏垂直居中。
func _build_text_column() -> void:
	_kicker = _label("H 区 · 员工宿舍", 20, KICKER, 0)
	_kicker.position = Vector2(COL_X, 296)
	_kicker.size = Vector2(COL_W, 34)
	_root.add_child(_kicker)

	_title = _label("慢生活园", 56, PARCHMENT, 5)
	_title.position = Vector2(COL_X, 338)
	_title.size = Vector2(COL_W, 84)
	_root.add_child(_title)

	var divider := ColorRect.new()
	divider.color = ACCENT
	divider.position = Vector2(COL_X + 2, 444)
	divider.size = Vector2(140, 3)
	_root.add_child(divider)

	_desc = _label("", 22, PARCHMENT_SOFT, 2)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size = Vector2(COL_W - 20, 150)
	_desc.position = Vector2(COL_X, 486)
	_root.add_child(_desc)

	_button = Button.new()
	_button.position = Vector2(COL_X, 672)
	_button.size = Vector2(460, 100)
	_button.add_theme_font_override("font", FONT)
	_button.add_theme_font_size_override("font_size", 26)
	_button.add_theme_color_override("font_color", Color("fff4d4"))
	_button.add_theme_color_override("font_hover_color", Color("fff8e0"))
	_button.add_theme_stylebox_override("normal", _button_style(ACCENT))
	_button.add_theme_stylebox_override("hover", _button_style(ACCENT_HOVER))
	_button.add_theme_stylebox_override("pressed", _button_style(Color("7e3c2a")))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.pressed.connect(_on_button_pressed)
	_root.add_child(_button)


func present(curfew: bool) -> void:
	_curfew = curfew
	_refresh()
	_root.show()


func dismiss() -> void:
	_root.hide()


func is_open() -> bool:
	return _root != null and _root.visible


func is_curfew() -> bool:
	return _curfew


func _refresh() -> void:
	# 宵禁时给画面压一层夜色，让"该睡了"先被看见再被读到。
	_photo.modulate = Color(0.72, 0.78, 0.95) if _curfew else Color.WHITE
	if _curfew:
		_kicker.text = "%02d:00 · 宵禁" % CURFEW_HOUR
		_title.text = "该回宿舍了"
		_desc.text = "宿舍 %02d:00 关门，再晚就只能睡走廊了。\n今天到此为止，早点休息，明天 %02d:00 再出门。" % [CURFEW_HOUR, WAKE_UP_HOUR]
		_button.text = "睡觉  ·  次日 %02d:00 出门" % WAKE_UP_HOUR
	else:
		_kicker.text = "H 区 · 员工宿舍"
		_title.text = "慢生活园"
		_desc.text = "你在这里开始一天，也在这里结束一天。\n记住：晚上 %02d:00 之前必须回到宿舍。" % CURFEW_HOUR
		_button.text = "离开宿舍"


func _on_button_pressed() -> void:
	if _curfew:
		sleep_requested.emit()
	else:
		leave_requested.emit()


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var imported := load(path) as Texture2D
	if imported != null:
		return imported
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _label(value: String, font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	return label


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = CARD_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	return style
