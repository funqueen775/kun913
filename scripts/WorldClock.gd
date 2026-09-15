extends Node

signal time_changed(snapshot: Dictionary)
signal phase_changed(phase_id: String)
signal main_event_reached(event: Dictionary)

const MINUTES_PER_DAY := 24 * 60
const DAYS_PER_MONTH := 30
const MINUTES_PER_REAL_SECOND := 6.0
const PHASES := [
	{"id": "dawn", "name": "清晨", "start": 6 * 60},
	{"id": "day", "name": "白天", "start": 8 * 60},
	{"id": "dusk", "name": "傍晚", "start": 17 * 60},
	{"id": "night", "name": "夜晚", "start": 19 * 60},
]
const MAIN_EVENTS := [
	{
		"id": "M1-E01", "month": 1, "day": 15, "hour": 9,
		"title": "新员工手册", "locationId": "B", "location": "B 科技丘 · 你的工位", "durationMinutes": 45,
		"story": "你完成环境安装后，陈工把一份《新员工手册》放到桌上。\n\n他提醒你：今天先不要急着展示能力。先弄清团队如何协作、谁负责决策，以及遇到不确定问题时该怎样同步。",
		"prompt": "你会如何开始第一天的工作？", "hint": "阅读手册后，选择你第一天的行动方式",
		"choices": [
			{"id": "option_a", "text": "先整理手册中的术语和流程，独自熟悉后再开始工作。"},
			{"id": "option_b", "text": "向陈工确认协作边界、优先事项和遇到问题时的沟通方式。"},
			{"id": "option_c", "text": "直接挑一个技术任务动手，用成果证明自己可以快速上手。"},
		]
	},
	{
		"id": "M1-E02", "month": 3, "day": 15, "hour": 9,
		"title": "技术选型", "locationId": "A", "location": "A 总部 · 评审室", "durationMinutes": 60,
		"story": "Agent 编排层即将进入正式开发。评审会上，自研方案可控但周期较长，开源方案上线快却需要适配现有系统。\n\n负责人请你给出建议，这次决定会影响后续几个月的技术路线和交付节奏。",
		"prompt": "面对两条技术路线，你会怎样推进决策？", "hint": "权衡交付速度、长期控制力和验证成本",
		"choices": [
			{"id": "option_a", "text": "采用成熟开源方案，先完成核心流程，再逐步替换不满足需求的部分。"},
			{"id": "option_b", "text": "坚持完全自研，宁可延长工期，也要从一开始掌握全部技术细节。"},
			{"id": "option_c", "text": "用一周分别做最小原型，按稳定性、成本和扩展性评分后再决定。"},
		]
	},
	{
		"id": "M1-E03", "month": 5, "day": 15, "hour": 9,
		"title": "评测集要不要建", "locationId": "B", "location": "B 科技丘 · 工位", "durationMinutes": 60,
		"story": "首个版本距离交付只剩三周，团队却发现 Agent 的表现主要靠人工体验判断。\n\n建立完整评测集至少要投入两周，产品进度和质量保障发生了正面冲突。",
		"prompt": "工期紧张时，你会怎样处理评测问题？", "hint": "决定团队如何平衡短期交付与可验证的质量",
		"choices": [
			{"id": "option_a", "text": "立即投入两周建立完整评测集，必要时主动协商延期。"},
			{"id": "option_b", "text": "先建立覆盖关键场景的最小评测集，交付后再持续补全。"},
			{"id": "option_c", "text": "先按原计划上线，通过用户反馈收集问题，暂时不做评测集。"},
		]
	},
	{
		"id": "M1-E04", "month": 7, "day": 15, "hour": 23,
		"title": "AI 代码标注", "locationId": "B", "location": "B 科技丘 · 深夜工位", "durationMinutes": 50,
		"story": "深夜，你准备提交一个由 AI 辅助完成的关键 PR。代码已经通过本地检查，但团队还没有形成统一的 AI 使用标注规范。\n\n现在需要决定是否主动说明 AI 参与，以及如何对这部分代码负责。",
		"prompt": "提交这次 PR 时，你会怎样处理 AI 参与信息？", "hint": "你的选择会影响代码责任、团队信任和协作规范",
		"choices": [
			{"id": "option_a", "text": "在 PR 中明确标注 AI 辅助范围，并说明自己完成的验证和风险检查。"},
			{"id": "option_b", "text": "只提交代码和测试结果，除非评审者询问，否则不主动提及 AI。"},
			{"id": "option_c", "text": "先暂缓提交，和负责人确认团队的 AI 代码规范后再处理。"},
		]
	},
]

var world_minute := 9 * 60
var running := true
var _last_phase := ""
var _minute_remainder := 0.0
var _completed_main_event_ids: Array[String] = []

func _ready() -> void:
	_emit_time_changed()

func _process(delta: float) -> void:
	if not running:
		return
	advance_minutes(delta * MINUTES_PER_REAL_SECOND)

func advance_minutes(minutes: float) -> void:
	_minute_remainder += maxf(0.0, minutes)
	var whole_minutes := floori(_minute_remainder)
	if whole_minutes <= 0:
		return
	_minute_remainder -= whole_minutes
	var target_minute := world_minute + whole_minutes
	var blocker := _first_blocking_event_between(world_minute, target_minute)
	if not blocker.is_empty():
		world_minute = _event_minute(blocker)
		running = false
		_emit_time_changed()
		main_event_reached.emit(blocker)
		return
	world_minute = target_minute
	_emit_time_changed()

func advance_days(days: int = 5) -> void:
	if not running:
		return
	advance_minutes(float(maxi(1, days) * MINUTES_PER_DAY))

## 睡觉：直接把时间拨到第二天早上，跨过午夜。
## 不走 advance_minutes 是有意的 —— 那条路会一路检查主线事件，
## 睡觉属于"跳过夜晚"，不该在半夜把玩家拽起来做剧情。
## 事件都在 9:00 / 23:00，从 23:00 睡到次日 7:00 不会漏掉任何一个。
func sleep_until_next_morning(hour: int) -> void:
	var day_index := world_minute / MINUTES_PER_DAY
	world_minute = (day_index + 1) * MINUTES_PER_DAY + clampi(hour, 0, 23) * 60
	_minute_remainder = 0.0
	running = true
	_emit_time_changed()

func next_main_event() -> Dictionary:
	for event in MAIN_EVENTS:
		if not _completed_main_event_ids.has(String(event["id"])):
			return event.duplicate(true)
	return {}

func complete_main_event(event_id: String) -> bool:
	if not MAIN_EVENTS.any(func(event): return String(event["id"]) == event_id):
		return false
	if not _completed_main_event_ids.has(event_id):
		_completed_main_event_ids.append(event_id)
	running = true
	_emit_time_changed()
	return true

func _first_blocking_event_between(from_minute: int, to_minute: int) -> Dictionary:
	for event in MAIN_EVENTS:
		if _completed_main_event_ids.has(String(event["id"])):
			continue
		var event_minute := _event_minute(event)
		if event_minute >= from_minute and event_minute <= to_minute:
			return event
	return {}

func _event_minute(event: Dictionary) -> int:
	return ((int(event["month"]) - 1) * DAYS_PER_MONTH + (int(event["day"]) - 1)) * MINUTES_PER_DAY + int(event.get("hour", 9)) * 60

func set_running(value: bool) -> void:
	running = value

func snapshot() -> Dictionary:
	var total_days := world_minute / MINUTES_PER_DAY
	var minute_of_day := posmod(world_minute, MINUTES_PER_DAY)
	var month := total_days / DAYS_PER_MONTH + 1
	var day := posmod(total_days, DAYS_PER_MONTH) + 1
	var hour := minute_of_day / 60
	var minute := posmod(minute_of_day, 60)
	var phase := phase_for_minute(minute_of_day)
	return {
		"worldMinute": world_minute,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"clock": "%02d:%02d" % [hour, minute],
		"phaseId": phase["id"],
		"phaseName": phase["name"],
	}

func phase_for_minute(minute_of_day: int) -> Dictionary:
	if minute_of_day < 6 * 60:
		return PHASES[3]
	if minute_of_day < 8 * 60:
		return PHASES[0]
	if minute_of_day < 17 * 60:
		return PHASES[1]
	if minute_of_day < 19 * 60:
		return PHASES[2]
	return PHASES[3]

func _emit_time_changed() -> void:
	var state := snapshot()
	var phase_id := String(state["phaseId"])
	if phase_id != _last_phase:
		_last_phase = phase_id
		phase_changed.emit(phase_id)
	time_changed.emit(state)
