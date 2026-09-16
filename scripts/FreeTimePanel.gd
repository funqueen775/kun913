extends CanvasLayer
## 自由周末面板：每 3 个月一次（第 3/6/9…月），玩家自主决定这段时间给什么。
## 流程（剧情册 V5.27 §11）：时间卡片「第 X 月·周末到了」→ 选区域 → 选活动
## → 小事件（部分带决策点）→ 结算反馈 + 好感度变化（隐藏）→ 雨天 D6 共伞彩蛋。
## 2026-09-16 重排：两列卡片网格 + 字号提级 + 内容滚动兜底 + 弹出/切换动画。
## 数据全部来自 data/story/free_time_system.json v1.3；数值结算在 MonthlyLife。
## 选人环节 MVP 不做（用户拍板）：双人/团建活动的同行 NPC 由系统随机指派。

signal weekend_closed(month: int)
signal memo_requested(event_id: String, memo: Dictionary)
## 玩家选定的组团（值形如 "D_树影书院" / "心湖"）。小镇据此把地面指引线铺到那个区域；
## 空字符串表示清掉上个周末留下的目的地。
signal zone_focused(zone_label: String)

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const CONFIG_PATH := "res://data/story/free_time_system.json"

const ACTIVITY_NAMES := {
	"S1_library_study": "图书馆自习",
	"S2_lakeside_walk": "湖边独走",
	"S3_rooftop_breeze": "天台吹风",
	"S4_weekend_overtime": "工位加班",
	"D1_coffee_chat": "食堂约饭",
	"D2_lakeside_deep_talk": "湖边散步深谈",
	"D3_lawn_sports": "球场打球",
	"D4_camp_bbq": "夜宵烧烤",
	"D5_study_together": "一起自习",
	"D6_rain_umbrella": "雨天共伞",
	"G1_trust_escape_room": "密室逃脱",
	"G2_campfire": "篝火晚会",
	"G3_board_game": "桌游局",
	"G4_annual_show_rehearsal": "年会节目排练",
	"W1_reproduce_paper": "复现一篇论文",
	"W2_own_project": "做自己的小项目",
	"W3_tech_blog": "写一篇技术博客",
	"W4_team_tool": "给团队造个小工具",
	"W5_postmortem_notes": "写复盘笔记",
}
## 活动一句话标签（区域卡 / 活动卡副文本用）。
const ACTIVITY_TAGS := {
	"S2_lakeside_walk": "独处",
	"S3_rooftop_breeze": "天台",
	"S4_weekend_overtime": "加班",
	"D1_coffee_chat": "约饭",
	"D2_lakeside_deep_talk": "深谈",
	"D3_lawn_sports": "打球",
	"D4_camp_bbq": "烧烤",
	"G1_trust_escape_room": "密室",
	"G2_campfire": "篝火",
	"G4_annual_show_rehearsal": "排练",
	"W1_reproduce_paper": "论文",
	"W2_own_project": "项目",
	"W3_tech_blog": "博客",
	"W4_team_tool": "工具",
	"W5_postmortem_notes": "复盘",
}
const ZONE_NAMES := {
	"A_总部": "A 总部",
	"B_科技丘": "B 科技丘",
	"C_水巷": "C 水巷",
	"D_树影书院": "D 树影书院",
	"E_训练谷": "E 训练谷",
	"H_慢生活园": "H 慢生活园",
	"心湖": "心湖",
	"心湖步道": "心湖步道",
}
## 区域卡图标占位字（第二步换像素小图）。
const ZONE_ICONS := {
	"A_总部": "总",
	"B_科技丘": "丘",
	"C_水巷": "巷",
	"D_树影书院": "书",
	"E_训练谷": "训",
	"H_慢生活园": "园",
	"心湖": "湖",
	"心湖步道": "湖",
}
const COLOR_BG := Color("54321f")
const COLOR_BORDER := Color("d49a4c")
const COLOR_TITLE := Color("ffe5a8")
const COLOR_TEXT := Color("fff8e8")
const COLOR_SUB := Color("d5b77b")
const COLOR_CARD := Color("6b3f26")
const COLOR_ICON_BG := Color("8a5a38")
const COLOR_ACCENT := Color("a34a32")
## 解锁阶段 = 当前月份所属区间（口径见 free_time_system schedule.unlocks）。
## 2026-09-16 用户拍板：不分局，一局跑完 48 个月；原 game1/2/3 只是阶段 1/2/3，不再是独立局。
## ⚠ 阶段只是「月份区间」，数据字段仍叫 unlock_game（后端 free_time.py 同读这个字段，不改名）。
const STAGE_SPAN_MONTHS := 16
const STAGE_MAX := 3
const DEFAULT_STAGE := 1

var _life
var _config: Dictionary = {}
var _month := 0
var _weather := "sunny"
var _step := "closed"
var _zone := ""
var _activity: Dictionary = {}
var _targets: Array = []
var _summary_lines: Array = []
var _pending_decision: Dictionary = {}

var _root: Control
var _panel: Panel
var _title: Label
var _subtitle: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: Button
var _open_tween: Tween
var _switch_tween: Tween


func setup(life) -> void:
	_life = life


func _ready() -> void:
	layer = 150
	_config = _load_config()
	_build_ui()


func _load_config() -> Dictionary:
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## ---------- 数据口径（探针直接测这些） ----------

## 月份 → 阶段：1-16 → 1，17-32 → 2，33-48 → 3。越界夹到 [1, 3]。
func stage_for_month(month: int) -> int:
	if month <= 0:
		return DEFAULT_STAGE
	return clampi(int((month - 1) / STAGE_SPAN_MONTHS) + 1, DEFAULT_STAGE, STAGE_MAX)


## 面板当前阶段（open_for_month 之后按当月算，未开面板时按 _month=0 → 阶段 1）。
func current_stage() -> int:
	return stage_for_month(_month)


## 当前阶段可选的活动（排除未解锁阶段与自动触发的 D6）。
func unlocked_activities() -> Array:
	var stage := current_stage()
	var result: Array = []
	for activity in _config.get("activities", []):
		if not activity is Dictionary:
			continue
		var unlock := int(activity.get("unlock_game", DEFAULT_STAGE))
		if unlock > stage:
			continue
		if activity.has("weather_req") or activity.has("auto_trigger"):
			continue
		result.append(activity)
	return result


## 有活动可玩的区域列表（多区域活动拆成多行）。
func zone_list() -> Array:
	var seen := {}
	var result: Array = []
	for activity in unlocked_activities():
		var raw := String(activity.get("zone", ""))
		for zone in raw.split("|"):
			if zone.is_empty() or seen.has(zone):
				continue
			seen[zone] = true
			result.append(zone)
	return result


func zone_display(zone: String) -> String:
	return String(ZONE_NAMES.get(zone, zone))


func activities_for_zone(zone: String) -> Array:
	var result: Array = []
	for activity in unlocked_activities():
		if String(activity.get("zone", "")).split("|").has(zone):
			result.append(activity)
	return result


## 随机指派同行者：双人 1 人、三人团 2 人、团队/独处不指派。
func auto_targets(activity: Dictionary) -> Array:
	var type := String(activity.get("type", "solo"))
	var candidates: Array = activity.get("candidates", ["wang_ge", "xiao_lin", "xiao_zhao", "lao_zhou"])
	if type == "duo":
		return [candidates.pick_random()]
	if type == "group":
		var pool := candidates.duplicate()
		pool.shuffle()
		var count := mini(2, pool.size())
		return pool.slice(0, count)
	return []


## ---------- 交互流转 ----------

func open_for_month(month: int) -> void:
	_month = month
	_weather = _life.roll_weather() if _life != null else "sunny"
	_step = "card"
	_zone = ""
	_activity = {}
	_targets = []
	_summary_lines = []
	_pending_decision = {}
	_root.show()
	_show_card()
	_play_open_animation()
	# 新一个周末开始了，上个周末的目的地要作废：组团得重选。
	zone_focused.emit("")


func is_open() -> bool:
	return _step != "closed"


func close() -> void:
	var month := _month
	_step = "closed"
	_root.hide()
	weekend_closed.emit(month)


func choose_zone(zone: String) -> void:
	_zone = zone
	zone_focused.emit(zone)
	_step = "activity"
	_show_activities()
	# 一选完组团就把地面指引线指过去，玩家关掉面板后不用再猜要往哪走。
	zone_focused.emit(zone)


func choose_activity(activity_id: String) -> Dictionary:
	_activity = {}
	for activity in unlocked_activities():
		if String(activity.get("activity_id", "")) == activity_id:
			_activity = activity
			break
	if _activity.is_empty():
		return {"lines": [], "feedback": "没有这个活动。"}
	# 直接点活动（没经过选组团）时 _zone 还是空的：拿活动自己的 zone 补上，
	# 多区域活动（"A_总部|心湖"）取第一个当目的地。
	if _zone.is_empty():
		var first_zone := String(_activity.get("zone", "")).split("|")[0]
		if not first_zone.is_empty():
			_zone = first_zone
			zone_focused.emit(first_zone)
	_targets = auto_targets(_activity)
	_summary_lines = []
	if _life != null:
		var result: Dictionary = _life.apply_weekend_activity(_activity, _targets)
		_summary_lines = result.get("lines", [])
	# 埋点：explore_click 扩展字段（free_time_system tracking_spec）。
	# 防御式取 ApiClient：--script 探针模式没有 autoload，硬引用会在探针里炸。
	var api := get_node_or_null("/root/ApiClient")
	if api != null:
		api.record_event("explore_click", {
			"slotIndex": _month,
			"zone": _zone,
			"activityId": activity_id,
			"targets": _targets,
			"weather": _weather,
		})
	if _should_show_decision():
		_step = "decision"
		_pending_decision = _activity.get("decision", {})
		_show_decision()
	else:
		_step = "event"
		_show_event()
	return {"lines": _summary_lines, "activity": _activity}


func _should_show_decision() -> bool:
	if not _activity.has("decision"):
		return false
	var node_id := String(_activity.get("decision", {}).get("node_id", ""))
	match node_id:
		"g2_mic_pass":
			# 熊总 30% 概率在场（原型 #27）
			return randf() < 0.3
		"d2_intimate_reply":
			# 知心时刻：好感 ≥ 40 且一次性
			if _targets.is_empty() or _life == null:
				return false
			var npc_id := String(_targets[0])
			return _life.can_trigger_intimate(npc_id)
		_:
			return true


func choose_decision_option(option_id: String) -> Dictionary:
	var options: Array = _pending_decision.get("options", [])
	var option: Dictionary = {}
	for candidate in options:
		if String(candidate.get("option_id", "")) == option_id:
			option = candidate
			break
	if option.is_empty() or _life == null:
		return {"lines": [], "feedback": "没有这个选项。"}
	var target := String(_targets[0]) if not _targets.is_empty() else ""
	if String(_pending_decision.get("node_id", "")) == "d2_intimate_reply" and not target.is_empty():
		_life.mark_intimate_used(target)
	var result: Dictionary = _life.apply_decision_option(_activity, option, target)
	for line in result.get("lines", []):
		_summary_lines.append(line)
	# G4 报台上占用下个自由周末（free_time_system hooks.cost）
	if option.has("hooks") and String(option["hooks"].get("cost", "")).contains("占用下个自由周末"):
		_summary_lines.append("彩排加练占用了下个自由周末。")
	var feedback := String(result.get("feedback", ""))
	if not feedback.is_empty():
		_summary_lines.append(feedback)
	_step = "event"
	_pending_decision = {}
	_show_event()
	return result


## ---------- 展示 ----------

func _weather_text() -> String:
	return "☀ 天气：晴" if _weather == "sunny" else "🌧 天气：雨"


func _zone_subtitle(zone: String) -> String:
	var activities := activities_for_zone(zone)
	var tags: Array[String] = []
	for activity in activities:
		if tags.size() >= 2:
			break
		var tag := String(ACTIVITY_TAGS.get(String(activity.get("activity_id", "")), ""))
		if not tag.is_empty():
			tags.append(tag)
	if tags.is_empty():
		return "%d 个活动" % activities.size()
	return "%d 个活动 · %s" % [activities.size(), " / ".join(tags)]


func _activity_subtitle(activity: Dictionary) -> String:
	var parts: Array[String] = []
	var tag := String(ACTIVITY_TAGS.get(String(activity.get("activity_id", "")), ""))
	if not tag.is_empty():
		parts.append(tag)
	parts.append("%d 秒" % int(activity.get("estimated_seconds", 30)))
	var type := String(activity.get("type", "solo"))
	if type == "duo" or type == "group":
		parts.append("随机同行")
	return " · ".join(parts)


func _show_card() -> void:
	_title.text = "第 %d 月 · 周末到了" % _month
	_subtitle.text = _weather_text()
	_clear_content()
	var body := _body_label("忙完这个月的活，周末是你的了。\n\n这段时间给谁、给什么，你自己定。\n出去走走，或者给自己安排点什么——都是你的选择。", 17, COLOR_TEXT)
	_content.add_child(body)
	_set_footer("出门逛逛", func(): _step = "zone"; _show_zones())


func _show_zones() -> void:
	_title.text = "去哪儿？"
	_subtitle.text = "坐上小火车，选一片区域下车。"
	_clear_content()
	var grid := _make_grid()
	for zone in zone_list():
		var zone_key := String(zone)
		var card := _make_card(
			String(ZONE_ICONS.get(zone_key, "镇")),
			zone_display(zone_key),
			_zone_subtitle(zone_key),
			func(): choose_zone(zone_key)
		)
		grid.add_child(card)
	_content.add_child(grid)
	_set_footer("", Callable())


func _show_activities() -> void:
	_title.text = "%s · 玩点什么？" % zone_display(_zone)
	_subtitle.text = _weather_text()
	_clear_content()
	var grid := _make_grid()
	for activity in activities_for_zone(_zone):
		var activity_id := String(activity["activity_id"])
		var card := _make_card(
			String(ZONE_ICONS.get(_zone, "玩")),
			String(ACTIVITY_NAMES.get(activity_id, activity_id)),
			_activity_subtitle(activity),
			func(): choose_activity(activity_id)
		)
		grid.add_child(card)
	_content.add_child(grid)
	_set_footer("回车站", func(): _step = "zone"; _show_zones())


func _decision_intro() -> String:
	var trigger := String(_pending_decision.get("trigger_text", ""))
	var stuck := String(_targets[0]) if not _targets.is_empty() else ""
	var npc_name := "同伴"
	if _life != null and not stuck.is_empty():
		npc_name = String(_life.NPC_NAMES.get(stuck, stuck))
	return trigger.replace("{stuck_npc}", npc_name)


func _show_decision() -> void:
	_title.text = String(ACTIVITY_NAMES.get(String(_activity.get("activity_id", "")), "")) + " · 要紧关头"
	_subtitle.text = ""
	_clear_content()
	_content.add_child(_body_label(_decision_intro(), 18, COLOR_TEXT))
	for option in _pending_decision.get("options", []):
		var option_id := String(option["option_id"])
		var text := String(option["text"])
		var choice := _make_wide_button(text, func(): choose_decision_option(option_id))
		_content.add_child(choice)
	_set_footer("", Callable())


func _show_event() -> void:
	_title.text = String(ACTIVITY_NAMES.get(String(_activity.get("activity_id", "")), "自由活动")) + " · 结束了"
	_subtitle.text = _weather_text()
	_clear_content()
	var instant := String(_activity.get("instant_feedback", ""))
	if not instant.is_empty():
		_content.add_child(_body_label(instant, 17, COLOR_TEXT))
	for line in _summary_lines:
		_content.add_child(_body_label("· %s" % String(line), 15, COLOR_SUB))
	if _weather == "rainy":
		var d6_text := _append_d6()
		if not d6_text.is_empty():
			_content.add_child(_body_label(d6_text.strip_edges(), 16, COLOR_TITLE))
	_set_footer("回宿舍", close)


## D6 雨天共伞彩蛋：雨天自动触发（MVP 简化：只要下雨就走一次），
## 好感 +6 并落一张「那把伞」特殊便签进记忆墙。
func _append_d6() -> String:
	if _life == null:
		return ""
	var d6: Dictionary = _life.apply_d6_umbrella()
	memo_requested.emit("D6_rain_umbrella", {"text": "那把伞", "tone": "gray-gold", "npc": d6.get("npcName", "")})
	return "—— 彩蛋 · 那把伞 ——\n%s\n%s 好感 +%d" % [
		String(d6.get("text", "")), String(d6.get("npcName", "")), int(d6.get("delta", 0)),
	]


## ---------- 动画 ----------

func _play_open_animation() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.94, 0.94)
	_panel.modulate.a = 0.0
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_panel, "modulate:a", 1.0, 0.22)


func _play_switch_animation() -> void:
	if _switch_tween != null and _switch_tween.is_valid():
		_switch_tween.kill()
	_content.modulate.a = 0.0
	_scroll.position.y = 112.0
	_switch_tween = create_tween()
	_switch_tween.set_parallel(true)
	_switch_tween.tween_property(_content, "modulate:a", 1.0, 0.18)
	_switch_tween.tween_property(_scroll, "position:y", 100.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## ---------- UI ----------

func _build_ui() -> void:
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
	_panel.position = Vector2(-380, -340)
	_panel.size = Vector2(760, 680)
	_panel.add_theme_stylebox_override("panel", _card_style(COLOR_BG, COLOR_BORDER))
	_root.add_child(_panel)

	_title = _content_label("自由周末", 26, COLOR_TITLE)
	_title.position = Vector2(32, 22)
	_title.size = Vector2(696, 38)
	_panel.add_child(_title)

	_subtitle = _content_label("", 17, COLOR_SUB)
	_subtitle.position = Vector2(32, 64)
	_subtitle.size = Vector2(696, 26)
	_panel.add_child(_subtitle)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(32, 100)
	_scroll.size = Vector2(696, 486)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.custom_minimum_size.x = 668
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)

	_footer = Button.new()
	_footer.position = Vector2(32, 604)
	_footer.size = Vector2(696, 52)
	_footer.add_theme_font_override("font", FONT)
	_footer.add_theme_font_size_override("font_size", 19)
	_footer.add_theme_color_override("font_color", COLOR_TEXT)
	_footer.add_theme_stylebox_override("normal", _card_style(COLOR_ACCENT, Color("4a2619")))
	_footer.add_theme_stylebox_override("hover", _card_style(Color("c0603e"), Color("4a2619")))
	_footer.hide()
	_panel.add_child(_footer)


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()
	_play_switch_animation()


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


## 区域 / 活动卡：图标方块 + 标题 + 副文本，整卡可点。
func _make_card(icon_char: String, title_text: String, sub_text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(328, 78)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	icon_label.position = Vector2(0, 0)
	icon_label.size = Vector2(52, 52)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_child(icon_label)

	var title := _content_label(title_text, 18, COLOR_TEXT)
	title.position = Vector2(78, 12)
	title.size = Vector2(236, 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title)
	var sub := _content_label(sub_text, 13, COLOR_SUB)
	sub.position = Vector2(78, 42)
	sub.size = Vector2(236, 24)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(sub)
	return button


func _make_wide_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(668, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _card_style(COLOR_CARD, COLOR_BORDER))
	button.add_theme_stylebox_override("hover", _card_style(Color("7d4c30"), COLOR_TITLE))
	button.pressed.connect(on_pressed)
	return button


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


## 正文区标签（在 VBox/滚动容器里，需要给 autowrap 一个宽度下限）。
func _body_label(value: String, font_size: int, color: Color) -> Label:
	return _content_label(value, font_size, color, 660.0)


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
