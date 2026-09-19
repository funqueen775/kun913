extends CanvasLayer
## 「本月精力」专属按钮 + 可展开面板（2026-09-16 重排版；2026-09-17 改月度口径）。
## 收起态：时间面板下方一条木牌按钮（闪电块 + 精力圆点 + n/max），
##         还有没用完的精力时圆点做呼吸提醒。
## 展开态：0.25s 向下滑出 —— 大圆点行 / 三张大数字卡（数值滚动）/ 2×2 行动卡（带副文本）/ 米色便签反馈。
## 口径见 scripts/MonthlyLife.gd：精力 = 每月 3 点、不可结转（跨天不回满，新月重发），
## 1 点精力只做一件事；时间推进与精力脱钩（睡觉跨天 + 主线结算双驱动，见 WorkplaceTown）。

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

## 「energy_exhausted」信号已上移到 MonthlyLife（2026-09-17）：行动卡与右上角精力
## 圆钮两条消费路径都走 spend_energy()，信号只在该函数末尾发一次，避免双发。

const ACTIONS := [
	{"id": "grow", "label": "专业成长", "sub": "啃论文，专业能力 +1"},
	{"id": "produce", "label": "工作产出", "sub": "推进任务，月底折奖金"},
	{"id": "social", "label": "人际经营", "sub": "约人喝咖啡，关系 +"},
	{"id": "rest", "label": "休息恢复", "sub": "睡个午觉，生命 +1"},
]
const COLOR_BG := Color("54321f")
const COLOR_BORDER := Color("d49a4c")
const COLOR_TITLE := Color("ffe5a8")
const COLOR_TEXT := Color("fff0c9")
const COLOR_SUB := Color("d5b77b")
const COLOR_CARD := Color("6b3f26")
const COLOR_ICON := Color("ef9f27")
const COLOR_DOT_FULL := Color("ef9f27")
const COLOR_DOT_EMPTY := Color("5a3a24")
const COLOR_NOTE_BG := Color("f5ecd7")
const COLOR_NOTE_TEXT := Color("4a3a20")
## 每月精力点数从 MonthlyLife.snapshot()["energyMax"] 读（口径只有一个来源）。
var _energy_max := 3

var _life
var _expanded := false
var _pulse_time := 0.0
var _seen_settlement := ""
var _tween: Tween
var _roll_tweens := {}
var _displayed := {}

var _collapsed_button: Button
var _panel: Panel
## 展开面板的大圆点与收起按钮的小圆点（两套，都随精力变色）。
var _dots: Array[Panel] = []
var _dot_styles: Array[StyleBoxFlat] = []
var _mini_dots: Array[Panel] = []
var _mini_styles: Array[StyleBoxFlat] = []
var _count_label: Label
var _month_label: Label
var _skill_value: Label
var _health_value: Label
var _money_value: Label
var _note_panel: Panel
var _note_label: Label
var _buttons: Array[Button] = []

## 展开面板挂在这个 y 上（收起条 y 334 高 54，留 10px 缝）。
const PANEL_BASE_Y := 398.0


func setup(life) -> void:
	_life = life
	if _life != null and _life.has_signal("state_changed"):
		_life.state_changed.connect(_refresh)


func _ready() -> void:
	layer = 121
	if _life != null:
		_energy_max = maxi(1, int(_life.snapshot().get("energyMax", 3)))
	_build_collapsed()
	_build_panel()
	_refresh()


func _process(delta: float) -> void:
	# 收起态呼吸提醒：还有精力没用时，实心圆点轻轻脉动。
	if _collapsed_button == null or _life == null:
		return
	# ⚠ 必须显式标 bool：_life 是弱类型引用，`not _expanded and _life.energy > 0`
	# 的结果是 Variant，用 := 推断会在加载时报「Cannot infer the type」。
	var pulse: bool = not _expanded and _life.energy > 0
	if not pulse:
		for dot in _mini_dots:
			dot.self_modulate.a = 1.0
		return
	_pulse_time += delta
	var a := 0.72 + 0.28 * sin(_pulse_time * 4.2)
	for i in _mini_dots.size():
		_mini_dots[i].self_modulate.a = 1.0 if i >= _life.energy else a


## ---------- 收起态 ----------

func _build_collapsed() -> void:
	_collapsed_button = Button.new()
	_collapsed_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# y 334：时间面板（26..234）→ 功能圆钮排（250..298）→ 悬停提示（306..330）→ 精力条。
	_collapsed_button.position = Vector2(-365, 334)
	_collapsed_button.size = Vector2(350, 54)
	_collapsed_button.add_theme_stylebox_override("normal", _card_style(COLOR_BG, COLOR_BORDER))
	_collapsed_button.add_theme_stylebox_override("hover", _card_style(Color("6b3f26"), COLOR_BORDER))
	_collapsed_button.add_theme_stylebox_override("pressed", _card_style(Color("472a19"), COLOR_BORDER))
	_collapsed_button.pressed.connect(func(): set_expanded(not _expanded))
	add_child(_collapsed_button)

	var icon := Panel.new()
	icon.position = Vector2(16, 15)
	icon.size = Vector2(24, 24)
	var icon_style := _flat_style(COLOR_ICON)
	icon_style.set_corner_radius_all(5)
	icon.add_theme_stylebox_override("panel", icon_style)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapsed_button.add_child(icon)

	var title := _label("本月精力", 24, COLOR_TEXT)
	title.position = Vector2(52, 0)
	title.size = Vector2(140, 54)
	_collapsed_button.add_child(title)

	for i in _energy_max:
		var dot := Panel.new()
		dot.position = Vector2(196 + i * 24, 20)
		dot.size = Vector2(14, 14)
		var dot_style := _flat_style(COLOR_DOT_FULL)
		dot_style.set_corner_radius_all(7)
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_collapsed_button.add_child(dot)
		_mini_dots.append(dot)
		_mini_styles.append(dot_style)

	_count_label = _label("4 / 4", 18, COLOR_SUB)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.position = Vector2(256, 0)
	_count_label.size = Vector2(78, 54)
	_collapsed_button.add_child(_count_label)


## ---------- 展开态 ----------

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-365, PANEL_BASE_Y)
	_panel.size = Vector2(350, 424)
	_panel.add_theme_stylebox_override("panel", _card_style(COLOR_BG, COLOR_BORDER))
	_panel.visible = false
	add_child(_panel)

	_month_label = _label("本月精力 · 第 1 月", 23, COLOR_TITLE)
	_month_label.position = Vector2(24, 18)
	_month_label.size = Vector2(250, 32)
	_panel.add_child(_month_label)
	for i in _energy_max:
		var dot := Panel.new()
		dot.position = Vector2(350 - 24 - (_energy_max - i) * 38, 20)
		dot.size = Vector2(26, 26)
		var dot_style := _flat_style(COLOR_DOT_FULL)
		dot_style.set_corner_radius_all(13)
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(dot)
		_dots.append(dot)
		_dot_styles.append(dot_style)

	var stats := [
		{"key": "skill", "label": "专业能力"},
		{"key": "health", "label": "生命"},
		{"key": "money", "label": "金钱"},
	]
	var card_width := (350.0 - 48.0 - 20.0) / 3.0
	for i in stats.size():
		var card := Panel.new()
		card.position = Vector2(24 + i * (card_width + 10), 60)
		card.size = Vector2(card_width, 64)
		card.add_theme_stylebox_override("panel", _flat_style(COLOR_CARD))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(card)
		var caption := _label(String(stats[i]["label"]), 16, COLOR_SUB)
		caption.position = Vector2(10, 7)
		caption.size = Vector2(card_width - 20, 20)
		card.add_child(caption)
		var value := _label("-", 25, COLOR_TEXT)
		value.position = Vector2(10, 28)
		value.size = Vector2(card_width - 20, 32)
		card.add_child(value)
		match String(stats[i]["key"]):
			"skill": _skill_value = value
			"health": _health_value = value
			"money": _money_value = value

	var card_width2 := (350.0 - 48.0 - 12.0) / 2.0
	for i in ACTIONS.size():
		var action: Dictionary = ACTIONS[i]
		var button := Button.new()
		button.position = Vector2(24 + (i % 2) * (card_width2 + 12), 138 + (i / 2) * 74)
		button.size = Vector2(card_width2, 66)
		button.add_theme_stylebox_override("normal", _card_style(COLOR_CARD, COLOR_BORDER))
		button.add_theme_stylebox_override("hover", _card_style(Color("7d4c30"), COLOR_TITLE))
		button.add_theme_stylebox_override("disabled", _card_style(Color("4a3327"), Color("3a2618")))
		var action_id := String(action["id"])
		button.pressed.connect(func(): _on_action_pressed(button, action_id))
		_panel.add_child(button)
		_buttons.append(button)
		var title := _label(String(action["label"]), 20, COLOR_TEXT)
		title.position = Vector2(12, 8)
		title.size = Vector2(card_width2 - 24, 26)
		button.add_child(title)
		var sub := _label(String(action["sub"]), 14, COLOR_SUB)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size.x = card_width2 - 24
		sub.position = Vector2(12, 36)
		sub.size = Vector2(card_width2 - 24, 26)
		button.add_child(sub)

	_note_panel = Panel.new()
	_note_panel.position = Vector2(24, 296)
	_note_panel.size = Vector2(302, 104)
	var note_style := _flat_style(COLOR_NOTE_BG)
	note_style.set_corner_radius_all(4)
	_note_panel.add_theme_stylebox_override("panel", note_style)
	_note_panel.rotation = -0.01
	_note_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_note_panel)
	_note_label = _label("主线不耗精力。每月 3 点精力、不可结转，1 点只做一件事，月底产出折算成奖金。", 15, COLOR_NOTE_TEXT)
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.custom_minimum_size.x = 278
	_note_label.position = Vector2(12, 8)
	_note_label.size = Vector2(278, 88)
	_note_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_note_panel.add_child(_note_label)


func _on_action_pressed(button: Button, action_id: String) -> void:
	if _life == null:
		return
	# 按下弹跳：scale 1 → 0.94 → 1（旋转中心在卡片中心）
	button.pivot_offset = button.size / 2.0
	var bounce := create_tween()
	bounce.tween_property(button, "scale", Vector2(0.94, 0.94), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(button, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var result: Dictionary = _life.spend_energy(action_id)
	_note_label.text = String(result.get("text", ""))
	_pop_note()
	_refresh()
	# 「精力耗尽」横幅改由 MonthlyLife.energy_exhausted 直接触发（信号已上移，
	# 见本文件顶部说明）；面板这里只负责便签反馈与刷新。


## 反馈便签弹出：轻微上移 + 淡入。
func _pop_note() -> void:
	var note_y := 296.0
	_note_panel.position.y = note_y + 8
	_note_panel.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_note_panel, "position:y", note_y, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_note_panel, "modulate:a", 1.0, 0.18)


## ---------- 展开 / 收起 ----------

func set_expanded(value: bool) -> void:
	if _panel == null:
		return
	_expanded = value
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if value:
		_panel.visible = true
		_panel.position.y = PANEL_BASE_Y - 18
		_panel.modulate.a = 0.0
		_tween.set_parallel(true)
		_tween.tween_property(_panel, "position:y", PANEL_BASE_Y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_panel, "modulate:a", 1.0, 0.25)
	else:
		_tween.set_parallel(true)
		_tween.tween_property(_panel, "position:y", PANEL_BASE_Y - 12, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(_panel, "modulate:a", 0.0, 0.18)
		_tween.chain().tween_callback(func(): _panel.visible = false)


## ---------- 刷新 ----------

func _refresh(_state: Dictionary = {}) -> void:
	# ⚠ 签名兼容信号 state_changed(state) 的一个参数；直接调用时不传。
	if _life == null or _collapsed_button == null:
		return
	var s: Dictionary = _life.snapshot()
	var energy := int(s["energy"])
	_month_label.text = "本月精力 · 第 %d 月" % int(s["month"])
	_count_label.text = "%d / %d" % [energy, _energy_max]
	for i in _dots.size():
		var target := COLOR_DOT_FULL if i < energy else COLOR_DOT_EMPTY
		_tween_dot_color(_dot_styles[i], target)
		_tween_dot_color(_mini_styles[i], target)
	_roll_number(_skill_value, "skill", int(s["skill"]), "%d")
	_roll_number(_health_value, "health", int(s["health"]), "%d / %d" % [int(s["health"]), int(s["healthMax"])], true)
	_roll_number(_money_value, "money", int(s["money"]), "¥%d")
	var settlement := String(_life.last_settlement)
	if settlement != _seen_settlement:
		_seen_settlement = settlement
		_note_label.text = settlement
		_pop_note()
	for button in _buttons:
		button.disabled = energy <= 0


## 精力圆点颜色过渡（琥珀实心 ↔ 暗木已用）。
func _tween_dot_color(style: StyleBoxFlat, target: Color) -> void:
	var current: Color = style.bg_color
	if current.is_equal_approx(target):
		return
	var t := create_tween()
	t.tween_method(func(v: Color): style.bg_color = v, current, target, 0.25)


## 数值滚动：从旧显示值滚到新值（0.4s 插值）。health 是文本型直接刷新。
func _roll_number(label: Label, key: String, to_value: int, fmt: String, is_text := false) -> void:
	if is_text:
		label.text = fmt
		return
	var from := int(_displayed.get(key, to_value))
	if from == to_value:
		label.text = fmt % to_value
		return
	_displayed[key] = to_value
	if _roll_tweens.has(key) and (_roll_tweens[key] as Tween).is_valid():
		(_roll_tweens[key] as Tween).kill()
	var t := create_tween()
	_roll_tweens[key] = t
	t.tween_method(func(v: float): label.text = fmt % int(round(v)), float(from), float(to_value), 0.4)


## ---------- 样式工具 ----------

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("23170f"))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _flat_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	return style


func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	return style
