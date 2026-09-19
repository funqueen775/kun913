extends CanvasLayer
## 周末活动 · 到达演出面板（2026-09-18 晚新链路，弹丸论外式）：
## 玩家按计划走到目的区进门 → 全屏场景图 + 底部对话框逐字演出「做了什么、什么感受」。
## 交互：点击 / E / 空格 / 回车逐条推进；正在打字时先一键补全，再点才翻页；
## 最后一条演完自动收起并 emit finished（由 WorkplaceTown 接 FreeTimePanel 结算）。
## 人物立绘先不做（用户拍板）：后续叠加在同一段代码里，不动结构。
## 红线：不引用 autoload（探针直接 new）；文案零数字流水（手账红线同源）。

signal finished

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
## 打字机节奏与 StoryEventPanel 保持一致（0.022s × 2 字符/拍）。
const TYPE_INTERVAL := 0.022
## 弹丸论外式演出（2026-09-18 用户对照参考图拍板）：
## 底部一条**近全宽的实心黑条** + **大白字**，占画面下沿 ~1/4，
## 字要有存在感，不能是窄窄一条半透明 HUD。
const COLOR_DIALOG_BG := Color(0.0, 0.0, 0.0, 0.94)
const COLOR_DIALOG_BORDER := Color(1.0, 1.0, 1.0, 0.18)
const COLOR_TEXT := Color(1.0, 1.0, 1.0)
const COLOR_SUB := Color(0.72, 0.72, 0.72)
## 对话框字号：1080p 下 32px 才有 galgame 台词的分量。
const DIALOG_FONT_SIZE := 32
const DIALOG_HEIGHT := 252.0

var _config: Dictionary = {}
var _lines: Array = []
var _line_index := -1
var _active := false

var _root: Control
var _image_rect: TextureRect
var _title_label: Label
var _dialog_label: Label
var _hint_label: Label
var _typewriter_full := ""
var _typewriter_shown := 0
var _typewriter_timer: Timer


func _ready() -> void:
	layer = 160
	visible = false
	_build_ui()


## config: {title: String, image: String(res 路径), lines: Array, who: String}
## lines 每行可为字符串（沿用默认 image）或 {text, image}（推进到该行时换图）。
func present(config: Dictionary) -> void:
	_config = config
	var lines = config.get("lines", [])
	_lines = lines if lines is Array else []
	_line_index = -1
	_active = true
	_title_label.text = String(config.get("title", ""))
	_image_rect.texture = null
	_apply_image(String(config.get("image", "")))
	visible = true
	_advance()


## 换背景图：优先走导入纹理，没导入（.import 缺失）直接读盘兜底。
func _apply_image(path: String) -> void:
	if path.is_empty():
		return
	var tex = null
	# 先查 exists 再 load（2026-09-18 深夜）：新图没有 .import 时 load() 会打
	# 「No loader found」的 USER ERROR 进日志；exists 对未导入资源返回 false，
	# 直接走读盘兜底，日志干净。
	if ResourceLoader.exists(path):
		tex = load(path)
	if not (tex is Texture2D):
		# 兜底：新图还没被编辑器导入时直接读盘，
		# headless 探针与本机文件锁环境下也能出图；导入完成后走压缩纹理。
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	if tex is Texture2D:
		_image_rect.texture = tex


func is_open() -> bool:
	return _active


func _finish() -> void:
	_active = false
	visible = false
	_image_rect.texture = null
	finished.emit()


## ---------- 推进 ----------

func _advance() -> void:
	if not _active:
		return
	# 正在打字 → 先一键补全（galgame 惯例：第一下补全，第二下翻页）。
	if _typewriter_shown < _typewriter_full.length():
		_typewriter_shown = _typewriter_full.length()
		_dialog_label.text = _typewriter_full
		_typewriter_timer.stop()
		return
	_line_index += 1
	if _line_index >= _lines.size():
		_finish()
		return
	var entry = _lines[_line_index]
	if entry is Dictionary:
		_apply_image(String(entry.get("image", "")))
	_start_typewriter(_line_text(_line_index))


## 单行文案：行可为字符串或 {text, image}；{who} → 同行者显示名，拿不到名字兜底「同伴」。
func _line_text(index: int) -> String:
	var entry = _lines[index]
	var text := String(entry.get("text", "")) if entry is Dictionary else String(entry)
	var who := String(_config.get("who", ""))
	if who.is_empty():
		who = "同伴"
	return text.replace("{who}", who)


func _start_typewriter(text: String) -> void:
	_typewriter_full = text
	_typewriter_shown = 0
	_dialog_label.text = ""
	_typewriter_timer.start()


func _tick_typewriter() -> void:
	if not _active:
		_typewriter_timer.stop()
		return
	_typewriter_shown = mini(_typewriter_shown + 2, _typewriter_full.length())
	_dialog_label.text = _typewriter_full.substr(0, _typewriter_shown)
	if _typewriter_shown >= _typewriter_full.length():
		_typewriter_timer.stop()


## ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
			_advance()
			get_viewport().set_input_as_handled()


## ---------- UI ----------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_image_rect = TextureRect.new()
	_image_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_image_rect)

	_title_label = Label.new()
	_title_label.position = Vector2(34, 22)
	_title_label.size = Vector2(1200, 40)
	_title_label.add_theme_font_override("font", FONT)
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_title_label.add_theme_constant_override("outline_size", 6)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_label)

	var dialog_panel := Panel.new()
	dialog_panel.anchor_left = 0.0
	dialog_panel.anchor_right = 1.0
	dialog_panel.anchor_top = 1.0
	dialog_panel.anchor_bottom = 1.0
	# 近全宽：左右只留一窄边，让黑条横贯整个下沿（弹丸论外式）。
	dialog_panel.offset_left = 24.0
	dialog_panel.offset_right = -24.0
	dialog_panel.offset_top = -DIALOG_HEIGHT
	dialog_panel.offset_bottom = -24.0
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DIALOG_BG
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.border_color = COLOR_DIALOG_BORDER
	dialog_panel.add_theme_stylebox_override("panel", style)
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dialog_panel)

	_dialog_label = Label.new()
	_dialog_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_label.offset_left = 40.0
	_dialog_label.offset_right = -40.0
	_dialog_label.offset_top = 28.0
	_dialog_label.offset_bottom = -56.0
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_dialog_label.add_theme_font_override("font", FONT)
	_dialog_label.add_theme_font_size_override("font_size", DIALOG_FONT_SIZE)
	_dialog_label.add_theme_color_override("font_color", COLOR_TEXT)
	_dialog_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog_panel.add_child(_dialog_label)

	_hint_label = Label.new()
	_hint_label.text = "点击继续 ▼"
	_hint_label.anchor_left = 1.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -140.0
	_hint_label.offset_right = -18.0
	_hint_label.offset_top = -46.0
	_hint_label.offset_bottom = -22.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_override("font", FONT)
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", COLOR_SUB)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog_panel.add_child(_hint_label)

	_typewriter_timer = Timer.new()
	_typewriter_timer.wait_time = TYPE_INTERVAL
	_typewriter_timer.timeout.connect(_tick_typewriter)
	add_child(_typewriter_timer)


func _on_root_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		get_viewport().set_input_as_handled()
