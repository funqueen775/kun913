extends Node
## 月度生活系统：每月 3 点精力、公开数值（专业能力/生命/产出/金钱）、
## 月底经济结算、NPC 好感度（隐藏数值）。
## 口径来源：
## - 《游戏机制与情绪价值设计说明 V1》§4（精力行动 / 生命规则 / 月底经济结算）
## - data/story/free_time_system.json v1.3（活动收益 / 好感度 / 收益递减）
## 刻意不做 autoload：由 WorkplaceTown 实例化后把引用下发给面板，
## 探针（build/probe_free_time.gd）也能直接 new 出来测逻辑。

signal state_changed(state: Dictionary)

const ENERGY_PER_MONTH := 3
const HEALTH_MAX := 10
const START_MONEY := 15000
const BASE_SALARY := 10000
const FIXED_EXPENSE := 6500
const BONUS_PER_OUTPUT := 500
const BONUS_OUTPUT_CAP := 3
## 好感度 0-100，对玩家隐藏（机制文档红线）；视觉表达走记忆墙便签颜色渐进。
const AFFINITY_MAX := 100
const NPC_NAMES := {
	"wang_ge": "王哥",
	"xiao_lin": "小林",
	"xiao_zhao": "小赵",
	"lao_zhou": "老周",
	"xiong_zong": "熊总",
}
## 「人际经营」的默认对象池。选人环节 MVP 不做（用户拍板）→ 随机指派。
const SOCIAL_POOL: Array[String] = ["wang_ge", "xiao_lin", "xiao_zhao", "lao_zhou"]

## 当前精力所属月份（第 1 月开局）。
var month := 1
var energy := ENERGY_PER_MONTH
var skill := 1
var health := 7
var output := 0
var money := START_MONEY
var affinity := {}
## 最近一次月底结算的文案（给精力面板展示）。
var last_settlement := ""
## 知心时刻：每 NPC 一次性（free_time_system v1.3 rules.intimate_moment）。
var intimate_used := {}
## 收益递减：npc_id -> 连续被约的次数，约别人就把其他人的计数清零。
var _consecutive_counts := {}


func _ready() -> void:
	randomize()
	for id in NPC_NAMES.keys():
		affinity[id] = 0


func snapshot() -> Dictionary:
	return {
		"month": month,
		"energy": energy,
		"energyMax": ENERGY_PER_MONTH,
		"skill": skill,
		"health": health,
		"healthMax": HEALTH_MAX,
		"output": output,
		"money": money,
	}


## 世界时钟进入新月份时调用：把跳过的每个月都做一次月底结算，再发新月精力。
## 生命归 0 的那个月结算后，下个月强制休息：精力只有 1 点（工资照发）。
func ensure_month(new_month: int) -> void:
	var changed := false
	while month < new_month:
		var forced_rest := _settle_month()
		month += 1
		output = 0
		energy = 1 if forced_rest else ENERGY_PER_MONTH
		changed = true
	if changed:
		state_changed.emit(snapshot())


## 月底经济结算（机制文档 §4.3）：工资 → 产出折奖金 → 扣固定支出。
## 家具/欠款系统不在 MVP 范围，只保留现金流主干。
func _settle_month() -> bool:
	var bonus := mini(output, BONUS_OUTPUT_CAP) * BONUS_PER_OUTPUT
	money += BASE_SALARY + bonus - FIXED_EXPENSE
	last_settlement = "第 %d 月结算：工资 +%d · 奖金 +%d · 生活支出 -%d" % [
		month, BASE_SALARY, bonus, FIXED_EXPENSE,
	]
	var forced_rest := false
	if health <= 0:
		health = 4
		forced_rest = true
		last_settlement += " · 身体垮了，下月强制休息（精力只有 1 点，工资照发）"
	return forced_rest


## 花 1 点精力做一件月度养成行动（机制文档 §4.1：1 点精力只做一件事）。
## 返回 {ok: bool, text: String}，text 直接给面板当即时反馈。
func spend_energy(action_id: String) -> Dictionary:
	if energy <= 0:
		return {"ok": false, "text": "这个月的精力已经用完了，等下个月吧。"}
	var text := ""
	match action_id:
		"grow":
			energy -= 1
			skill += 1
			text = "你啃完了半本论文，顺手把上周卡住的疑问想通了。专业能力 +1。"
		"produce":
			energy -= 1
			output += 1
			text = "你把手头的活往前推了一大段。本月产出 +1，月底折算成奖金。"
		"rest":
			energy -= 1
			health = mini(HEALTH_MAX, health + 1)
			text = "你睡了一个不设闹钟的午觉。生命 +1。"
		"social":
			energy -= 1
			var npc_id: String = SOCIAL_POOL.pick_random()
			_add_affinity(npc_id, 2)
			text = "你约 %s 喝了杯咖啡，聊了聊最近的事。关系悄悄近了一点。" % NPC_NAMES.get(npc_id, npc_id)
		_:
			return {"ok": false, "text": "没有这个行动。"}
	state_changed.emit(snapshot())
	return {"ok": true, "text": text, "actionId": action_id}


## 好感度加减（隐藏数值）。同一人连续被约第 3 次起收益减半（收益递减，§11.4）。
func _add_affinity(npc_id: String, delta: int) -> int:
	if not affinity.has(npc_id):
		affinity[npc_id] = 0
	var count := int(_consecutive_counts.get(npc_id, 0)) + 1
	_consecutive_counts[npc_id] = count
	for key in _consecutive_counts.keys():
		if key != npc_id:
			_consecutive_counts[key] = 0
	if count >= 3 and delta > 0:
		delta = int(ceil(delta * 0.5))
	affinity[npc_id] = clampi(int(affinity[npc_id]) + delta, 0, AFFINITY_MAX)
	return delta


func affinity_of(npc_id: String) -> int:
	return int(affinity.get(npc_id, 0))


## 自由周末活动结算：吃 free_time_system.json 里单个活动配置。
## targets = 参与 NPC id 列表（选人环节 MVP 不做，由面板随机指派）。
## 返回 {lines: Array[String]} 给面板逐行展示。
func apply_weekend_activity(activity: Dictionary, targets: Array) -> Dictionary:
	var lines: Array[String] = []
	var gain: Dictionary = activity.get("gain", {})
	var cost: Dictionary = activity.get("cost", {})
	var skill_delta := int(gain.get("S", 0)) - int(cost.get("S", 0))
	var output_delta := int(gain.get("O", 0)) - int(cost.get("O", 0))
	var health_delta := int(gain.get("H", 0)) - int(cost.get("H", 0))
	var network_delta := int(gain.get("N", 0)) - int(cost.get("N", 0))
	if skill_delta != 0:
		skill = maxi(0, skill + skill_delta)
		lines.append("专业能力 %+d" % skill_delta)
	if output_delta != 0:
		output = maxi(0, output + output_delta)
		lines.append("本月产出 %+d" % output_delta)
	if health_delta != 0:
		health = clampi(health + health_delta, 0, HEALTH_MAX)
		lines.append("生命 %+d" % health_delta)
	# N（人脉/影响力）MVP 没有独立公开数值，折算进人际面：
	# 有同行对象就记在同行者身上，没对象随机送一个 NPC。
	if network_delta != 0:
		lines.append("人脉 %+d" % network_delta)
		if targets.is_empty():
			targets = [SOCIAL_POOL.pick_random()]
		for target in targets:
			_add_affinity(String(target), network_delta)
	var base_gain := 0
	var aff_gain = activity.get("affinity_gain", null)
	# ⚠ JSON 数字解析出来是 float，「is int」永远不成立，必须先挡 null 再 int()
	if aff_gain is Dictionary:
		base_gain = int(aff_gain.get("each", 0))
	elif aff_gain != null:
		base_gain = int(aff_gain)
	var repeated_hint := false
	for target in targets:
		var npc_id := String(target)
		var actual := _add_affinity(npc_id, base_gain)
		lines.append("%s 好感 %+d" % [NPC_NAMES.get(npc_id, npc_id), actual])
		if int(_consecutive_counts.get(npc_id, 0)) >= 3:
			repeated_hint = true
	if repeated_hint:
		lines.append("他有点意外你又来了。")
	# ⚠ JSON 里 memory_tag 可能是显式 null，String(null) 会抛「Nonexistent constructor」
	var memory_tag_value = activity.get("memory_tag")
	var memory_tag := "" if memory_tag_value == null else String(memory_tag_value)
	if not memory_tag.is_empty():
		lines.append("记住了你：%s" % memory_tag)
	state_changed.emit(snapshot())
	return {"lines": lines}


## 决策点选项结算（G1/G2/D2/G4）。target_npc 用于 stuck_npc / boss 占位符。
func apply_decision_option(activity: Dictionary, option: Dictionary, target_npc: String) -> Dictionary:
	var lines: Array[String] = []
	var gain: Dictionary = option.get("gain", {})
	var skill_delta := int(gain.get("S", 0))
	var output_delta := int(gain.get("O", 0))
	var health_delta := int(gain.get("H", 0))
	if skill_delta != 0:
		skill = maxi(0, skill + skill_delta)
		lines.append("专业能力 %+d" % skill_delta)
	if output_delta != 0:
		output = maxi(0, output + output_delta)
		lines.append("本月产出 %+d" % output_delta)
	if health_delta != 0:
		health = clampi(health + health_delta, 0, HEALTH_MAX)
		lines.append("生命 %+d" % health_delta)
	var aff_delta = option.get("affinity_delta")
	if aff_delta is Dictionary:
		if aff_delta.has("each"):
			for npc_id in SOCIAL_POOL:
				var actual := _add_affinity(npc_id, int(aff_delta["each"]))
				lines.append("%s 好感 %+d" % [NPC_NAMES.get(npc_id, npc_id), actual])
		else:
			var role := String(aff_delta.get("target", ""))
			var npc_id := target_npc if role == "stuck_npc" or role == "boss" else role
			if not npc_id.is_empty():
				var actual2 := _add_affinity(npc_id, int(aff_delta.get("value", 0)))
				lines.append("%s 好感 %+d" % [NPC_NAMES.get(npc_id, npc_id), actual2])
	elif aff_delta != null and not target_npc.is_empty():
		var actual3 := _add_affinity(target_npc, int(aff_delta))
		lines.append("%s 好感 %+d" % [NPC_NAMES.get(target_npc, target_npc), actual3])
	var memory_tags = option.get("memory_tags")
	if memory_tags is Array:
		for tag in memory_tags:
			lines.append("记住了你：%s" % String(tag))
	var feedback := String(option.get("instant_feedback", ""))
	state_changed.emit(snapshot())
	return {"lines": lines, "feedback": feedback}


## 知心时刻触发条件：好感 ≥ 40 且该 NPC 还没用过（free_time_system hooks.intimate_moment）。
func can_trigger_intimate(npc_id: String) -> bool:
	return affinity_of(npc_id) >= 40 and not intimate_used.has(npc_id)


func mark_intimate_used(npc_id: String) -> void:
	intimate_used[npc_id] = true


## 天气：晴 80% / 雨 20%（每个自由周末独立判定）。
func roll_weather() -> String:
	return "rainy" if randf() < 0.2 else "sunny"


## D6 雨天共伞彩蛋（自动剧情，无决策）：随机一名 NPC，好感 +6，配「那把伞」便签。
func apply_d6_umbrella() -> Dictionary:
	var npc_id: String = SOCIAL_POOL.pick_random()
	var actual := _add_affinity(npc_id, 6)
	return {
		"npcId": npc_id,
		"npcName": NPC_NAMES.get(npc_id, npc_id),
		"delta": actual,
		"text": "雨说下就下。一把伞，两个人，半边肩膀是湿的。谁也没提这个安排。",
	}
