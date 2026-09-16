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
		"id": "M1-E01", "month": 1, "day": 1, "hour": 9,
		"title": "新员工手册", "locationId": "B", "location": "B 科技丘 · 你的工位", "durationMinutes": 45,
		"story": "早上九点，B 区。你按工位号找到自己的位置。桌上只有一台还没开机的显示器，和一本被翻过很多次的册子。",
		"actTitle": "第一幕 · 进入行业",
		"situation": "weak",
		"cast": ["xiaoxiong", "wange"],
		"speakers": {
			"xiaoxiong": {"name": "小熊", "role": "比你早半年", "loadout": "street_creator", "pos": "left"},
			"wange": {"name": "王哥", "role": "带你的人", "loadout": "neutral_hoodie", "pos": "right"},
		},
		"beats": [
			{"type": "narration", "text": "早上九点，B 区。\n\n你按工位号找到自己的位置。桌上只有一台还没开机的显示器，和一本被翻过很多次的册子。"},
			{"type": "say", "speaker": "xiaoxiong", "text": "你是今天来报到的吧？我叫小熊，比你早来半年。\n\n先别急着装环境。坐了十二个小时车的人我见多了——第一天硬上，第三天就蔫。"},
			{"type": "say", "speaker": "wange", "text": "新来的？"},
			{"type": "narration", "text": "他没停，往前走了两步，又回头。"},
			{"type": "say", "speaker": "wange", "text": "手册第三章别看太早。看了容易想太多。"},
			{"type": "say", "speaker": "xiaoxiong", "text": "别理他，他就是那么个人。\n\n册子在桌上，一共三章。你自己翻——比我嘴上说管用。"},
			{"type": "interact", "target": "handbook", "label": "桌上的《新员工手册》", "hint": "翻开看看（技术规范 / 协作流程 / 晋升通道）"},
			{"type": "choice", "prompt": "三章里，你先翻开哪一章？"},
		],
		"prompt": "三章里，你先翻开哪一章？", "hint": "三章都读得到，先翻哪章只说明你第一天最在意什么",
		"choices": [
			{"id": "option_a", "text": "技术规范。代码怎么写、什么必须标注。"},
			{"id": "option_b", "text": "协作流程。谁拍板、卡住了该找谁。"},
			{"id": "option_c", "text": "晋升通道。在这儿，人是怎么被看见的。"},
		],
		"outcome": {
			"option_a": "你把第一章读了两遍，在「生成式工具参与的代码要标注」那一条旁边画了道线。\n\n小熊瞥了一眼，什么都没说。三个月后你才明白，那道线是给未来的自己划的。",
			"option_b": "你翻到「该找谁」那页，停了一会儿，抬头看了看王哥走掉的方向。\n\n那页上写着：问他「为什么」，他不怕你问，怕你不问。",
			"option_c": "你直接翻到了最后一章。\n\n小熊看见你翻的页码，笑了一下：「挺实际。」他没评价，只是把自己的水杯往你这边推了推。",
		},
		"memoryNote": {
			"option_a": {"text": "第一天先弄懂了规矩", "tone": "gold"},
			"option_b": {"text": "第一天先弄清了人", "tone": "gold"},
			"option_c": {"text": "第一天就问「人怎么被看见」", "tone": "gray"},
		}
	},
	{
		"id": "M1-E02", "month": 3, "day": 1, "hour": 9,
		"title": "技术选型", "locationId": "A", "location": "A 总部 · 评审室", "durationMinutes": 60,
		"story": "Agent 编排层即将进入正式开发。评审会上，自研方案可控但周期较长，开源方案上线快却需要适配现有系统。\n\n负责人请你给出建议，这次决定会影响后续几个月的技术路线和交付节奏。",
		"prompt": "面对两条技术路线，你会怎样推进决策？", "hint": "权衡交付速度、长期控制力和验证成本",
		"choices": [
			{"id": "option_a", "text": "采用成熟开源方案，先完成核心流程，再逐步替换不满足需求的部分。"},
			{"id": "option_b", "text": "坚持完全自研，宁可延长工期，也要从一开始掌握全部技术细节。"},
			{"id": "option_c", "text": "用一周分别做最小原型，按稳定性、成本和扩展性评分后再决定。"},
		],
		"actTitle": "第一幕 · 进入行业",
		"situation": "medium",
		"cast": [
			{"name": "王哥", "role": "带你的人", "loadout": "elder_man", "pos": "left"},
			{"name": "陈工", "role": "直属 Leader", "loadout": "suit_man", "pos": "right"},
		],
		"outcome": {
			"option_a": "方案当场就过了。三个月后核心流程上线，而那些「以后再替换」的部分一直留在那里——留到第十四个月。",
			"option_b": "你争取到了工期，也拿到了对每个细节的掌控权。第十六个月，这套底座成了团队里唯一没人敢动、也唯一没人全懂的东西。",
			"option_c": "两份原型摆上会桌，争论变成了看数据。多花的那一周，后面省回来的不止一个月。",
		},
		"memoryNote": {
			"option_a": {"text": "先上线的代价，半年后要还", "tone": "gray"},
			"option_b": {"text": "选了难走的那条路", "tone": "gold"},
			"option_c": {"text": "用数据代替了拍脑袋", "tone": "gold"},
		}
	},
	{
		"id": "M1-E03", "month": 5, "day": 1, "hour": 9,
		"title": "评测集要不要建", "locationId": "B", "location": "B 科技丘 · 工位", "durationMinutes": 60,
		"story": "首个版本距离交付只剩三周，团队却发现 Agent 的表现主要靠人工体验判断。\n\n建立完整评测集至少要投入两周，产品进度和质量保障发生了正面冲突。",
		"prompt": "工期紧张时，你会怎样处理评测问题？", "hint": "决定团队如何平衡短期交付与可验证的质量",
		"choices": [
			{"id": "option_a", "text": "立即投入两周建立完整评测集，必要时主动协商延期。"},
			{"id": "option_b", "text": "先建立覆盖关键场景的最小评测集，交付后再持续补全。"},
			{"id": "option_c", "text": "先按原计划上线，通过用户反馈收集问题，暂时不做评测集。"},
		],
		"actTitle": "第一幕 · 进入行业",
		"situation": "medium",
		"cast": [{"name": "王哥", "role": "带你的人", "loadout": "elder_man", "pos": "right"}],
		"outcome": {
			"option_a": "评测集上线第一周就抓出三个线上问题。交付晚了两周，但从那以后，没人再问「这个改动会不会弄坏什么」。",
			"option_b": "最小集覆盖了最关键的二十个场景。剩下的那一半，交付之后总有更紧急的事排在前面。",
			"option_c": "版本按时上线了。第十四个月那场演示之前，没有人能说清它到底变好了没有——包括你自己。",
		},
		"memoryNote": {
			"option_a": {"text": "为看不见的东西买了单", "tone": "gold"},
			"option_b": {"text": "说好交付后补的那一半", "tone": "gray"},
			"option_c": {"text": "没人知道它到底好不好", "tone": "gray"},
		}
	},
	{
		"id": "M1-E04", "month": 7, "day": 1, "hour": 23,
		"title": "AI 代码标注", "locationId": "B", "location": "B 科技丘 · 深夜工位", "durationMinutes": 50,
		"story": "深夜，你准备提交一个由 AI 辅助完成的关键 PR。代码已经通过本地检查，但团队还没有形成统一的 AI 使用标注规范。\n\n现在需要决定是否主动说明 AI 参与，以及如何对这部分代码负责。",
		"prompt": "提交这次 PR 时，你会怎样处理 AI 参与信息？", "hint": "你的选择会影响代码责任、团队信任和协作规范",
		"choices": [
			{"id": "option_a", "text": "在 PR 中明确标注 AI 辅助范围，并说明自己完成的验证和风险检查。"},
			{"id": "option_b", "text": "只提交代码和测试结果，除非评审者询问，否则不主动提及 AI。"},
			{"id": "option_c", "text": "先暂缓提交，和负责人确认团队的 AI 代码规范后再处理。"},
		],
		"actTitle": "第一幕 · 进入行业",
		"situation": "weak",
		"cast": [],
		"outcome": {
			"option_a": "你在 PR 描述里写清了哪部分是 AI 生成的、你验证了什么、哪一段你还没把握。评审开了二十分钟，其中十五分钟在讨论那个「没把握」。",
			"option_b": "PR 十分钟就过了，没人问起。你合上电脑，心里有个地方轻轻响了一声——像是什么东西被锁进了抽屉。",
			"option_c": "你压到第二天，先去问了规范。团队因此有了第一份 AI 代码标注约定，落款是你的名字。",
		},
		"memoryNote": {
			"option_a": {"text": "写清楚了自己做了什么", "tone": "gold"},
			"option_b": {"text": "那次我没写", "tone": "gray"},
			"option_c": {"text": "替团队定了一条规矩", "tone": "gold"},
		}
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

## 以「一个月」为单位推进：把时间拨到下一个未完成主线事件的时点。
## 主线事件都挂在每月 1 日（月初即剧情），所以这一跳正好落在下一个月的开头；
## 事件结算后本月剩余的时间留给自由活动（小镇里自己安排）。
## 全部主线完成后退化为直接推进一个月，游戏继续自由漫游。
func advance_month() -> void:
	if not running:
		return
	var next := next_main_event()
	if next.is_empty():
		advance_days(DAYS_PER_MONTH)
		return
	var target := _event_minute(next)
	if target > world_minute:
		advance_minutes(float(target - world_minute))
		return
	# 目标事件时点已过（理论上被睡觉守卫挡住，不会走到这）：直接停在那件事上，绝不吞剧情。
	world_minute = target
	running = false
	_emit_time_changed()
	main_event_reached.emit(next)

## 睡觉：把时间拨到第二天早上，跨过午夜。
## 有主线事件守卫：如果这一觉会跨过某个未完成主线事件的时点（比如月初 23:00 的事件），
## 时间停在事件上而不是把它睡过去 —— 事件只在月初 1 日出现后，被睡掉一次就永远触不到了。
## 事件都在 9:00 / 23:00；停在 23:00 的事件上结算完，再睡一次就是次日早上。
func sleep_until_next_morning(hour: int) -> void:
	var day_index := world_minute / MINUTES_PER_DAY
	var target_minute := (day_index + 1) * MINUTES_PER_DAY + clampi(hour, 0, 23) * 60
	var blocker := _first_blocking_event_between(world_minute, target_minute)
	if not blocker.is_empty():
		world_minute = _event_minute(blocker)
		running = false
		_minute_remainder = 0.0
		_emit_time_changed()
		main_event_reached.emit(blocker)
		return
	world_minute = target_minute
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
