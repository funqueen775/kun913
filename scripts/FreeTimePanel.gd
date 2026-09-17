extends CanvasLayer
## 自由周末面板：每 3 个月一次（第 3/6/9…月），玩家自主决定这段时间给什么。
## 流程（剧情册 V5.27 §11）：时间卡片「第 X 月·周末到了」→ 选区域 → 选活动
## → 小事件（部分带决策点）→ 结算反馈 + 好感度变化（隐藏）→ 雨天 D6 共伞彩蛋。
## 2026-09-16 重排：两列卡片网格 + 字号提级 + 内容滚动兜底 + 弹出/切换动画。
## 数据全部来自 data/story/free_time_system.json v1.3；数值结算在 MonthlyLife。
## 选人环节 MVP 不做（用户拍板）：双人/团建活动的同行 NPC 由系统随机指派。

signal weekend_closed(month: int)
signal memo_requested(event_id: String, memo: Dictionary)
## 一个周末的完整手账记录（§7.2 weekend_ledger）。小镇侧落 workplace_town_weekends.jsonl。
signal weekend_ledger(record: Dictionary)
## 玩家选定的组团（值形如 "D_树影书院" / "心湖"）。小镇据此把地面指引线铺到那个区域；
## 空字符串表示清掉上个周末留下的目的地。
signal zone_focused(zone_label: String)

## 一个自由周末 = 周六 2 格（设计文档 §3.1 / §13.1：周六 2 格 + 周日自由）。
## 周日**不进这张表**：它没有额度、不出结算、不铺引导线。
const SLOT_IDS: Array[String] = ["sat_am", "sat_pm"]
const SEGMENT_LABELS: Array[String] = ["周六上午", "周六下午"]
const SLOT_COUNT := 2

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
## 组团名 → 契约 regionId 字母。契约对**每个**事件强制 payload.regionId 匹配 ^[A-H]$
## （server.py post_event），所以自由活动的埋点也必须带这个字段。
## 「心湖 / 心湖步道」在 A–H 里没有独立字母，按设计文档 §12 口径算 A（主城核心景观带）。
## 副作用已知：zone_dwell 的空间偏好统计会把心湖停留记进 A。
const ZONE_CODES := {
	"A_总部": "A",
	"B_科技丘": "B",
	"C_水巷": "C",
	"D_树影书院": "D",
	"E_训练谷": "E",
	"H_慢生活园": "H",
	"心湖": "A",
	"心湖步道": "A",
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
## 周六两格。每格 {slotId, zone, activityId, activity, targets, labels}；activity 为空 = 留白。
var _slots: Array = []
## 正在编辑第几格（begin_slot 设，choose_activity 用完即回 slots）。
var _editing_slot := -1
## commit_weekend() 的逐格结算结果 + 组合效果（手账页只读这两个）。
var _slot_results: Array = []
var _combo: Dictionary = {}
var _note_edit: LineEdit
## B 件·在场一幕：演了哪一格 / 选了哪个应答 / 结算结果（只含标签，不含数值）。
var _encounter_slot := -1
var _encounter_option: Dictionary = {}
var _encounter_result: Dictionary = {}

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


## 组团名 → 契约 regionId（A–H 单字母）。查表优先，其次取 "D_树影书院" 这类前缀字母；
## 两者都落空时兜底 "A"——宁可标成总部，也不要发空串被服务端 400 拒。
func zone_region_id(zone: String) -> String:
	var code := String(ZONE_CODES.get(zone, ""))
	if code.is_empty():
		code = zone.strip_edges().split("_")[0].to_upper()
	if code.length() == 1 and "ABCDEFGH".contains(code):
		return code
	return "A"


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
	_zone = ""
	_activity = {}
	_targets = []
	_summary_lines = []
	_pending_decision = {}
	_slot_results = []
	_combo = {}
	_note_edit = null
	_encounter_slot = -1
	_encounter_option = {}
	_encounter_result = {}
	_editing_slot = -1
	_slots = []
	for slot_id in SLOT_IDS:
		_slots.append(_blank_slot(slot_id))
	_step = "slots"
	_root.show()
	_show_slots()
	_play_open_animation()
	# 新一个周末开始了，上个周末的目的地要作废：组团得重选。
	zone_focused.emit("")


func _blank_slot(slot_id: String) -> Dictionary:
	return {
		"slotId": slot_id,
		"zone": "",
		"activityId": "",
		"activity": {},
		"targets": [],
		"labels": [],
	}


## 周六两格（探针直接读这个）。
func slots() -> Array:
	return _slots


func slot_is_blank(index: int) -> bool:
	if index < 0 or index >= _slots.size():
		return true
	return ((_slots[index] as Dictionary).get("activity") as Dictionary).is_empty()


## 该活动是否已排进别格（§13.2 拍板：同一个活动一个周末只能出现一次）。
func activity_used_elsewhere(activity_id: String, except_index: int) -> bool:
	for i in _slots.size():
		if i == except_index:
			continue
		if String((_slots[i] as Dictionary).get("activityId", "")) == activity_id:
			return true
	return false


## 点某一格 → 给它选区域（填格流程的入口）。
func begin_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	_editing_slot = index
	_zone = String((_slots[index] as Dictionary).get("zone", ""))
	_step = "slots_zone"
	_show_zones()


## 清空一格 = 恢复留白（留白是有效选择，不提示、不惩罚）。
func clear_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	_slots[index] = _blank_slot(SLOT_IDS[index])
	_editing_slot = index
	_step = "slots"
	_show_slots()


func is_open() -> bool:
	return _step != "closed"


func close() -> void:
	var month := _month
	_step = "closed"
	_root.hide()
	weekend_closed.emit(month)


## 为「正在编辑的那一格」选区域 → 进活动列表。**不结算**。
func choose_zone(zone: String) -> void:
	_zone = zone
	_step = "slots_activity"
	_show_activities()
	# 一选完组团就把地面指引线指过去，玩家关掉面板后不用再猜要往哪走。
	zone_focused.emit(zone)


## 把活动填进正在编辑的那一格。**填格不结算**（§3.1）——结算是 commit_weekend() 的事。
## 埋点 explore_click 落在这里：每格最终选的活动就是「投入结构」的来源。
func choose_activity(activity_id: String) -> Dictionary:
	if _editing_slot < 0 or _editing_slot >= _slots.size():
		return {"ok": false, "feedback": "没有正在编辑的那一格。"}
	var activity := {}
	for candidate in unlocked_activities():
		if String(candidate.get("activity_id", "")) == activity_id:
			activity = candidate
			break
	if activity.is_empty():
		return {"ok": false, "feedback": "没有这个活动。"}
	if activity_used_elsewhere(activity_id, _editing_slot):
		return {"ok": false, "feedback": "这个活动已经排进另一格了。"}
	var targets := auto_targets(activity)
	var chosen_zone := _zone
	if chosen_zone.is_empty():
		# 直接点活动（没经过选组团）时 _zone 还是空的：拿活动自己的 zone 补上，
		# 多区域活动（"A_总部|心湖"）取第一个当目的地。
		chosen_zone = String(activity.get("zone", "")).split("|")[0]
	var slot: Dictionary = _slots[_editing_slot]
	slot["zone"] = chosen_zone
	slot["activityId"] = activity_id
	slot["activity"] = activity
	slot["targets"] = targets
	slot["labels"] = _slot_labels(targets)
	_slots[_editing_slot] = slot
	# 埋点：explore_click 扩展字段（free_time_system tracking_spec）。
	# 防御式取 ApiClient：--script 探针模式没有 autoload，硬引用会在探针里炸。
	var api := get_node_or_null("/root/ApiClient")
	if api != null:
		api.record_event("explore_click", {
			"regionId": zone_region_id(chosen_zone),
			"slotIndex": _editing_slot,
			"slotId": String(slot.get("slotId", "")),
			"zone": chosen_zone,
			"activityId": activity_id,
			"targets": targets,
			"weather": _weather,
		})
	_step = "slots"
	_show_slots()
	return {"ok": true, "activity": activity, "slotIndex": _editing_slot, "lines": []}


## 「就这样过」→ 一次性结算（逐格 + 组合），再决定要不要演一次决策点，最后进手账页。
func commit_weekend() -> Dictionary:
	if _life == null:
		return {}
	var result: Dictionary = _life.apply_weekend(_slots)
	_slot_results = result.get("slot_results", [])
	_combo = result.get("combo", {})
	# 一个周末**最多演一屏**：有 decision 就演 decision（B 件让位），没有才退而演在���一幕。
	var decision_slot := _pick_decision_slot()
	var encounter_index := -1
	if decision_slot < 0:
		encounter_index = _pick_encounter_slot()
	if decision_slot >= 0:
		_editing_slot = decision_slot
		_activity = _slots[decision_slot]["activity"]
		_targets = _slots[decision_slot]["targets"]
		_pending_decision = _activity.get("decision", {})
		_step = "decision"
		_show_decision()
	elif encounter_index >= 0:
		_editing_slot = encounter_index
		_encounter_slot = encounter_index
		_activity = _slots[encounter_index]["activity"]
		_targets = _slots[encounter_index]["targets"]
		_zone = String(_slots[encounter_index].get("zone", ""))
		_step = "encounter"
		_show_encounter()
	else:
		_step = "ledger"
		_show_ledger()
	return result


## 一个周末**最多演一次**决策点（§3.3）：取第一格带 decision 且当下成立的那个。
## 其余格降级为普通结算——"那晚后来又聊了两句"写进手账就够。
func _pick_decision_slot() -> int:
	for i in _slots.size():
		var activity = (_slots[i] as Dictionary).get("activity")
		if not (activity is Dictionary) or (activity as Dictionary).is_empty():
			continue
		var act := activity as Dictionary
		if not act.has("decision"):
			continue
		_activity = act
		_targets = (_slots[i] as Dictionary).get("targets", [])
		if _should_show_decision():
			return i
	return -1


## B 件：两格里挑一格演「在场一幕」。条件＝这格有活动 + 有同行者 + 活动配了 encounter。
## 「一个周末最多一屏、decision 优先」由 commit_weekend() 把关，这里只负责找到第一格。
func _pick_encounter_slot() -> int:
	for i in _slots.size():
		var slot = _slots[i]
		if not (slot is Dictionary):
			continue
		var act = (slot as Dictionary).get("activity")
		if not (act is Dictionary) or (act as Dictionary).is_empty():
			continue
		var targets = (slot as Dictionary).get("targets", [])
		if not (targets is Array) or (targets as Array).is_empty():
			continue
		var enc = (act as Dictionary).get("encounter")
		if not (enc is Dictionary) or (enc as Dictionary).is_empty():
			continue
		return i
	return -1


## 同行者的显示名（手账页那几行用；没有同行者就是"一个人"）。
func _slot_labels(targets: Array) -> Array:
	var names: Array = []
	for npc_id in targets:
		var key := String(npc_id)
		names.append(String(_life.NPC_NAMES.get(key, key)) if _life != null else key)
	return names


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
	# 决策是周末内的一幕，演完直接进手账页，不再单独出一屏数字结算。
	_step = "ledger"
	_pending_decision = {}
	_show_ledger()
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


## 新首屏：周六两格总表（§3.1）。填格不结算，底部「就这样过」才一次性结算。
func _show_slots() -> void:
	_title.text = "第 %d 月 · 周末到了" % _month
	_subtitle.text = "%s　·　周六两格，自己排" % _weather_text()
	_clear_content()
	_content.add_child(_body_label("忙完这个月的活，这个周末是你的了。\n两格，给谁、给什么，你自己排——哪一格空着也行。", 17, COLOR_TEXT))
	_content.add_child(_relation_overview_block())
	for i in _slots.size():
		_content.add_child(_make_slot_row(i))
	_set_footer("就这样过", commit_weekend)


## 关系一览（机制文档 §5.4「前台展示关系阶段及进度感」）。
## 此前 MonthlyLife.affinity_level() 全库**没有任何界面读过**，好感一直是个纯隐藏数。
## 红线：只出「档位段数 + 现档称谓」两样，分数 / 阈值 / 解锁条件一律不出现。
func _relation_overview_block() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_content_label("你和他们，走到哪儿了", 16, COLOR_TITLE, 660.0))
	if _life == null:
		return box
	for row in _life.relation_overview():
		box.add_child(_content_label(
			_relation_line(
				String(row.get("name", "")),
				int(row.get("level", 1)),
				String(row.get("stage", "")),
			),
			15, COLOR_SUB, 660.0
		))
	return box


## 一行的统一形状：「王哥　●●●○○　老熟人了」。段数 = 档位，**不是分数**。
func _relation_line(name: String, level: int, stage: String) -> String:
	if stage.is_empty():
		return ""
	var filled := clampi(level, 0, 5)
	return "%s　%s%s　%s" % [name, "●".repeat(filled), "○".repeat(5 - filled), stage]


## 本次两格里出现过的那位唯一同行者（显示名）。没有 / 多于一人的话空串 ——
## 记忆墙据此决定贴不贴「关系档色点」：拿不准就干脆不贴，不猜。
func _sole_target_name() -> String:
	var ids: Array = []
	for i in _slots.size():
		if slot_is_blank(i):
			continue
		for raw in (_slots[i] as Dictionary).get("targets", []):
			var npc_id := String(raw)
			if not ids.has(npc_id):
				ids.append(npc_id)
	if ids.size() != 1 or _life == null:
		return ""
	return String(_life.NPC_NAMES.get(String(ids[0]), ""))


func _make_slot_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card := _make_card(
		"上" if index == 0 else "下",
		String(SEGMENT_LABELS[index]),
		slot_summary(index),
		func(): begin_slot(index)
	)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card)
	if not slot_is_blank(index):
		row.add_child(_make_small_button("清空", func(): clear_slot(index)))
	return row


## 一格的摘要（手账页与两格总表共用）：活动名 + 同行者；留白返回"还没安排"。
func slot_summary(index: int) -> String:
	if index < 0 or index >= _slots.size() or slot_is_blank(index):
		return "还没安排"
	var slot: Dictionary = _slots[index]
	var act := slot.get("activity") as Dictionary
	var aid := String(act.get("activity_id", ""))
	var labels: Array = slot.get("labels", [])
	var who := "一个人"
	if not labels.is_empty():
		who = " / ".join(labels)
	return "%s · %s" % [String(ACTIVITY_NAMES.get(aid, aid)), who]


func _segment_label(index: int) -> String:
	if index >= 0 and index < SEGMENT_LABELS.size():
		return String(SEGMENT_LABELS[index])
	return "这一格"


func _show_zones() -> void:
	_title.text = "%s：去哪儿？" % _segment_label(_editing_slot)
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
	_set_footer("回周末", func(): _step = "slots"; _show_slots())


func _show_activities() -> void:
	_title.text = "%s · %s——玩点什么？" % [_segment_label(_editing_slot), zone_display(_zone)]
	_subtitle.text = _weather_text()
	_clear_content()
	var grid := _make_grid()
	for activity in activities_for_zone(_zone):
		var activity_id := String(activity["activity_id"])
		# §13.2：同一个活动一个周末只能出现一次 → 已填进另一格的置灰不可选。
		var used := activity_used_elsewhere(activity_id, _editing_slot)
		var sub := "已经排进另一格了" if used else _activity_subtitle(activity)
		var card := _make_card(
			String(ZONE_ICONS.get(_zone, "玩")),
			String(ACTIVITY_NAMES.get(activity_id, activity_id)),
			sub,
			func(): choose_activity(activity_id),
			used
		)
		grid.add_child(card)
	_content.add_child(grid)
	_set_footer("回周末", func(): _step = "slots"; _show_slots())


func _decision_intro() -> String:
	var trigger := String(_pending_decision.get("trigger_text", ""))
	var stuck := String(_targets[0]) if not _targets.is_empty() else ""
	var npc_name := "同伴"
	if _life != null and not stuck.is_empty():
		npc_name = String(_life.NPC_NAMES.get(stuck, stuck))
	return trigger.replace("{stuck_npc}", npc_name)


## 知心时刻的收尾问句。**刻意不用 activity.decision.trigger_text** ——
## 那句是「对方讲了一件从没说过的事」的通用铺垫，放在真正的独白**之后**就成了复读。
const INTIMATE_QUESTION := "他停下来，看着你：「你呢？」"


func _show_decision() -> void:
	var node_id := String(_pending_decision.get("node_id", ""))
	var intimate := node_id == "d2_intimate_reply"
	if intimate:
		_title.text = "知心时刻 · %s" % _target_display_name()
		_subtitle.text = "私人故事 · 只此一次"
	else:
		_title.text = String(ACTIVITY_NAMES.get(String(_activity.get("activity_id", "")), "")) + " · 要紧关头"
		_subtitle.text = ""
	_clear_content()
	if intimate:
		# V5.27 §11.3 的四段独白原文，整段先摆出来，再问玩家怎么接。
		var story := _intimate_story()
		if not story.is_empty():
			_content.add_child(_body_label(story, 18, COLOR_TEXT))
		_content.add_child(_body_label(INTIMATE_QUESTION, 18, COLOR_TEXT))
	else:
		_content.add_child(_body_label(_decision_intro(), 18, COLOR_TEXT))
	for option in _pending_decision.get("options", []):
		var option_id := String(option["option_id"])
		var text := String(option["text"])
		var choice := _make_wide_button(text, func(): choose_decision_option(option_id))
		_content.add_child(choice)
	_set_footer("", Callable())


## 当前决策对象（同行者）的显示名。
func _target_display_name() -> String:
	if _life == null or _targets.is_empty():
		return "同伴"
	var npc_id := String(_targets[0])
	return String(_life.NPC_NAMES.get(npc_id, npc_id))


## 知心时刻正文（data/story/free_time_system.json → npcs.<id>.intimate_text）。
## 取不到就返回空串，屏上只留收尾问句 —— **绝不在这里硬编一份备胎文案**，
## 那样文案一改就两处不一致。
func _intimate_story() -> String:
	if _life == null or _targets.is_empty():
		return ""
	return String(_life.intimate_text_of(String(_targets[0])))


## B 件 · 在场一幕（§4）：一屏场景 + 2-3 个应答。**不改任何数值** ——
## 好感与属性早已由 commit_weekend() 结清，这里只是给这场活动一张脸。
func _show_encounter() -> void:
	var act_id := String(_activity.get("activity_id", ""))
	_title.text = "%s · 撞见" % String(ACTIVITY_NAMES.get(act_id, act_id))
	_subtitle.text = "%s　·　%s" % [_segment_label(_editing_slot), zone_display(_zone)]
	_clear_content()
	_content.add_child(_body_label(_encounter_intro(), 18, COLOR_TEXT))
	var enc = _activity.get("encounter")
	if not (enc is Dictionary):
		_set_footer("就这样", _finish_weekend)
		return
	var options = (enc as Dictionary).get("options", [])
	if options is Array:
		for candidate in (options as Array):
			if not (candidate is Dictionary):
				continue
			var option_id := String((candidate as Dictionary).get("option_id", ""))
			var option_text := String((candidate as Dictionary).get("text", option_id))
			_content.add_child(_make_wide_button(option_text, func(): choose_encounter_option(option_id)))
	_set_footer("", Callable())


## 场景句里的 {who} → 随机同行者的显示名。沿用 _decision_intro() 替换 {stuck_npc} 的既有做法。
func _encounter_intro() -> String:
	var enc = _activity.get("encounter")
	var text := "" if not (enc is Dictionary) else String((enc as Dictionary).get("text", ""))
	var who := "同伴"
	if _life != null and not _targets.is_empty():
		who = String(_life.NPC_NAMES.get(String(_targets[0]), String(_targets[0])))
	return text.replace("{who}", who)


## 选定应答 → **只落标签**，随即进手账页。不碰 skill / output / health / 好感任何一个数。
func choose_encounter_option(option_id: String) -> Dictionary:
	var enc = _activity.get("encounter")
	if not (enc is Dictionary):
		return {"ok": false, "feedback": "这一幕没有可应答的选项。"}
	var options = (enc as Dictionary).get("options", [])
	if not (options is Array):
		return {"ok": false, "feedback": "这一幕没有可应答的选项。"}
	var chosen: Dictionary = {}
	for candidate in (options as Array):
		if not (candidate is Dictionary):
			continue
		if String((candidate as Dictionary).get("option_id", "")) == option_id:
			chosen = candidate as Dictionary
			break
	if chosen.is_empty():
		return {"ok": false, "feedback": "没有这个应答。"}
	_encounter_option = chosen
	_encounter_result = _life.apply_encounter_option(chosen) if _life != null else {}
	_step = "ledger"
	_show_ledger()
	return {"ok": true, "option": chosen, "result": _encounter_result}


## 周末手账页（C 件，§5）。
## 红线：**一行数字流水都不出现**——"专业能力 +1" / "王哥 好感 +5" 全部不展示，
## 数值变化降级为方向性的人话（relation_phrase / weekend_structure_line）。
func _show_ledger() -> void:
	_title.text = "第 %d 月 · 周末手账" % _month
	_subtitle.text = _weather_text()
	_clear_content()
	for row in _slot_table_lines():
		_content.add_child(_body_label(String(row), 16, COLOR_TEXT))
	_content.add_child(_separator())
	var enc_lines := _encounter_lines()
	if not enc_lines.is_empty():
		for line in enc_lines:
			_content.add_child(_body_label(String(line), 15, COLOR_SUB))
		_content.add_child(_separator())
	_content.add_child(_body_label("写下你的一句：", 15, COLOR_SUB))
	_note_edit = LineEdit.new()
	_note_edit.placeholder_text = "（可以不写）"
	_note_edit.max_length = 40
	_note_edit.custom_minimum_size = Vector2(660, 44)
	_note_edit.add_theme_font_override("font", FONT)
	_note_edit.add_theme_font_size_override("font_size", 16)
	_note_edit.add_theme_color_override("font_color", COLOR_TEXT)
	_note_edit.add_theme_stylebox_override("normal", _card_style(Color("452a1c"), COLOR_BORDER))
	_note_edit.add_theme_stylebox_override("focus", _card_style(Color("452a1c"), COLOR_TITLE))
	_content.add_child(_note_edit)
	_content.add_child(_separator())
	if _life != null:
		_content.add_child(_body_label(_life.weekend_structure_line(_slots), 16, COLOR_TITLE))
	for status_line in _relation_status_lines():
		_content.add_child(_body_label(String(status_line), 15, COLOR_SUB))
	for phrase in _relation_phrases():
		_content.add_child(_body_label(String(phrase), 15, COLOR_SUB))
	for line in _combo.get("lines", []):
		_content.add_child(_body_label(String(line), 15, COLOR_SUB))
	if _weather == "rainy":
		var d6_text := _append_d6()
		if not d6_text.is_empty():
			_content.add_child(_body_label(d6_text.strip_edges(), 16, COLOR_TITLE))
	_set_footer("就这样", _finish_weekend)


## 手账表格的每一行：「周六上午　湖边散步深谈　王哥」；留白写"留白"。
func _slot_table_lines() -> Array:
	var rows: Array = []
	for i in _slots.size():
		if slot_is_blank(i):
			rows.append("%s　留白" % SEGMENT_LABELS[i])
			continue
		var slot: Dictionary = _slots[i]
		var act := slot.get("activity") as Dictionary
		var aid := String(act.get("activity_id", ""))
		var labels: Array = slot.get("labels", [])
		var who := "一个人"
		if not labels.is_empty():
			who = " / ".join(labels)
		rows.append("%s　%s　%s" % [SEGMENT_LABELS[i], String(ACTIVITY_NAMES.get(aid, aid)), who])
	return rows


func _relation_phrases() -> Array:
	var phrases: Array = []
	for entry in _slot_results:
		if not (entry is Dictionary):
			continue
		for phrase in (entry as Dictionary).get("relations", []):
			phrases.append(String(phrase))
	return phrases


## 手账页：本次同行者**现在**各处在什么档位（跨档那句另由 _relation_phrases() 出）。
## 一行一位、跨格去重；查不到档位的不写（陈工不在关系系统里）。
func _relation_status_lines() -> Array:
	var lines: Array = []
	if _life == null:
		return lines
	var seen := {}
	for i in _slots.size():
		if slot_is_blank(i):
			continue
		for raw in (_slots[i] as Dictionary).get("targets", []):
			var npc_id := String(raw)
			if seen.has(npc_id):
				continue
			seen[npc_id] = true
			var line := _relation_line(
				String(_life.NPC_NAMES.get(npc_id, npc_id)),
				int(_life.affinity_level(_life.affinity_of(npc_id))),
				String(_life.relation_stage_name(npc_id)),
			)
			if not line.is_empty():
				lines.append(line)
	return lines


## 手账页的「在场一幕」块：一句当时的画面 + 「记住了你：XXX」。**恒无数字**（红线）。
func _encounter_lines() -> Array:
	var lines: Array = []
	if _encounter_result.is_empty():
		return lines
	var feedback := String(_encounter_result.get("feedback", ""))
	if not feedback.is_empty():
		lines.append(feedback)
	var remembered = _encounter_result.get("lines", [])
	if remembered is Array:
		for phrase in (remembered as Array):
			lines.append(String(phrase))
	return lines


## 落手账（§7.2）：完整记录进 weekend_ledger（小镇侧写 jsonl）；
## 玩家手写那句另走 memo_requested，供记忆墙当便签用。
func _finish_weekend() -> void:
	var note := ""
	if _note_edit != null:
		note = _note_edit.text.strip_edges()
	# B 件：把这一幕的选择写进手账存档，供 §6 回声（下次进入该区域 NPC 回召）消费。
	var encounter_record := {}
	if _encounter_slot >= 0:
		encounter_record = {
			"slotId": String((_slots[_encounter_slot] as Dictionary).get("slotId", "")),
			"activityId": String(_activity.get("activity_id", "")),
			"optionId": String(_encounter_option.get("option_id", "")),
			"tags": _encounter_result.get("tags", []),
		}
	var record := {
		"month": _month,
		"weather": _weather,
		"slots": _slot_records(),
		"combo": String(_combo.get("key", "")),
		# 手账册（§6.2）复显用的投入结构人话；老记录没这字段，册子侧自行兜底。
		"structureLine": _life.weekend_structure_line(_slots) if _life != null else "",
		"sameZoneFocus": bool(_combo.get("same_zone", false)),
		"playerNote": note,
		"relations": _relation_phrases(),
		"encounter": encounter_record,
		"echoConsumed": false,
	}
	if not note.is_empty():
		# `npc` 存**显示名**（记忆墙拿它反查关系档贴色点）。刻意不用 npc_id：
		# NPC 在项目里有两套 id 空间（npcs.json 是 wange，MonthlyLife 是 wang_ge），
		# 名字是唯一两边都成立的 join key。两格同行者不止一人时给空串 → 不贴点。
		memo_requested.emit("weekend_%d" % _month, {"text": note, "tone": "parchment", "npc": _sole_target_name()})
	weekend_ledger.emit(record)
	close()


func _slot_records() -> Array:
	var records: Array = []
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		records.append({
			"slotId": String(slot.get("slotId", "")),
			"blank": slot_is_blank(i),
			"zone": String(slot.get("zone", "")),
			"activityId": String(slot.get("activityId", "")),
			"targets": slot.get("targets", []),
		})
	return records


func _separator() -> Label:
	return _content_label("─".repeat(20), 13, COLOR_SUB)


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
	# ⚠ 红线（§5）：这里以前会把 "%s 好感 +%d" 直接打上手账页——雨天（20%）必漏一次数值。
	# 改成人话，只交代同路的是谁，数字一个都不给。
	return "—— 彩蛋 · 那把伞 ——\n%s\n和你撑同一把伞的是%s。" % [
		String(d6.get("text", "")), String(d6.get("npcName", "")),
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
## disabled = true 用于「已排进另一格」的活动：置灰、不可点（§13.2 同一活动只出现一次）。
func _make_card(icon_char: String, title_text: String, sub_text: String, on_pressed: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(328, 78)
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


## 窄按钮（两格总表右侧的「清空」）。
func _make_small_button(text: String, on_pressed: Callable) -> Button:
	var small := Button.new()
	small.text = text
	small.custom_minimum_size = Vector2(96, 78)
	small.add_theme_font_override("font", FONT)
	small.add_theme_font_size_override("font_size", 16)
	small.add_theme_color_override("font_color", COLOR_SUB)
	small.add_theme_stylebox_override("normal", _card_style(Color("452a1c"), COLOR_BORDER))
	small.add_theme_stylebox_override("hover", _card_style(COLOR_CARD, COLOR_TITLE))
	small.pressed.connect(on_pressed)
	return small


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
