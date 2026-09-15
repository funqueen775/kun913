class_name DormRoom
extends CanvasLayer

## 宿舍：玩家每天出发、每天结束的地方。
##
## 美术的宿舍图还没交付，所以现在整屏是纯黑的，只留**一个**可点的按钮。
## 等图到了只要做一件事：把 DORM_IMAGE_PATH 填成图片路径。
## 填了之后黑屏自动变成宿舍背景，标题/描述/按钮的位置一个都不用动。
##
## 两种状态：
##   · 平时    —— 唯一选项「离开宿舍」，点了出门开始一天
##   · 23:00 后 —— 唯一选项「睡觉」，点了直接睡到第二天早上

signal leave_requested
signal sleep_requested

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
## 美术交付宿舍图后填这里（留空 = 纯黑屏）。
const DORM_IMAGE_PATH := ""
const CURFEW_HOUR := 23
const WAKE_UP_HOUR := 7

var _root: Control
var _photo: TextureRect
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
	backdrop.color = Color("05070c")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.texture = _load_texture(DORM_IMAGE_PATH)
	_root.add_child(_photo)

	_title = _label("宿舍", 44, Color("f6e6c2"), 4)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.size = Vector2(1100, 84)
	_title.position = Vector2(-550, -170)
	_root.add_child(_title)

	_desc = _label("", 22, Color("e8d3ac"), 3)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.set_anchors_preset(Control.PRESET_CENTER)
	_desc.size = Vector2(1040, 150)
	_desc.position = Vector2(-520, -60)
	_root.add_child(_desc)

	_button = Button.new()
	_button.set_anchors_preset(Control.PRESET_CENTER)
	_button.size = Vector2(460, 100)
	_button.position = Vector2(-230, 90)
	_button.add_theme_font_override("font", FONT)
	_button.add_theme_font_size_override("font_size", 26)
	_button.add_theme_color_override("font_color", Color("fff4d4"))
	_button.add_theme_stylebox_override("normal", _button_style(Color("9f4c36")))
	_button.add_theme_stylebox_override("hover", _button_style(Color("bf6241")))
	_button.pressed.connect(_on_button_pressed)
	_root.add_child(_button)

	_root.hide()


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
	if _curfew:
		_title.text = "%02d:00 · 该回宿舍了" % CURFEW_HOUR
		_desc.text = "宿舍 %02d:00 关门，再晚就只能睡走廊了。\n今天到此为止，早点休息，明天 %02d:00 再出门。" % [CURFEW_HOUR, WAKE_UP_HOUR]
		_button.text = "睡觉  ·  次日 %02d:00 出门" % WAKE_UP_HOUR
	else:
		_title.text = "H 区 · 慢生活园 · 你的宿舍"
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
	label.add_theme_color_override("font_outline_color", Color("23170f"))
	label.add_theme_constant_override("outline_size", outline)
	return label


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("4a2619")
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	return style
