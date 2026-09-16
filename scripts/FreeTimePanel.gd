extends CanvasLayer
## 自由周末面板：每 3 个月一次（第 3/6/9…月），玩家自主决定这段时间给什么。
## 流程（剧情册 V5.27 §11）：时间卡片「第 X 月·周末到了」→ 选区域 → 选活动
## → 小事件（部分带决策点）→ 结算反馈 + 好感度变化（隐藏）→ 雨天 D6 共伞彩蛋。
## 数据全部来自 data/story/free_time_system.json v1.3；数值结算在 MonthlyLife。
## 选人环节 MVP 不做（用户拍板）：双人/团建活动的同行 NPC 由系统随机指派。

signal weekend_closed(month: int)
signal memo_requested(event_id: String, memo: Dictionary)

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
## 本期解锁档位（free_time_system schedule.unlocks：1-16 月 = game1）。
const CURRENT_GAME := 1

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
var _title: Label
var _body: Label
var _buttons: VBoxContainer
var _close_button: Button


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

## 当前档位可选的活动（排除未解锁档位与自动触发的 D6）。
func unlocked_activities() -> Array:
	var result: Array = []
	for activity in _config.get("activities", []):
		if not activity is Dictionary:
			continue
		var unlock := int(activity.get("unlock_game", CURRENT_GAME))
		if unlock > CURRENT_GAME:
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


func is_open() -> bool:
	return _step != "closed"


func close() -> void:
	var month := _month
	_step = "closed"
	_root.hide()
	weekend_closed.emit(month)


func choose_zone(zone: String) -> void:
	_zone = zone
	_step = "activity"
	_show_activities()


func choose_activity(activity_id: String) -> Dictionary:
	_activity = {}
	for activity in unlocked_activities():
		if String(activity.get("activity_id", "")) == activity_id:
			_activity = activity
			break
	if _activity.is_empty():
		return {"lines": [], "feedback": "没有这个活动。"}
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


func _show_card() -> void:
	_title.text = "第 %d 月 · 周末到了" % _month
	_body.text = "忙完这个月的活，周末是你的了。\n%s\n\n这段时间给谁、给什么，你自己定。" % _weather_text()
	_clear_buttons()
	_add_button("出门逛逛", func(): _step = "zone"; _show_zones())


func _show_zones() -> void:
	_title.text = "去哪儿？"
	_body.text = "坐上小火车，选一片区域下车。"
	_clear_buttons()
	for zone in zone_list():
		var zone_key := String(zone)
		_add_button(zone_display(zone_key), func(): choose_zone(zone_key))


func _show_activities() -> void:
	_title.text = "%s · 玩点什么？" % zone_display(_zone)
	_body.text = _weather_text()
	_clear_buttons()
	for activity in activities_for_zone(_zone):
		var activity_id := String(activity["activity_id"])
		var label := String(ACTIVITY_NAMES.get(activity_id, activity_id))
		var type := String(activity.get("type", "solo"))
		if type == "duo" or type == "group":
			label += "（随机同行）"
		_add_button(label, func(): choose_activity(activity_id))
	_add_button("回车站", func(): _step = "zone"; _show_zones())


func _decision_intro() -> String:
	var trigger := String(_pending_decision.get("trigger_text", ""))
	var stuck := String(_targets[0]) if not _targets.is_empty() else ""
	var npc_name := "同伴"
	if _life != null:
		npc_name = String(_life.NPC_NAMES.get(stuck, stuck)) if not stuck.is_empty() else npc_name
	return trigger.replace("{stuck_npc}", npc_name)


func _show_decision() -> void:
	_title.text = String(ACTIVITY_NAMES.get(String(_activity.get("activity_id", "")), "")) + " · 要紧关头"
	_body.text = _decision_intro()
	_clear_buttons()
	for option in _pending_decision.get("options", []):
		var option_id := String(option["option_id"])
		var label := String(option["text"])
		_add_button(label, func(): choose_decision_option(option_id))


func _show_event() -> void:
	_title.text = String(ACTIVITY_NAMES.get(String(_activity.get("activity_id", "")), "自由活动")) + " · 结束了"
	var lines := ""
	var instant := String(_activity.get("instant_feedback", ""))
	if not instant.is_empty():
		lines += instant + "\n"
	for line in _summary_lines:
		lines += "· %s\n" % String(line)
	if _weather == "rainy":
		lines += _append_d6()
	_body.text = lines.strip_edges()
	_clear_buttons()
	_add_button("回宿舍", close)


## D6 雨天共伞彩蛋：雨天自动触发（MVP 简化：只要下雨就走一次），
## 好感 +6 并落一张「那把伞」特殊便签进记忆墙。
func _append_d6() -> String:
	if _life == null:
		return ""
	var d6: Dictionary = _life.apply_d6_umbrella()
	memo_requested.emit("D6_rain_umbrella", {"text": "那把伞", "tone": "gray-gold", "npc": d6.get("npcName", "")})
	return "\n—— 彩蛋 · 那把伞 ——\n%s\n%s 好感 +%d" % [
		String(d6.get("text", "")), String(d6.get("npcName", "")), int(d6.get("delta", 0)),
	]


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

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -320)
	panel.size = Vector2(660, 640)
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)

	_title = _label("自由周末", 24, Color("ffe5a8"))
	_title.position = Vector2(28, 20)
	_title.size = Vector2(604, 34)
	panel.add_child(_title)

	_body = _label("", 16, Color("fff8e8"))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 604
	_body.max_lines_visible = 14
	_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body.position = Vector2(28, 62)
	_body.size = Vector2(604, 220)
	panel.add_child(_body)

	_buttons = VBoxContainer.new()
	_buttons.position = Vector2(28, 296)
	_buttons.size = Vector2(604, 300)
	_buttons.add_theme_constant_override("separation", 10)
	panel.add_child(_buttons)


func _clear_buttons() -> void:
	for child in _buttons.get_children():
		child.queue_free()


func _add_button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(604, 44)
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("fff0c9"))
	button.add_theme_stylebox_override("normal", _button_style(Color("7a4630")))
	button.add_theme_stylebox_override("hover", _button_style(Color("a35a3a")))
	button.pressed.connect(on_pressed)
	_buttons.add_child(button)


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
	style.bg_color = Color("54321f", 0.96)
	style.border_color = Color("d49a4c")
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := _panel_style()
	style.bg_color = color
	style.border_color = Color("4a2619")
	return style
