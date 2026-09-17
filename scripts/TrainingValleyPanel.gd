extends CanvasLayer
## 训练谷 · 熊熊有招（Batch 4）：关卡选择 + 1v1 骰子对局 + 结算。
## 规则核心在 TrainingDuel.gd（纯规则、探针直测）；本文件只做 UI 与节奏。
## 红线：胜负 / 骰运 / 卡牌使用 / 选择角色一律不进职业测评（机制文档 §10）；
## 对局遥测暂缓（openapi 17 枚举无对局类型，加枚举要动 contracts，等对方会话落地后补）。
## 搭档选择 MVP 只开放玩家角色：Lv3 熊友搭档依赖 Batch 5 关系系统，先占位。
## 样式沿用 FreeTimePanel 暖棕羊皮纸配色。

signal reward_earned(amount: int, reason: String)
signal closed

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const DUEL := preload("res://scripts/TrainingDuel.gd")

const COLOR_BG := Color("54321f")
const COLOR_BORDER := Color("d49a4c")
const COLOR_TITLE := Color("ffe5a8")
const COLOR_TEXT := Color("fff8e8")
const COLOR_SUB := Color("d5b77b")
const COLOR_CARD := Color("6b3f26")
const COLOR_ICON_BG := Color("8a5a38")
const COLOR_ACCENT := Color("a34a32")
const COLOR_HP_ME := Color("7fae5a")
const COLOR_HP_FOE := Color("c0603e")

var _life                    # MonthlyLife：首通状态 + 加钱
var _month := 1
var _config: Dictionary = {}
var _levels: Array = []
var _duel                    # TrainingDuel 实例
var _level: Dictionary = {}
var _in_duel := false
var _busy := false           # AI 回合计时中，锁输入

var _root: Control
var _panel: Panel
var _title: Label
var _subtitle: Label
var _content: VBoxContainer
var _scroll: ScrollContainer
var _footer: Button
## 对局模式的独立件（select 模式下隐藏）
var _duel_box: VBoxContainer
var _hp_me_bar: ColorRect
var _hp_foe_bar: ColorRect
var _hp_label: Label
var _dice_label: Label
var _phase_label: Label
var _log_label: Label
var _hand_box: HBoxContainer
var _pass_btn: Button


func setup(life) -> void:
	_life = life


func open(month: int) -> void:
	_month = month
	_config = DUEL.load_config()
	_levels = _config.get("levels", [])
	_build_ui()
	_show_select()
	_root.show()


func close() -> void:
	_root.hide()
	_in_duel = false
	closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


## ---------- 关卡选择 ----------

func _show_select() -> void:
	_in_duel = false
	_title.text = "熊熊有招"
	_subtitle.text = "训练谷 · 职场过招（胜负不进测评，失败无惩罚）"
	_duel_box.hide()
	_content.show()
	_clear_content()
	var partner := _body_label("搭档：本次用你自己的角色。熊友搭档 Lv3 后解锁。", 14, COLOR_SUB)
	_content.add_child(partner)
	for level_v: Dictionary in _levels:
		var id := String(level_v.get("id"))
		var unlocked: bool = _month >= int(level_v.get("unlock_month", 99))
		var cleared: bool = _life != null and _life.is_duel_cleared(id)
		var sub := "%s · %s" % [String(level_v.get("opponent")), String(level_v.get("context"))]
		if not unlocked:
			sub += "｜未开放：%s" % String(level_v.get("unlock_hint"))
		elif cleared:
			sub += "｜已首通"
		else:
			sub += "｜首通奖励 %d 文" % int(level_v.get("first_clear_reward", 0))
		var btn := _make_card(_style_icon(String(level_v.get("ai_style"))),
			String(level_v.get("name")), sub, _on_level_pressed.bind(level_v), not unlocked)
		_content.add_child(btn)
	_set_footer("", Callable())


func _style_icon(style: String) -> String:
	match style:
		"teaching": return "教"
		"aggressive": return "攻"
		"steady": return "稳"
		"tactical": return "谋"
	return "对"


func _on_level_pressed(level: Dictionary) -> void:
	_level = level
	_start_duel()


## ---------- 对局 ----------

func _start_duel() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_duel = DUEL.create(_level, rng)
	_in_duel = true
	_busy = false
	_title.text = "%s · %s" % [String(_level.get("name")), String(_level.get("opponent"))]
	_subtitle.text = String(_level.get("context"))
	_content.hide()
	_duel_box.show()
	_log_label.text = String(_level.get("intro"))
	_set_pass("", Callable())
	_refresh()
	_set_footer("返回关卡列表", _back_to_select)


func _back_to_select() -> void:
	_in_duel = false
	_show_select()


func _refresh() -> void:
	if _duel == null or not _in_duel:
		return
	var me := int(_duel.hp["player"])
	var foe := int(_duel.hp["opponent"])
	_hp_me_bar.size.x = 240.0 * me / float(_duel.max_hp)
	_hp_foe_bar.size.x = 240.0 * foe / float(_duel.max_hp)
	_hp_label.text = "你 %d/%d    ｜    %s %d/%d" % [me, _duel.max_hp, String(_level.get("opponent")), foe, _duel.max_hp]
	if _duel.over:
		_phase_label.text = "对局结束"
		_dice_label.text = ""
	elif _duel.current_roll > 0:
		_dice_label.text = "本回合骰子：%d 点" % _duel.current_roll
	else:
		_dice_label.text = ""
	match "%s/%s" % [_duel.actor, _duel.phase]:
		"player/roll":
			_phase_label.text = "轮到你：先投骰"
		"player/attack":
			_phase_label.text = "骰子已揭晓：出一张进攻/调整牌，或直接结算"
		"player/defend":
			_phase_label.text = "对方在考虑要不要防…"
		"opponent/roll", "opponent/attack":
			_phase_label.text = "%s 正在思考…" % String(_level.get("opponent"))
		"opponent/defend":
			_phase_label.text = "%s 的攻击来了：可以「先挡一下」，或硬吃" % String(_level.get("opponent"))
		_:
			_phase_label.text = ""
	_set_pass("", Callable())
	if _duel.over:
		for child in _hand_box.get_children():
			child.queue_free()
		return
	# 手牌区：只亮当前阶段允许的卡
	# 攻方出牌 = 玩家是 actor 且在 attack 阶段；玩家防 = 对手是 actor 且在 defend 阶段
	var clickable := ""
	if _duel.actor == "player" and _duel.phase == "attack":
		clickable = "attack"
	elif _duel.actor == "opponent" and _duel.phase == "defend":
		clickable = "defend"
	for child in _hand_box.get_children():
		child.queue_free()
	for card_id: String in _duel.hands["player"]:
		var card: Dictionary = _duel.cards_by_id.get(card_id, {})
		var timing := String(card.get("timing", "attack"))
		var btn := Button.new()
		btn.text = "%s\n%s" % [String(card.get("name")), _effect_text(String(card.get("effect")))]
		btn.custom_minimum_size = Vector2(150, 84)
		btn.add_theme_font_override("font", FONT)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", COLOR_TEXT)
		btn.disabled = clickable == "" or timing != clickable
		btn.add_theme_stylebox_override("normal", _card_style(COLOR_CARD, COLOR_BORDER))
		btn.add_theme_stylebox_override("hover", _card_style(Color("7d4c30"), COLOR_TITLE))
		btn.add_theme_stylebox_override("disabled", _card_style(Color("452a1c"), Color("6b4a33")))
		btn.pressed.connect(_on_card_pressed.bind(card_id))
		_hand_box.add_child(btn)
	if clickable == "attack":
		_set_pass("不出牌，直接结算", _on_pass_attack)
	elif clickable == "defend":
		_set_pass("不防，硬吃这一下", _on_pass_defend)
	else:
		_set_pass("投骰", _on_roll_pressed)


func _effect_text(effect: String) -> String:
	match effect:
		"damage_double": return "伤害翻倍"
		"reroll": return "重投一次"
		"extra_roll": return "追加一枚骰"
		"heal_3": return "恢复 3 点"
		"reduce_3": return "减伤 3 点"
	return ""


func _on_roll_pressed() -> void:
	if _busy or _duel.over or _duel.actor != "player":
		return
	var r: int = _duel.roll()
	if r > 0:
		_log_label.text = "你掷出了 %d 点。" % r
	_refresh()


func _on_card_pressed(card_id: String) -> void:
	if _busy or _duel.over:
		return
	var card: Dictionary = _duel.cards_by_id.get(card_id, {})
	if _duel.phase == "attack" and _duel.actor == "player":
		if _duel.play_attack_card(card_id):
			_log_label.text = "你打出「%s」。" % String(card.get("name"))
			_duel.ai_auto_defend()
			_after_settle()
	elif _duel.phase == "defend" and _duel.actor == "opponent":
		# 对手进攻、玩家防守
		if _duel.play_defend_card(card_id):
			_log_label.text = "你用「%s」挡下了这一击。" % String(card.get("name"))
			_after_settle()


func _on_pass_attack() -> void:
	if _busy or _duel.over:
		return
	_duel.pass_attack()
	_duel.ai_auto_defend()
	_after_settle()


func _on_pass_defend() -> void:
	if _busy or _duel.over:
		return
	_duel.pass_defend()
	_after_settle()


func _after_settle() -> void:
	_log_label.text += "\n" + _turn_text(_duel.last_turn)
	_refresh()
	if _duel.over:
		_show_result()
	elif _duel.actor == "opponent":
		_opponent_turn()


## 把一回合结算翻成人话（log_label 用；规则数字在 TrainingDuel.log 里）。
func _turn_text(turn: Dictionary) -> String:
	if turn.is_empty():
		return ""
	var who := "你" if String(turn.get("actor")) == "player" else String(_level.get("opponent"))
	var foe := String(_level.get("opponent")) if who == "你" else "你"
	var parts: Array[String] = []
	parts.append("%s 掷出 %d 点" % [who, int(turn.get("roll"))])
	if int(turn.get("extra", 0)) > 0:
		parts.append("追加 %d 点" % int(turn.get("extra")))
	if bool(turn.get("double", false)):
		parts.append("伤害翻倍")
	if int(turn.get("guard", 0)) > 0:
		parts.append("%s 减伤 %d" % [foe, int(turn.get("guard"))])
	parts.append("→ %s 受了 %d 点" % [foe, int(turn.get("damage"))])
	return " ".join(parts)


func _opponent_turn() -> void:
	_busy = true
	_refresh()
	await get_tree().create_timer(0.8).timeout
	if not _in_duel or _duel.over or not is_inside_tree():
		_busy = false
		return
	var res: Dictionary = _duel.ai_full_attack()
	if int(res.get("roll", 0)) > 0:
		var cid := String(res.get("card", ""))
		var card_text := ""
		if cid != "":
			var card: Dictionary = _duel.cards_by_id.get(cid, {})
			card_text = "，打出「%s」" % String(card.get("name"))
		_log_label.text = "%s 掷出 %d 点%s。" % [String(_level.get("opponent")), int(res.get("roll")), card_text]
	_refresh()
	_busy = false


func _show_result() -> void:
	_refresh()
	var won: bool = _duel.winner == "player"
	var lines := String(_level.get("win_line") if won else _level.get("lose_line"))
	var reward_note := ""
	if won:
		var level_id := String(_level.get("id"))
		if _life != null and _life.mark_duel_cleared(level_id):
			var amount := int(_level.get("first_clear_reward", 0))
			if amount > 0:
				_life.add_money(amount, "训练谷首通 · %s" % String(_level.get("name")))
				reward_note = "\n首通奖励 %d 文已入账。" % amount
				reward_earned.emit(amount, String(_level.get("name")))
		else:
			reward_note = "\n（重复通关无奖励）"
	_log_label.text = ("你赢了！" if won else "这一局输了。") + "\n" + lines + reward_note
	_log_label.text += "\n失败无惩罚，随时可以再来一局。"
	_set_footer("", Callable())
	# 结算按钮：再来一局 / 返回
	var again := _make_wide_button("再来一局（无惩罚）", func() -> void: _start_duel())
	_content_reuse(again)
	var back := _make_wide_button("返回关卡列表", _back_to_select)
	_content_reuse(back)


## 结算复用手牌区摆两个宽按钮（避开 scroll 隐藏态）。
func _content_reuse(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(330, 54)
	_hand_box.add_child(btn)


## ---------- UI 构建 ----------

func _build_ui() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.hide()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-390, -350)
	_panel.size = Vector2(780, 700)
	_panel.add_theme_stylebox_override("panel", _card_style(COLOR_BG, COLOR_BORDER))
	_root.add_child(_panel)

	_title = _content_label("熊熊有招", 26, COLOR_TITLE)
	_title.position = Vector2(32, 20)
	_title.size = Vector2(716, 38)
	_panel.add_child(_title)

	_subtitle = _content_label("", 16, COLOR_SUB)
	_subtitle.position = Vector2(32, 60)
	_subtitle.size = Vector2(716, 24)
	_panel.add_child(_subtitle)

	# 对局视图（默认隐藏）
	_duel_box = VBoxContainer.new()
	_duel_box.position = Vector2(32, 96)
	_duel_box.size = Vector2(716, 524)
	_duel_box.add_theme_constant_override("separation", 10)
	_duel_box.hide()
	_panel.add_child(_duel_box)

	_hp_label = _content_label("", 18, COLOR_TEXT)
	_hp_label.custom_minimum_size.x = 700.0
	_duel_box.add_child(_hp_label)

	_hp_me_bar = ColorRect.new()
	_hp_me_bar.color = COLOR_HP_ME
	_hp_me_bar.custom_minimum_size = Vector2(240, 12)
	_duel_box.add_child(_hp_me_bar)
	_hp_foe_bar = ColorRect.new()
	_hp_foe_bar.color = COLOR_HP_FOE
	_hp_foe_bar.custom_minimum_size = Vector2(240, 12)
	_duel_box.add_child(_hp_foe_bar)

	_dice_label = _content_label("", 30, COLOR_TITLE)
	_dice_label.custom_minimum_size.x = 700.0
	_duel_box.add_child(_dice_label)

	_phase_label = _content_label("", 17, COLOR_SUB)
	_phase_label.custom_minimum_size.x = 700.0
	_duel_box.add_child(_phase_label)

	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 10)
	_duel_box.add_child(_hand_box)

	_log_label = _content_label("", 15, COLOR_TEXT)
	_log_label.custom_minimum_size.x = 700.0
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size.y = 150.0
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_duel_box.add_child(_log_label)

	# 选择视图
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(32, 96)
	_scroll.size = Vector2(716, 524)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.custom_minimum_size.x = 688
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)

	_footer = Button.new()
	_footer.position = Vector2(32, 632)
	_footer.size = Vector2(716, 52)
	_footer.add_theme_font_override("font", FONT)
	_footer.add_theme_font_size_override("font_size", 18)
	_footer.add_theme_color_override("font_color", COLOR_TEXT)
	_footer.add_theme_stylebox_override("normal", _card_style(COLOR_ACCENT, Color("4a2619")))
	_footer.add_theme_stylebox_override("hover", _card_style(Color("c0603e"), Color("4a2619")))
	_footer.hide()
	_panel.add_child(_footer)


func _set_footer(text: String, on_pressed: Callable) -> void:
	if text.is_empty():
		_footer.hide()
		return
	_footer.text = text
	for connection in _footer.pressed.get_connections():
		_footer.pressed.disconnect(connection["callable"])
	if on_pressed.is_valid():
		_footer.pressed.connect(on_pressed)
	_footer.show()


func _set_pass(text: String, on_pressed: Callable) -> void:
	if _pass_btn == null:
		_pass_btn = _make_wide_button(text, on_pressed)
		_duel_box.add_child(_pass_btn)
		return
	if text.is_empty():
		_pass_btn.hide()
		return
	_pass_btn.text = text
	for connection in _pass_btn.pressed.get_connections():
		_pass_btn.pressed.disconnect(connection["callable"])
	_pass_btn.pressed.connect(on_pressed)
	_pass_btn.show()


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()


func _make_card(icon_char: String, title_text: String, sub_text: String, on_pressed: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(688, 78)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if disabled:
		button.disabled = true
		button.add_theme_stylebox_override("normal", _card_style(Color("452a1c"), Color("6b4a33")))
		button.add_theme_stylebox_override("disabled", _card_style(Color("452a1c"), Color("6b4a33")))
	else:
		button.add_theme_stylebox_override("normal", _card_style(COLOR_CARD, COLOR_BORDER))
		button.add_theme_stylebox_override("hover", _card_style(Color("7d4c30"), COLOR_TITLE))
		button.add_theme_stylebox_override("pressed", _card_style(Color("472a19"), COLOR_BORDER))
	button.pressed.connect(on_pressed)

	var icon := Panel.new()
	icon.position = Vector2(13, 13)
	icon.size = Vector2(52, 52)
	var icon_style := _flat_style(COLOR_ICON_BG)
	icon_style.set_corner_radius_all(6)
	icon.add_theme_stylebox_override("panel", icon_style)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var icon_label := _content_label(icon_char, 20, COLOR_TITLE)
	icon_label.size = Vector2(52, 52)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_child(icon_label)

	var title := _content_label(title_text, 18, COLOR_TEXT)
	title.position = Vector2(78, 12)
	title.size = Vector2(500, 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title)
	var sub := _content_label(sub_text, 13, COLOR_SUB)
	sub.position = Vector2(78, 42)
	sub.size = Vector2(600, 24)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(sub)
	return button


func _make_wide_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(700, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _card_style(COLOR_CARD, COLOR_BORDER))
	button.add_theme_stylebox_override("hover", _card_style(Color("7d4c30"), COLOR_TITLE))
	button.pressed.connect(on_pressed)
	return button


func _content_label(value: String, font_size: int, color: Color, wrap_width := 0.0) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("23170f"))
	label.add_theme_constant_override("outline_size", 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if wrap_width > 0.0:
		label.custom_minimum_size.x = wrap_width
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _body_label(value: String, font_size: int, color: Color) -> Label:
	return _content_label(value, font_size, color, 680.0)


func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	return style


func _flat_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	return style
