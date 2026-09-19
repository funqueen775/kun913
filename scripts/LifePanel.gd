extends CanvasLayer
## 「生活」居中模态面板（2026-09-18 用户拍板：周末不再自动弹窗，全模块收进一颗「生活」钮）。
## 顶部 Tab 导航分三页：
##   精力 —— 自 EnergyModalPanel 原样迁入（看余点 + 花 1 点，搭档协助 chips 保留）；
##   周末 —— 自由周末状态页（就绪可去安排 / 已过完 / 主线未结被锁 / 本月无），
##           「去安排」发 weekend_requested，由 WorkplaceTown 停表并打开 FreeTimePanel；
##   熊友 —— 4 位 NPC 的关系档位一览。红线（free_time_system.json:2）：只说关系，不报数字。
## 风格基线同 SettingsPanel / 旧 EnergyModalPanel（暖木金边圆角大卡 + 点背景/ESC 关闭）。
## 刻意不引用任何 autoload（WorldClock / ApiClient）：探针可以直接 new 出来测；
## 停钟由 WorkplaceTown 在 open/close 回调里做。
## 周末状态由 WorkplaceTown 推送（set_weekend_state），本面板不反查小镇内部状态。

signal closed()
## 点「去安排这个周末」→ WorkplaceTown 关本面板、停表、open_for_month(weekend_month)。
signal weekend_requested(weekend_month: int)

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
## 关系档位点：点亮用橙，未点用暗底（同精力圆点配色，一套视觉语言）。
const COLOR_REL_FULL := Color("ef9f27")
const COLOR_REL_EMPTY := Color(0.353, 0.227, 0.141, 0.85)

const CARD_SIZE := Vector2(560, 632)

## 四个动作（id 与 MonthlyLife.spend_energy 的入参一致；探针按这个表验收）。
const ACTIONS := [
	{"id": "grow", "label": "专业成长", "sub": "啃论文，专业能力 +1"},
	{"id": "produce", "label": "工作产出", "sub": "推进任务，月底折奖金"},
	{"id": "social", "label": "人际经营", "sub": "约人喝咖啡，关系 +"},
	{"id": "rest", "label": "休息恢复", "sub": "睡个午觉，生命 +1"},
]

## 熊友页的固定名册：与 MonthlyLife.SOCIAL_POOL 同一口径（熊总没有好感来源，不上榜）。
const BUDDY_IDS: Array[String] = ["wang_ge", "xiao_lin", "xiao_zhao", "lao_zhou"]

const TAB_IDS: Array[String] = ["energy", "weekend", "buddy"]
const TAB_LABELS := {
	"energy": "精力",
	"weekend": "周末",
	"buddy": "熊友",
}
const TAB_SUBTITLES := {
	"energy": "每月初发 3 点 · 不可结转",
	"weekend": "每 3 个月一次 · 周六两格",
	"buddy": "关系如何，一眼便知",
}

var _life
## 主线门禁（WorkplaceTown 注入 WorldClock.main_event_due）：
## 有效且返回 true = 当月主线没过完 → 精力动作卡整体置灰、周末页显示锁定态。
var main_gate: Callable = Callable()
var _root: Control
var _dim: ColorRect
var _card: Panel
var _open_flag := false
var _tween: Tween
var _active_tab := "energy"
var _tab_buttons := {}
var _subtitle: Label

## —— 精力页成员（名字沿用 EnergyModalPanel，探针 hud_polish 按这些名字验收）——
var _dots: Array[Panel] = []
var _count_label: Label
var _note_label: Label
var _buttons: Array[Button] = []
## 熊友卡搭档协助（Batch 5 §6.2）：空串 = 自己上，不叫人。
var _selected_buddy := ""
var _buddy_title: Label
var _buddy_row: HBoxContainer
var _buddy_chips := {}
var _energy_root: Control

## —— 周末页成员 ——
var _weekend_root: Control
## WorkplaceTown 推送：ready=可去安排 / done=本月周末已过 / locked=主线没过完 / none=本月无。
var _weekend_state := "none"
var _weekend_month := -1
var _next_weekend_month := -1
var _weekend_status: Label
var _weekend_sub: Label
var _weekend_go: Button

## —— 熊友页成员 ——
var _buddy_root: Control


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
	_build_tab_bar()
	_build_energy_content()
	_build_weekend_content()
	_build_buddy_content()
	_switch_tab("energy")
	_refresh()


## ---------- Tab 导航 ----------

func _build_tab_bar() -> void:
	var title_font := FontVariation.new()
	title_font.base_font = FONT
	title_font.variation_embolden = 0.5
	for i in TAB_IDS.size():
		var tab_id: String = TAB_IDS[i]
		var tab := Button.new()
		tab.text = String(TAB_LABELS[tab_id])
		tab.position = Vector2(32.0 + i * 112.0, 18)
		tab.size = Vector2(104, 40)
		tab.add_theme_font_override("font", title_font)
		tab.add_theme_font_size_override("font_size", 20)
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_switch_tab.bind(tab_id))
		tab.pressed.connect(_on_card_bounce.bind(tab))
		_card.add_child(tab)
		_tab_buttons[tab_id] = tab
	_subtitle = _label(String(TAB_SUBTITLES["energy"]), 14, COLOR_SUB)
	_subtitle.position = Vector2(380, 26)
	_subtitle.size = Vector2(150, 24)
	_card.add_child(_subtitle)

	var close_button := _make_circle_close_button()
	close_button.position = Vector2(CARD_SIZE.x - 40.0 - 22.0, 62)
	close_button.pressed.connect(close)
	_card.add_child(close_button)


func _switch_tab(tab_id: String) -> void:
	if not TAB_IDS.has(tab_id):
		return
	_active_tab = tab_id
	for id: String in _tab_buttons.keys():
		var tab: Button = _tab_buttons[id]
		if id == _active_tab:
			tab.add_theme_stylebox_override("normal", _button_style(COLOR_CHIP, Color("ffe0a0"), 10))
			tab.add_theme_color_override("font_color", COLOR_CHIP_TEXT)
		else:
			tab.add_theme_stylebox_override("normal", _button_style(COLOR_CARD, COLOR_BORDER, 10))
			tab.add_theme_color_override("font_color", COLOR_TEXT)
	_subtitle.text = String(TAB_SUBTITLES[_active_tab])
	_energy_root.visible = _active_tab == "energy"
	_weekend_root.visible = _active_tab == "weekend"
	_buddy_root.visible = _active_tab == "buddy"
	if _active_tab == "energy":
		_refresh()


func open_at_tab(tab_id: String) -> void:
	open()
	_switch_tab(tab_id)


## ---------- 精力页（自 EnergyModalPanel 迁入，坐标保持原版式） ----------

func _build_energy_content() -> void:
	_energy_root = Control.new()
	_energy_root.position = Vector2.ZERO
	_energy_root.size = CARD_SIZE
	_energy_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_energy_root)

	var title_font := FontVariation.new()
	title_font.base_font = FONT
	title_font.variation_embolden = 0.5

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
		_energy_root.add_child(dot)
		_dots.append(dot)
	_count_label = _label("3 / 3", 26, COLOR_TITLE)
	_count_label.position = Vector2(CARD_SIZE.x - 160.0, dot_row_y - 6.0)
	_count_label.size = Vector2(126, 38)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_font_override("font", title_font)
	_energy_root.add_child(_count_label)

	var divider := ColorRect.new()
	divider.color = COLOR_LINE
	divider.position = Vector2(32, 158)
	divider.size = Vector2(CARD_SIZE.x - 64.0, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_root.add_child(divider)

	# 搭档协助（Batch 5 · 机制文档 §6.2）：Lv3「伙伴」后可选一名同事，
	# 同一次行动只结算一名、只放大公开资源。没解锁时不摆空位，只留一行说明。
	_buddy_title = _label("搭档协助", 15, COLOR_SUB)
	_buddy_title.position = Vector2(34, 170)
	_buddy_title.size = Vector2(CARD_SIZE.x - 68.0, 20)
	_energy_root.add_child(_buddy_title)
	_buddy_row = HBoxContainer.new()
	_buddy_row.position = Vector2(32, 194)
	_buddy_row.size = Vector2(CARD_SIZE.x - 64.0, 34)
	_buddy_row.add_theme_constant_override("separation", 8)
	_energy_root.add_child(_buddy_row)

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
		_energy_root.add_child(card_button)
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
	_energy_root.add_child(_note_label)
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
		# 花完最后 1 点：停 0.8s 让玩家看到反馈，然后自动关面板，
		# 把舞台让给「精力用完」的顶部横幅提示。
		await get_tree().create_timer(0.8).timeout
		if _open_flag:
			close()


## 圆点 / 计数 / 按钮置灰，全部跟着 state_changed 走。
func _refresh(_state: Dictionary = {}) -> void:
	if _card == null or _count_label == null:
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


## ---------- 周末页 ----------

func _build_weekend_content() -> void:
	_weekend_root = Control.new()
	_weekend_root.position = Vector2.ZERO
	_weekend_root.size = CARD_SIZE
	_weekend_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weekend_root.visible = false
	_card.add_child(_weekend_root)

	var title_font := FontVariation.new()
	title_font.base_font = FONT
	title_font.variation_embolden = 0.5

	_weekend_status = _label("", 26, COLOR_TITLE)
	_weekend_status.position = Vector2(32, 190)
	_weekend_status.size = Vector2(CARD_SIZE.x - 64.0, 40)
	_weekend_status.add_theme_font_override("font", title_font)
	_weekend_root.add_child(_weekend_status)

	_weekend_sub = _label("", 16, COLOR_SUB)
	_weekend_sub.position = Vector2(32, 244)
	_weekend_sub.size = Vector2(CARD_SIZE.x - 64.0, 60)
	_weekend_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weekend_root.add_child(_weekend_sub)

	_weekend_go = Button.new()
	_weekend_go.text = "去安排这个周末"
	_weekend_go.position = Vector2(32, 330)
	_weekend_go.size = Vector2(CARD_SIZE.x - 64.0, 68)
	_weekend_go.add_theme_font_override("font", title_font)
	_weekend_go.add_theme_font_size_override("font_size", 24)
	_weekend_go.add_theme_color_override("font_color", COLOR_CHIP_TEXT)
	_weekend_go.add_theme_stylebox_override("normal", _button_style(COLOR_CHIP, Color("ffe0a0"), 14))
	_weekend_go.add_theme_stylebox_override("hover", _button_style(Color("f5ad3d"), Color("ffe0a0"), 14))
	_weekend_go.add_theme_stylebox_override("pressed", _button_style(Color("d98d1c"), Color("ffe0a0"), 14))
	_weekend_go.pivot_offset = _weekend_go.size / 2.0
	_weekend_go.pressed.connect(_on_go_weekend_pressed)
	_weekend_go.pressed.connect(_on_card_bounce.bind(_weekend_go))
	_weekend_root.add_child(_weekend_go)
	# 默认态：WorkplaceTown 推送前先给一版「本月没有自由周末」，别让页面空白。
	set_weekend_state("none", -1, -1)


## WorkplaceTown 推送周末状态（面板不反查小镇内部，探针也能直接喂数据）。
func set_weekend_state(state: String, weekend_month: int, next_month: int) -> void:
	_weekend_state = state
	_weekend_month = weekend_month
	_next_weekend_month = next_month
	if _weekend_status == null:
		return
	match state:
		"ready":
			_weekend_status.text = "第 %d 月 · 自由周末就绪" % weekend_month
			_weekend_sub.text = "周六两格随你安排，也能留白就这么过。"
			_weekend_go.visible = true
		"done":
			_weekend_status.text = "本月的周末已经过完了"
			_weekend_sub.text = "下一个自由周末在第 %d 月 · 到时候「生活」钮会亮红点。" % maxi(1, next_month)
			_weekend_go.visible = false
		"locked":
			_weekend_status.text = "本月主线还没过完"
			_weekend_sub.text = "主线结完，自由周末才开场。"
			_weekend_go.visible = false
		_:
			_weekend_status.text = "本月没有自由周末"
			_weekend_sub.text = "下一个在第 %d 月 · 到时候「生活」钮会亮红点。" % maxi(1, next_month)
			_weekend_go.visible = false


func _on_go_weekend_pressed() -> void:
	if _weekend_month <= 0:
		return
	weekend_requested.emit(_weekend_month)


## ---------- 熊友页 ----------

func _build_buddy_content() -> void:
	_buddy_root = Control.new()
	_buddy_root.position = Vector2.ZERO
	_buddy_root.size = CARD_SIZE
	_buddy_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buddy_root.visible = false
	_card.add_child(_buddy_root)

	var intro := _label("只说关系，不报数字 —— 这是小镇的规矩。", 14, COLOR_SUB)
	intro.position = Vector2(34, 100)
	intro.size = Vector2(CARD_SIZE.x - 68.0, 20)
	_buddy_root.add_child(intro)

	var card_w := CARD_SIZE.x - 64.0
	for i in BUDDY_IDS.size():
		var npc_id: String = BUDDY_IDS[i]
		var y := 140.0 + 78.0 * i
		var row := Panel.new()
		row.position = Vector2(32, y)
		row.size = Vector2(card_w, 66)
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = COLOR_CARD
		row_style.border_color = COLOR_BORDER
		row_style.set_border_width_all(2)
		row_style.set_corner_radius_all(14)
		row.add_theme_stylebox_override("panel", row_style)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buddy_root.add_child(row)

		# 头像圆 + 名字 + 现档称谓（MonthlyLife.relation_stage_name，红线内的话术）。
		var avatar := Panel.new()
		avatar.position = Vector2(14, 13)
		avatar.size = Vector2(40, 40)
		var avatar_style := StyleBoxFlat.new()
		avatar_style.bg_color = COLOR_CHIP
		avatar_style.set_corner_radius_all(20)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(avatar)
		var avatar_label := _label(_buddy_name(npc_id).left(1), 20, COLOR_CHIP_TEXT)
		avatar_label.size = Vector2(40, 40)
		avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar.add_child(avatar_label)

		var name_label := _label(_buddy_name(npc_id), 19, COLOR_TEXT)
		name_label.position = Vector2(66, 8)
		name_label.size = Vector2(160, 28)
		row.add_child(name_label)
		var stage_label := _label("", 14, COLOR_SUB)
		stage_label.name = "Stage_" + npc_id
		stage_label.position = Vector2(66, 36)
		stage_label.size = Vector2(220, 22)
		row.add_child(stage_label)

		# 关系进度点：5 颗，点亮数 = 档位（1-5）。⚠ 由档位换算，不显示任何分数。
		for d in 5:
			var rel_dot := Panel.new()
			rel_dot.position = Vector2(card_w - 132.0 + d * 20.0, 12)
			rel_dot.size = Vector2(13, 13)
			var rel_style := StyleBoxFlat.new()
			rel_style.bg_color = COLOR_REL_FULL
			rel_style.set_corner_radius_all(6)
			rel_dot.add_theme_stylebox_override("panel", rel_style)
			rel_dot.name = "RelDot_%d_%d" % [i, d]
			rel_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(rel_dot)

		# 搭档解锁标记：Lv3「伙伴」后花精力可叫 TA 搭把手。
		var assist_tag := _label("", 12, COLOR_SUB)
		assist_tag.name = "Assist_" + npc_id
		assist_tag.position = Vector2(card_w - 132.0, 34)
		assist_tag.size = Vector2(110, 20)
		row.add_child(assist_tag)

	var footnote := _label("关系到「老熟人了」，花精力时就能叫 TA 搭把手。", 14, COLOR_SUB)
	footnote.position = Vector2(34, 470)
	footnote.size = Vector2(CARD_SIZE.x - 68.0, 22)
	_buddy_root.add_child(footnote)
	_refresh_buddy_page()


func _buddy_name(npc_id: String) -> String:
	if _life != null:
		return String(_life.NPC_NAMES.get(npc_id, npc_id))
	return npc_id


## 按最新好感刷新熊友页：档位点 + 称谓 + 搭档标记。
## ⚠ affinity_of 的分数只在本函数内部用于换算档位，绝不落进任何 Label。
func _refresh_buddy_page() -> void:
	if _buddy_root == null:
		return
	for i in BUDDY_IDS.size():
		var npc_id: String = BUDDY_IDS[i]
		var level := 1
		var stage := ""
		var unlocked := false
		if _life != null:
			level = int(_life.affinity_level(int(_life.affinity_of(npc_id))))
			stage = String(_life.relation_stage_name(npc_id))
			unlocked = bool(_life.is_buddy_unlocked(npc_id))
		var row := _buddy_root.get_child(1 + i) as Panel
		if row == null:
			continue
		var stage_label := row.get_node_or_null(NodePath("Stage_" + npc_id)) as Label
		if stage_label != null:
			stage_label.text = stage
		for d in 5:
			var rel_dot := row.get_node_or_null(NodePath("RelDot_%d_%d" % [i, d])) as Panel
			if rel_dot == null:
				continue
			var rel_style: StyleBoxFlat = rel_dot.get_theme_stylebox("panel")
			if rel_style != null:
				rel_style.bg_color = COLOR_REL_FULL if d < level else COLOR_REL_EMPTY
		var assist_tag := row.get_node_or_null(NodePath("Assist_" + npc_id)) as Label
		if assist_tag != null:
			assist_tag.text = "可搭把手" if unlocked else ""


## ---------- 开合与交互 ----------

func open() -> void:
	if _open_flag:
		return
	_open_flag = true
	_root.visible = true
	_refresh()
	_refresh_buddy_page()
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


## ---------- 样式工具（同 SettingsPanel 基线） ----------

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
