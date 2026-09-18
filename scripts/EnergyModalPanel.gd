extends CanvasLayer
## 「本月精力」居中模态弹窗（2026-09-17 用户拍板：整个精力模块收敛成一颗圆钮 + 弹窗）。
## 入口：右上角「精力」圆钮。职责：看本月剩余点数 + 选一件事花 1 点。
## 风格基线同 SettingsPanel（暖木金边圆角大卡 + 入场缩放/淡入 + 点背景/ESC 关闭）。
## 刻意不引用任何 autoload（WorldClock / ApiClient）：探针可以直接 new 出来测；
## 停钟由 WorkplaceTown 在 open/close 回调里做，本面板只管自己的显示与消费。
## 花掉最后 1 点时弹窗自动关闭：energy_exhausted 信号让 WorkplaceTown 弹顶部横幅
## （2026-09-17 晚拍板：只提示，不跳 22:00），弹窗不挡那场演出。
## 主线门禁（2026-09-17 晚拍板）：当月主线没过完 → 四张动作卡整体置灰，
## 判定由 WorkplaceTown 注入 main_gate（WorldClock.main_event_due），本面板不碰 autoload。

signal closed()

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
const COLOR_CARD := Color(0.42, 0.247, 0.149, 0.9)
const COLOR_CARD_HOVER := Color(0.48, 0.29, 0.175)
const COLOR_CARD_PRESSED := Color(0.36, 0.21, 0.125)
const COLOR_DOT_FULL := Color("ef9f27")
const COLOR_DOT_EMPTY := Color(0.353, 0.227, 0.141)
const COLOR_LINE := Color(0.831, 0.604, 0.298, 0.35)

const CARD_SIZE := Vector2(560, 632)

## 四个动作（id 与 MonthlyLife.spend_energy 的入参一致）。
const ACTIONS := [
	{"id": "grow", "label": "专业成长", "sub": "啃论文，专业能力 +1"},
	{"id": "produce", "label": "工作产出", "sub": "推进任务，月底折奖金"},
	{"id": "social", "label": "人际经营", "sub": "约人喝咖啡，关系 +"},
	{"id": "rest", "label": "休息恢复", "sub": "睡个午觉，生命 +1"},
]

var _life
## 主线门禁（WorkplaceTown 注入 WorldClock.main_event_due）：
## 有效且返回 true = 当月主线没过完，动作卡整体置灰。
var main_gate: Callable = Callable()
var _root: Control
var _dim: ColorRect
var _card: Panel
var _open_flag := false
var _tween: Tween
var _dots: Array[Panel] = []
var _count_label: Label
var _note_label: Label
var _buttons: Array[Button] = []
## 熊友卡搭档协助（Batch 5 §6.2）：空串 = 自己上，不叫人。
var _selected_buddy := ""
var _buddy_title: Label
var _buddy_row: HBoxContainer
var _buddy_chips := {}


func setup(life) -> void:
	_life = life
	if _life != null and _life.has_signal("state_changed"):
		_life.state_changed.connect(_refresh)


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
	_refresh()


func open() -> void:
	if _open_flag:
		return
	_open_flag = true
	_root.visible = true
	_refresh()
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
	closed.emit()


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

	var title := _label("本月精力", 30, COLOR_TITLE)
	title.position = Vector2(32, 24)
	title.size = Vector2(240, 44)
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

	var subtitle := _label("每月初发 3 点 · 不可结转", 14, COLOR_SUB)
	subtitle.position = Vector2(104, 66)
	subtitle.size = Vector2(320, 24)
	_card.add_child(subtitle)

	var close_button := _make_circle_close_button()
	close_button.position = Vector2(CARD_SIZE.x - 40.0 - 22.0, 22)
	close_button.pressed.connect(close)
	_card.add_child(close_button)

	# 大圆点行：本月剩余点数（满=橙 / 空=暗），最多铺 8 颗（月度 3 点远远用不满）。
	var dot_row_y := 112.0
	var dot_size := 26.0
	for i in 8:
		var dot := Panel.new()
		dot.position = Vector2(34 + i * (dot_size + 10.0), dot_row_y)
		dot.size = Vector2(dot_size, dot_size)
		var dot_style := StyleBoxFlat.new()
		dot_style.bg_color = COLOR_DOT_FULL
		dot_style.set_corner_radius_all(int(dot_size / 2.0))
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(dot)
		_dots.append(dot)
	_count_label = _label("3 / 3", 26, COLOR_TITLE)
	_count_label.position = Vector2(CARD_SIZE.x - 160.0, dot_row_y - 6.0)
	_count_label.size = Vector2(126, 38)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_font_override("font", title_font)
	_card.add_child(_count_label)

	var divider := ColorRect.new()
	divider.color = COLOR_LINE
	divider.position = Vector2(32, 158)
	divider.size = Vector2(CARD_SIZE.x - 64.0, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(divider)

	# 搭档协助（Batch 5 · 机制文档 §6.2）：Lv3「伙伴」后可选一名同事，
	# 同一次行动只结算一名、只放大公开资源。没解锁时不摆空位，只留一行说明。
	_buddy_title = _label("搭档协助", 15, COLOR_SUB)
	_buddy_title.position = Vector2(34, 170)
	_buddy_title.size = Vector2(CARD_SIZE.x - 68.0, 20)
	_card.add_child(_buddy_title)
	_buddy_row = HBoxContainer.new()
	_buddy_row.position = Vector2(32, 194)
	_buddy_row.size = Vector2(CARD_SIZE.x - 64.0, 34)
	_buddy_row.add_theme_constant_override("separation", 8)
	_card.add_child(_buddy_row)

	# 4 张动作卡：整卡可点，左图标圆 + 动作名 + 副文本。
	var card_x := 32.0
	var card_w := CARD_SIZE.x - 64.0
	for i in ACTIONS.size():
		var action: Dictionary = ACTIONS[i]
		var y := 240.0 + 86.0 * i
		var card_button := Button.new()
		card_button.position = Vector2(card_x, y)
		card_button.size = Vector2(card_w, 74)
		card_button.add_theme_stylebox_override("normal", _button_style(COLOR_CARD, COLOR_BORDER, 14))
		card_button.add_theme_stylebox_override("hover", _button_style(COLOR_CARD_HOVER, Color("ffc453"), 14))
		card_button.add_theme_stylebox_override("pressed", _button_style(COLOR_CARD_PRESSED, COLOR_BORDER, 14))
		card_button.add_theme_stylebox_override("disabled", _button_style(Color(0.24, 0.15, 0.09, 0.6), Color(0.831, 0.604, 0.298, 0.25), 14))
		card_button.pivot_offset = card_button.size / 2.0
		card_button.pressed.connect(_on_action_pressed.bind(String(action["id"])))
		card_button.pressed.connect(_on_card_bounce.bind(card_button))
		_card.add_child(card_button)
		_buttons.append(card_button)

		var icon := Panel.new()
		icon.position = Vector2(14, 15)
		icon.size = Vector2(44, 44)
		var icon_style := StyleBoxFlat.new()
		icon_style.bg_color = COLOR_CHIP
		icon_style.set_corner_radius_all(22)
		icon.add_theme_stylebox_override("panel", icon_style)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_button.add_child(icon)
		var icon_label := _label(String(action["label"]).left(1), 20, COLOR_CHIP_TEXT)
		icon_label.position = Vector2(0, 0)
		icon_label.size = Vector2(44, 44)
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_override("font", title_font)
		icon.add_child(icon_label)

		var name_label := _label(String(action["label"]), 22, COLOR_TEXT)
		name_label.position = Vector2(74, 8)
		name_label.size = Vector2(240, 34)
		name_label.add_theme_font_override("font", title_font)
		card_button.add_child(name_label)

		var sub_label := _label(String(action["sub"]), 15, COLOR_SUB)
		sub_label.position = Vector2(74, 42)
		sub_label.size = Vector2(card_w - 90.0, 24)
		card_button.add_child(sub_label)

	# 反馈便签：点完动作在这里说一句人话。
	_note_label = _label("", 15, COLOR_SUB)
	_note_label.position = Vector2(34, 596)
	_note_label.size = Vector2(CARD_SIZE.x - 68.0, 24)
	_note_label.clip_text = true
	_note_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card.add_child(_note_label)
	_rebuild_buddy_chips()


## 点一张动作卡 = 花 1 点精力（MonthlyLife.spend_energy 是唯一消费通路，
## energy_exhausted 由它在末尾发、WorkplaceTown 接管提示横幅）。
func _on_action_pressed(action_id: String) -> void:
	if _life == null:
		return
	var result: Dictionary = _life.spend_energy(action_id, _selected_buddy)
	if not bool(result.get("ok", false)):
		# 拒绝原因直接用 MonthlyLife 的话（精力用完 / 主线没过完，两条分支文案都在那）。
		_note_label.text = String(result.get("text", "这个月的 3 点用完了，下个月初补满"))
		return
	_note_label.text = String(result.get("text", ""))
	_refresh()
	if int(_life.energy) <= 0:
		# 花完最后 1 点：停 0.8s 让玩家看到反馈，然后自动关弹窗，
		# 把舞台让给「精力用完」的顶部横幅提示。
		await get_tree().create_timer(0.8).timeout
		if _open_flag:
			close()


## 圆点 / 计数 / 按钮置灰，全部跟着 state_changed 走。
func _refresh(_state: Dictionary = {}) -> void:
	if _card == null:
		return
	var energy := 0
	var energy_max := 3
	if _life != null:
		var snapshot: Dictionary = _life.snapshot()
		energy = int(snapshot.get("energy", 0))
		energy_max = maxi(1, int(snapshot.get("energyMax", 3)))
	for i in _dots.size():
		var full: bool = i < energy
		var style: StyleBoxFlat = _dots[i].get_theme_stylebox("panel")
		if style != null:
			style.bg_color = COLOR_DOT_FULL if full else COLOR_DOT_EMPTY
		_dots[i].modulate = Color(1, 1, 1, 1) if i < energy_max else Color(1, 1, 1, 0.25)
	_count_label.text = "%d / %d" % [energy, energy_max]
	var no_energy: bool = energy <= 0
	# 主线门禁：当月主线没过完 → 四张动作卡整体置灰（MonthlyLife.spend_energy 里还有硬拦兜底）。
	var main_locked: bool = main_gate.is_valid() and bool(main_gate.call())
	for button in _buttons:
		button.disabled = no_energy or main_locked
	if main_locked:
		_note_label.text = "本月主线还没过完——先去完成主线事件，再来花精力。"
	_rebuild_buddy_chips()


## ---------- 熊友卡搭档协助（Batch 5 §6.2）----------

## 重列搭档 chips：「自己」+ 已解锁（Lv3）的同事。没解锁任何同事时只剩「自己」，
## 标题带一句人话（不暴露好感数值/等级）。
func _rebuild_buddy_chips() -> void:
	if _buddy_row == null:
		return
	var options: Array = [{"id": "", "name": "自己"}]
	if _life != null:
		for npc_id: String in _life.unlocked_buddies():
			var card: Dictionary = _life.buddy_card_for(npc_id)
			options.append({"id": npc_id, "name": String(card.get("name", npc_id))})
	# 选中项若已不在列表（理论上不会），退回「自己」
	var ids: Array = []
	for opt: Dictionary in options:
		ids.append(String(opt["id"]))
	if not ids.has(_selected_buddy):
		_selected_buddy = ""
	for child in _buddy_row.get_children():
		child.queue_free()
	_buddy_chips.clear()
	if options.size() <= 1:
		_buddy_title.text = "搭档协助 · 关系到「伙伴」后，会有人愿意搭把手"
	else:
		_buddy_title.text = "搭档协助 · 同一次行动只叫一人，只加成公开数值"
	var chip_w := int((CARD_SIZE.x - 64.0 - 8.0 * (options.size() - 1)) / options.size())
	for opt: Dictionary in options:
		var chip := Button.new()
		chip.text = String(opt["name"])
		chip.custom_minimum_size = Vector2(chip_w, 34)
		chip.add_theme_font_override("font", FONT)
		chip.add_theme_font_size_override("font_size", 16)
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_buddy_chip_pressed.bind(String(opt["id"])))
		_buddy_row.add_child(chip)
		_buddy_chips[String(opt["id"])] = chip
	_apply_buddy_styles()


func _apply_buddy_styles() -> void:
	for id: String in _buddy_chips.keys():
		var chip: Button = _buddy_chips[id]
		if id == _selected_buddy:
			chip.add_theme_stylebox_override("normal", _button_style(COLOR_CHIP, Color("ffe0a0"), 10))
			chip.add_theme_stylebox_override("hover", _button_style(COLOR_CHIP, Color("ffe0a0"), 10))
			chip.add_theme_color_override("font_color", COLOR_CHIP_TEXT)
		else:
			chip.add_theme_stylebox_override("normal", _button_style(COLOR_CARD, COLOR_BORDER, 10))
			chip.add_theme_stylebox_override("hover", _button_style(COLOR_CARD_HOVER, Color("ffc453"), 10))
			chip.add_theme_color_override("font_color", COLOR_TEXT)


func _on_buddy_chip_pressed(buddy_id: String) -> void:
	_selected_buddy = buddy_id
	_apply_buddy_styles()
	if buddy_id.is_empty():
		_note_label.text = "这次自己上。"
		return
	var card: Dictionary = _life.buddy_card_for(buddy_id)
	var assist: Dictionary = card.get("assist", {})
	var scope := String(assist.get("action", "*"))
	var where := "任何一件事" if scope == "*" else _action_name(scope)
	_note_label.text = "%s 会在「%s」上搭把手。" % [String(card.get("name", "")), where]


func _action_name(action_id: String) -> String:
	for action: Dictionary in ACTIONS:
		if String(action["id"]) == action_id:
			return String(action["label"])
	return action_id


## ---------- 交互与样式工具（同 SettingsPanel 基线） ----------

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
	button.pressed.connect(_on_card_bounce.bind(button))
	return button


## 点背景（卡片外）关闭。
func _on_center_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## 按压回弹：scale 1 → 0.94 → 1（旋转中心在控件中心）。
func _on_card_bounce(button: Button) -> void:
	button.pivot_offset = button.size / 2.0
	var bounce := create_tween()
	bounce.tween_property(button, "scale", Vector2(0.94, 0.94), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(button, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
