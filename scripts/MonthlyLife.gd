extends Node
## 生活系统：精力（每月 3 点）、公开数值（专业能力/生命/产出/金钱）、
## 月底经济结算、NPC 好感度（隐藏数值）。
## 口径来源：
## - 《游戏机制与情绪价值设计说明 V1》§4（精力行动 / 生命规则 / 月底经济结算）
## - data/story/scoring_cards.json `_anchor_params.monthly_energy`（3 点 / 不可结转，测量有效性要求）
## - data/story/free_time_system.json v1.3（活动收益 / 好感度 / 收益递减）
## 2026-09-17 改回月度口径（24 件基准拍板 #2）：精力 = 每月 3 点、**不可结转**，
## 1 点 = 1 项养成行动；跨天**不再**回满，只在进入新月时发 3 点。
## 时间推进与精力脱钩：时段推进改由「睡觉跨天 + 主线事件结算」双驱动（WorkplaceTown）。
## 刻意不做 autoload：由 WorkplaceTown 实例化后把引用下发给面板，
## 探针（build/probe_free_time.gd）也能直接 new 出来测逻辑。

signal state_changed(state: Dictionary)

## 花掉本月最后 1 点精力时发射（2026-09-17 自 EnergyPanel 上移到这里 —— 唯一发源地）。
## EnergyPanel 行动卡与右上角精力圆钮两条消费路径都经过 spend_energy，
## WorkplaceTown 监听它弹顶部横幅提示（2026-09-17 晚拍板：只提示，不再跳 22:00）。
## 月初补满再花完会再发。
signal energy_exhausted()

## 主线门禁（2026-09-17 晚用户拍板：当月主线没过完，不许花精力升级）。
## WorkplaceTown 注入 WorldClock.main_event_due 的 Callable——刻意用注入而不是
## 直接读 autoload，探针（build/probe_*.gd）new 出来测时门禁为空 = 恒不锁。
var main_gate: Callable = Callable()

## NPC 主动消息规则核心（Batch 5）。走 preload 不用 class_name：
## 全局类缓存只在编辑器扫描时才刷新，探针直接 --script 跑会报「Identifier not declared」。
const NPC_MESSAGES := preload("res://scripts/NpcMessageSystem.gd")

## 精力按「月」结算：每月 3 点（scoring_cards._anchor_params.monthly_energy），
## **不可结转** —— 月底没用完的直接清零，新月重新发 3 点。
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

## 当前体力所属月份（第 1 月开局）。
var month := 1
## 当前体力属于哪一天（对齐 WorldClock.snapshot()["dayIndex"]）。-1 = 还没和世界时钟对过表。
var day_index := -1
var energy := ENERGY_PER_MONTH
## 强制休息标记：生命归零后的那个月，整月不发精力（见 sync / _settle_month）。
var forced_rest := false
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
## 小旗标（跨事件伏笔的落点）：S2「领悟」、D4 提前讲秘密。
## 只存标记不存数值，消费点写在各自的行动里（grow / can_trigger_intimate）。
var flags := {}
## 训练谷首通记录（Batch 4）：已首通的 level_id 数组。重复通关无奖励（机制文档 §7.1）。
var duel_first_clears: Array = []

## ---------- NPC 主动消息（Batch 5 · 机制文档 §2「有人记得我」） ----------
## 收到的消息（按到达顺序）。每条 {id, npc, npc_name, kind, text, month, read, unlocks_duel?}。
var messages: Array = []
## 由邀约消息解锁的训练谷关卡 id（V5.27 §11.9：关卡由共同经历引出，不凭空开放）。
var duel_unlocks: Array = []
## 累积的记忆标签 —— 记忆类消息的燃料（「旧承诺被重新提起」要有的可提）。
var memory_tags: Array = []
var _sent_messages := {}          # {msg_id: 发送月份}：once 去重
var _last_msg_month_by_npc := {}  # {npc_id: 上次发送月份}：冷却

## 有新的主动消息到达 —— HUD「信」钮的红点靠它刷新。
signal message_arrived()


func _ready() -> void:
	randomize()
	for id in NPC_NAMES.keys():
		affinity[id] = 0


func snapshot() -> Dictionary:
	return {
		"month": month,
		"dayIndex": day_index,
		"energy": energy,
		"energyMax": ENERGY_PER_MONTH,
		"skill": skill,
		"health": health,
		"healthMax": HEALTH_MAX,
		"output": output,
		"money": money,
	}


## 世界时钟每次变动都调这里对表（见 WorkplaceTown._on_world_time_changed）。
## · 跨天 → **不动精力**（月度口径：睡一觉不回精力，精力只在换月时发）。
## · 跨月 → 把跳过的每个月都补一次月底工资结算、产出清零、发新月精力。
## 生命归零之后的那个月转入「强制休息」：整月精力 = 0（工资照发、自由周末保留），
## 下个月结算时生命已回到 4，自然解除、恢复 3 点。
func sync(new_month: int, new_day_index: int) -> void:
	var changed := false
	while month < new_month:
		forced_rest = _settle_month()
		month += 1
		output = 0
		# 精力不可结转：新月一律重发（强制休息月发 0 点，等于整月禁养成行动）。
		energy = 0 if forced_rest else ENERGY_PER_MONTH
		# 新月第一件事：看有没有人想起你。forced_rest 在这里已是「新月」的状态。
		_refresh_messages()
		changed = true
	if day_index != new_day_index:
		day_index = new_day_index
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
		last_settlement += " · 身体垮了，下月强制休息（整月不发精力，工资照发）"
	return forced_rest


## 训练谷首通标记。返回 true = 这次是首次（调用方此时才发奖）。
func mark_duel_cleared(level_id: String) -> bool:
	if duel_first_clears.has(level_id):
		return false
	duel_first_clears.append(level_id)
	return true


## ---------- NPC 主动消息（机制文档 §2「有人记得我」） ----------

## 新月第一件事：问一次「这个月谁会想起你」。
## 规则与文案全在 NpcMessageSystem（纯函数），这里只喂局面、存结果、兑现邀约解锁。
func _refresh_messages() -> void:
	var levels := {}
	for npc_id in affinity.keys():
		levels[String(npc_id)] = affinity_level(int(affinity[npc_id]))
	var ctx := {
		"month": month,
		"health": health,
		"forced_rest": forced_rest,
		"levels": levels,
		"flags": flags,
		"memory_tags": memory_tags,
		"cleared_duels": duel_first_clears,
		"sent": _sent_messages,
		"last_month_by_npc": _last_msg_month_by_npc,
		"npc_names": NPC_NAMES,
	}
	var fresh: Array = NPC_MESSAGES.generate(ctx)
	for entry in fresh:
		var msg: Dictionary = entry
		var msg_id := String(msg.get("id", ""))
		if msg_id.is_empty():
			continue
		_sent_messages[msg_id] = month
		_last_msg_month_by_npc[String(msg.get("npc", ""))] = month
		messages.append(msg)
		# 训练谷邀约：收到才算开放（V5.27 §11.9 —— 关卡由共同经历引出）。
		var unlocks := String(msg.get("unlocks_duel", ""))
		if not unlocks.is_empty() and not duel_unlocks.has(unlocks):
			duel_unlocks.append(unlocks)
	if not fresh.is_empty():
		message_arrived.emit()


## 未读条数（HUD 红点用）。
func unread_message_count() -> int:
	var n := 0
	for msg in messages:
		if not bool((msg as Dictionary).get("read", false)):
			n += 1
	return n


## 打开消息面板时调用：全部标为已读（红点清零）。
func mark_messages_read() -> void:
	for i in messages.size():
		var msg: Dictionary = messages[i]
		msg["read"] = true
		messages[i] = msg


## 某条消息是否收到过（训练谷关卡解锁判定用）。
func has_received_message(msg_id: String) -> bool:
	return _sent_messages.has(msg_id)


## 训练谷关卡是否开放：收到邀约即开。
## 月份兜底（unlock_month）由界面侧判 —— 消息系统万一没触发，关卡不能永久锁死。
func is_duel_unlocked(level_id: String) -> bool:
	return duel_unlocks.has(level_id)


## 累积记忆标签（事件选项的 memory_tags）。记忆类消息靠它才有「旧事」可提。
func remember_tags(tags: Array) -> void:
	for t in tags:
		var s := String(t)
		if s.is_empty() or memory_tags.has(s):
			continue
		memory_tags.append(s)


## ---------- 熊友卡（Batch 5 · 机制文档 §6）----------
## Lv3「伙伴」（好感 ≥40）解锁：① 月度养成搭档协助 ② 训练谷可选角色。
## 红线：协助只放大**公开资源**（专业能力/产出/生命/精力），绝不碰好感与隐藏测评。

const BUDDY_CONFIG := "res://data/story/buddy_cards.json"
var _buddy_cards: Array = []
var _buddy_by_npc := {}
## 老周「免耗」的每月限次（配置 per_month_limit）。懒初始化：只按 month 比对。
var _free_assist_month := -1
var _free_assist_count := 0


func _ensure_buddies() -> void:
	if not _buddy_cards.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BUDDY_CONFIG))
	if not (parsed is Dictionary):
		return
	for card in (parsed as Dictionary).get("cards", []):
		if card is Dictionary:
			_buddy_cards.append(card)
			_buddy_by_npc[String(card.get("npc_id", ""))] = card


## 已解锁的搭档 npc_id 列表（好感 ≥40 = Lv3）。**只回 id，不回分数**。
func unlocked_buddies() -> Array[String]:
	var out: Array[String] = []
	_ensure_buddies()
	for card: Dictionary in _buddy_cards:
		if affinity_of(String(card.get("npc_id", ""))) >= 40:
			out.append(String(card.get("npc_id")))
	return out


## 某 NPC 的熊友卡配置；没有返回 {}（面板据此决定要不要亮出这张卡）。
func buddy_card_for(npc_id: String) -> Dictionary:
	_ensure_buddies()
	return _buddy_by_npc.get(npc_id, {})


func buddy_cards() -> Array:
	_ensure_buddies()
	return _buddy_cards


func is_buddy_unlocked(npc_id: String) -> bool:
	return unlocked_buddies().has(npc_id)


func is_duel_cleared(level_id: String) -> bool:
	return duel_first_clears.has(level_id)


## 场外入账（训练谷首通奖励等）：立即生效，不走月底结算。
func add_money(amount: int, _reason := "") -> void:
	if amount == 0:
		return
	money += amount
	state_changed.emit(snapshot())


## 花 1 点精力做一件事（锚点口径：1 点 = 对应方向 1 点）。
## 返回 {ok: bool, text: String}，text 直接给面板当即时反馈。
func spend_energy(action_id: String, buddy_id := "") -> Dictionary:
	if energy <= 0:
		return {"ok": false, "text": "这个月的精力用完了。下个月初会补满 3 点。"}
	# 主线门禁（兜底层）：UI 置灰之外再拦一道，任何消费路径都绕不过。
	if main_gate.is_valid() and bool(main_gate.call()):
		return {"ok": false, "text": "本月主线还没过完——先去完成主线事件，再来花精力。"}
	# 熊友卡协助（机制文档 §6.2）：先整段校验，失败绝不落任何数值。
	var assist := {}
	var buddy_name := ""
	if not String(buddy_id).is_empty():
		var card := buddy_card_for(String(buddy_id))
		if card.is_empty():
			return {"ok": false, "text": "你还拿不出这张熊友卡。"}
		buddy_name = String(card.get("name", ""))
		if not unlocked_buddies().has(String(buddy_id)):
			return {"ok": false, "text": "%s 还没到开口就答应的交情，关系再近一点再说。" % buddy_name}
		assist = card.get("assist", {})
		var scope := String(assist.get("action", "*"))
		if scope != "*" and scope != action_id:
			return {"ok": false, "text": "%s 在这件事上帮不上忙——他的强项是别处。" % buddy_name}
		var limit := int(assist.get("per_month_limit", 0))
		if limit > 0:
			if _free_assist_month != month:
				_free_assist_month = month
				_free_assist_count = 0
			if _free_assist_count >= limit:
				return {"ok": false, "text": "%s 这个月已经替你挡过一次了，剩下的自己来。" % buddy_name}
	var assist_effect := String(assist.get("effect", ""))
	var boost := int(assist.get("value", 0))
	var free_action := assist_effect == "free_action"
	var text := ""
	match action_id:
		"grow":
			skill += 1
			# S2 的「领悟」在这里兑现：下一个技术类行动额外 +1（hooks.epiphany_flag）
			if flags.get("epiphany_ready", false):
				flags.erase("epiphany_ready")
				skill += 1
				text = "你啃完了半本论文。湖边没想通的那件事，这会儿自己接上了。专业能力 +2。"
			else:
				text = "你啃完了半本论文，顺手把上周卡住的疑问想通了。专业能力 +1。"
			if assist_effect == "skill_bonus":
				skill += boost
		"produce":
			output += 1
			text = "你把手头的活往前推了一大段。本月产出 +1，月底折算成奖金。"
			if assist_effect == "output_bonus":
				output += boost
		"rest":
			health = mini(HEALTH_MAX, health + 1)
			text = "你睡了一个不设闹钟的午觉。生命 +1。"
			if assist_effect == "health_bonus":
				health = mini(HEALTH_MAX, health + boost)
		"social":
			var npc_id: String = SOCIAL_POOL.pick_random()
			_add_affinity(npc_id, 2)
			text = "你约 %s 喝了杯咖啡，聊了聊最近的事。关系悄悄近了一点。" % NPC_NAMES.get(npc_id, npc_id)
		_:
			return {"ok": false, "text": "没有这个行动。"}
	if free_action:
		# 老周：这件事没花你的精力（同月限次，前面已校验）
		_free_assist_count += 1
	else:
		energy -= 1
	if not assist.is_empty():
		var assist_text := String(assist.get("text", ""))
		if not assist_text.is_empty():
			text += "　" + assist_text
	state_changed.emit(snapshot())
	if energy <= 0:
		energy_exhausted.emit()
	return {"ok": true, "text": text, "actionId": action_id, "buddyId": String(buddy_id)}


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


## ---------- 收益口径 ----------

## 基础 gain + 满足 when 条件的 conditional_gain（free_time_system v1.4 新增字段）。
## 目前只有 S3 天台吹风在用：「绷太紧了才管用」—— 生命 ≤3 时给满 +2，否则只 +1。
## v1.6：conditional_gain 兼容**数组**（逐条判定，首条命中即用，单对象写法兼容保留）——
## S3 要两个方向的条件（≤3 给满、≥7 归零），单对象装不下。覆盖语义不变。
func gain_for(activity: Dictionary) -> Dictionary:
	var base = activity.get("gain", {})
	var result: Dictionary = (base as Dictionary).duplicate() if base is Dictionary else {}
	var conditional = activity.get("conditional_gain")
	if conditional is Array:
		for entry in (conditional as Array):
			if entry is Dictionary and _when_matches((entry as Dictionary).get("when", {})):
				var override_a = (entry as Dictionary).get("gain", {})
				if override_a is Dictionary:
					for key in (override_a as Dictionary).keys():
						result[key] = int((override_a as Dictionary)[key])
				break
		return result
	if not (conditional is Dictionary):
		return result
	if not _when_matches(conditional.get("when", {})):
		return result
	var override = conditional.get("gain", {})
	if override is Dictionary:
		for key in override.keys():
			result[key] = int(override[key])
	return result


## 条件判定。目前只认 H_lte / H_gte；不认识的条件一律当**不成立** ——
## 宁可少给收益，也不要因为字段名写错而错给。
func _when_matches(when) -> bool:
	if not (when is Dictionary) or when.is_empty():
		return true
	if when.has("H_lte") and health > int(when["H_lte"]):
		return false
	if when.has("H_gte") and health < int(when["H_gte"]):
		return false
	return true


## 自由周末活动结算：吃 free_time_system.json 里单个活动配置。
## targets = 参与 NPC id 列表（选人环节 MVP 不做，由面板随机指派）。
## 返回 {lines: Array[String]} 给面板逐行展示。
func apply_weekend_activity(activity: Dictionary, targets: Array) -> Dictionary:
	var lines: Array[String] = []
	# 「全员」型活动（G4 年会排练）没有同行者名单，但它是公司级场合：
	# 好感给整个同事池，而不是像 duo/group 那样只给见面的人。
	if String(activity.get("type", "")) == "team" and targets.is_empty():
		targets = SOCIAL_POOL.duplicate()
	var gain: Dictionary = gain_for(activity)
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
	# 活动钩子（`hooks` 以前是死字段，v1.4 起落地）：
	# · early_secret —— 炭火和深夜让人诚实，但捷径有价：好感少拿 1，换知心时刻提前解锁。
	# · epiphany_flag —— 走到第三圈突然通了：下一个技术行动（grow）额外 +1 专业能力。
	var hooks = activity.get("hooks", {})
	var hook_map: Dictionary = hooks if hooks is Dictionary else {}
	var early_secret := false
	if hook_map.has("early_secret"):
		var secret: Dictionary = hook_map["early_secret"]
		early_secret = randf() < float(secret.get("chance", 0.0))
		if early_secret:
			# 减益数值走配置（affinity_delta），不写死在代码里；缺省按 -1 兜底。
			base_gain = maxi(0, base_gain + int(secret.get("affinity_delta", -1)))
	var repeated_hint := false
	for target in targets:
		var npc_id := String(target)
		var actual := _add_affinity(npc_id, base_gain)
		lines.append("%s 好感 %+d" % [NPC_NAMES.get(npc_id, npc_id), actual])
		if early_secret:
			flags["intimate_early_" + npc_id] = true
		if int(_consecutive_counts.get(npc_id, 0)) >= 3:
			repeated_hint = true
	if early_secret:
		lines.append("他今晚话比平时多。有件事，他提前说了。")
	if hook_map.has("epiphany_flag"):
		var epiphany: Dictionary = hook_map["epiphany_flag"]
		if randf() < float(epiphany.get("chance", 0.0)):
			flags["epiphany_ready"] = true
			var epiphany_text := String(epiphany.get("text", ""))
			if not epiphany_text.is_empty():
				lines.append(epiphany_text)
	if repeated_hint:
		lines.append("他有点意外你又来了。")
	# ⚠ JSON 里 memory_tag 可能是显式 null，String(null) 会抛「Nonexistent constructor」
	var memory_tag_value = activity.get("memory_tag")
	var memory_tag := "" if memory_tag_value == null else String(memory_tag_value)
	if not memory_tag.is_empty():
		lines.append("记住了你：%s" % memory_tag)
	state_changed.emit(snapshot())
	return {"lines": lines}


## ---------- 自由周末：两格组合 + 批量结算（设计文档 §3.4 / §13.1） ----------
## 结构口径：一个自由周末 = 周六 2 格 + 周日自由。周日不进这里，它没有额度。

const FREE_TIME_CONFIG := "res://data/story/free_time_system.json"
## activity_id → 投入结构类别（work / social / solo_recover / solo_work）。
## 从 free_time_system.json 的 `input_structure.categories` **反查**，不新增任何数据字段。
var _input_category := {}


func _ensure_input_category() -> void:
	if not _input_category.is_empty():
		return
	var text := FileAccess.get_file_as_string(FREE_TIME_CONFIG)
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var structure = (parsed as Dictionary).get("input_structure", {})
	if not (structure is Dictionary):
		return
	var categories = (structure as Dictionary).get("categories", {})
	if not (categories is Dictionary):
		return
	for category in (categories as Dictionary).keys():
		var ids = categories[category]
		if not (ids is Array):
			continue
		for activity_id in ids:
			_input_category[String(activity_id)] = String(category)


## 活动的投入结构类别（work / social / solo_recover / solo_work）；取不到返回 ""。
func input_category_of(activity_id: String) -> String:
	_ensure_input_category()
	return String(_input_category.get(activity_id, ""))


## 好感 0-100 → 档位 1-5（阈值同 affinity_spec.level_thresholds：20/40/60/80）。
func affinity_level(score: int) -> int:
	var s := clampi(score, 0, AFFINITY_MAX)
	if s >= 80:
		return 5
	if s >= 60:
		return 4
	if s >= 40:
		return 3
	if s >= 20:
		return 2
	return 1


## 好感跨档 → 一句人话。**绝不返回分数**（free_time_system.json:2 红线：affinity 对玩家隐藏）。
## 没跨档返回空串（手账上就不写这一行，不硬凑）。
func relation_phrase(npc_id: String, before: int, after: int) -> String:
	var to_level := affinity_level(after)
	if to_level <= affinity_level(before):
		return ""
	var who := String(NPC_NAMES.get(npc_id, npc_id))
	match to_level:
		2:
			return "和%s，从点头之交变成了能聊两句的人。" % who
		3:
			return "和%s，像老熟人了。" % who
		4:
			return "和%s，到了能说点真的的地步。" % who
		_:
			return "和%s，是能托底的关系了。" % who


## ---------- 关系阶段：前台展示（机制文档 §5.4「前台展示关系阶段及进度感」） ----------
## V5.27 §11.3 定了 Lv1–Lv5 与「记忆墙便签蓝→黄→金渐进」，但此前**没有任何界面读过它**。
## 本节只做「把档位翻成人话 + 现档称谓」，**一个数字都不外露**——
## 分数、阈值、解锁条件都不出现在返回值里（free_time_system.json:2 红线）。
##
## 档位 → 现档称谓（不是"Lv3"这种编号，而是玩家读得懂的一句话）。
const RELATION_STAGE_TEXT := {
	1: "还只是点头之交",
	2: "能聊两句了",
	3: "老熟人了",
	4: "能说点真的",
	5: "能托底的关系",
}

## 现档称谓；npc_id 不认识返回空串（宁可不显示，也不要编一个）。
func relation_stage_name(npc_id: String) -> String:
	if not NPC_NAMES.has(npc_id):
		return ""
	return String(RELATION_STAGE_TEXT.get(affinity_level(affinity_of(npc_id)), ""))


## 显示名 → 内部 id。**NPC_NAMES 反过来查**，这样演员表口径仍然只有一处。
## 用途：剧情便签里只存了角色显示名（"王哥"），记忆墙要拿它反查好感档。
func relation_key_of_name(display_name: String) -> String:
	var key := display_name.strip_edges()
	if key.is_empty():
		return ""
	for npc_id in NPC_NAMES.keys():
		if String(NPC_NAMES[npc_id]) == key:
			return String(npc_id)
	return ""


## 显示名 → 现档称谓。查不到这个人（如陈工不进关系系统）返回空串。
func relation_stage_of_name(display_name: String) -> String:
	var npc_id := relation_key_of_name(display_name)
	if npc_id.is_empty():
		return ""
	return relation_stage_name(npc_id)


## 关系一览：给自由周末首屏用的只读快照。
## 返回 [{id, name, level, stage, pips}]，按 SOCIAL_POOL 顺序（= 机制文档的四人核心 NPC）。
## pips = 0-5 的档位段数，供界面画「●●●○○」这种进度感；**它不是分数**（只有段数）。
func relation_overview() -> Array:
	var rows: Array = []
	for raw_id in SOCIAL_POOL:
		var npc_id := String(raw_id)
		var level := affinity_level(affinity_of(npc_id))
		rows.append({
			"id": npc_id,
			"name": String(NPC_NAMES.get(npc_id, npc_id)),
			"level": level,
			"stage": String(RELATION_STAGE_TEXT.get(level, "")),
			"pips": level,
		})
	return rows


## ---------- 知心时刻（Lv2 私人故事，V5.27 §11.3 四段） ----------

## 好感门槛（free_time_system.json rules.level_unlocks.Lv2 / hooks.intimate_moment.when）。
const INTIMATE_MIN_AFFINITY := 40
## npc_id -> intimate_text（懒加载，只读一份）。
var _npc_story := {}


## 知心时刻正文（该 NPC 的私事独白）。取不到返回空串，调用方自行降级为通用触发句。
func intimate_text_of(npc_id: String) -> String:
	_ensure_npc_story()
	return String(_npc_story.get(npc_id, ""))


func _ensure_npc_story() -> void:
	if not _npc_story.is_empty():
		return
	var text := FileAccess.get_file_as_string(FREE_TIME_CONFIG)
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var npcs = (parsed as Dictionary).get("npcs", {})
	if not (npcs is Dictionary):
		return
	for key in (npcs as Dictionary).keys():
		var entry = (npcs as Dictionary)[key]
		if not (entry is Dictionary):
			continue
		var line := String((entry as Dictionary).get("intimate_text", ""))
		if not line.is_empty():
			_npc_story[String(key)] = line


## 两格 → 组合效果（设计文档 §3.4 两格版）。
## slots = [{activity: Dictionary, zone: String}, ...]；**空列表 / 只填一格 / 有留白 → 不参与判定**。
## 返回 {key, lines, state_delta, same_zone}：
## · key ∈ {"", all_work, all_social, all_solo, people_and_self, balanced_default}
## · state_delta 只含 S / O / H（组合不给人脉 N）
## · same_zone_focus 独立叠加（same_zone = true，并把 +1 并进 state_delta）
## 优先级：all_* > people_and_self > balanced_default。
func weekend_combo(slots: Array) -> Dictionary:
	var result := {"key": "", "lines": [], "state_delta": {}, "same_zone": false}
	var filled: Array = []
	for slot in slots:
		if not (slot is Dictionary):
			continue
		var activity = (slot as Dictionary).get("activity")
		if activity is Dictionary and not (activity as Dictionary).is_empty():
			filled.append(slot)
	if filled.size() < 2:
		return result

	# 归一：work 与 solo_work 同属「技术」。
	var cats: Array[String] = []
	for slot in filled:
		var raw := input_category_of(String((slot["activity"] as Dictionary).get("activity_id", "")))
		cats.append("work" if (raw == "work" or raw == "solo_work") else raw)

	var lines: Array[String] = []
	var delta := {}
	var key := "balanced_default"
	# ⚠ `work + social` 在判定表里没有条目 → 与 `work + solo_recover` 同落 balanced_default
	#   （平衡是默认值，不奖励）。**不新增组合键**，保持 6 键口径。
	if not cats[0].is_empty() and cats[0] == cats[1]:
		match cats[0]:
			"work":
				key = "all_work"
				delta = {"H": -1}
				lines.append("两天都没离开工位。这很像你——但身体记着账。")
			"social":
				key = "all_social"
				delta = {"H": -1}
				lines.append("两天都给了人。人缘是攒出来的，累也是真的。")
			"solo_recover":
				key = "all_solo"
				delta = {"H": 1}
				lines.append("两天都留给了自己。缓过来了。")
	elif cats.has("social") and cats.has("solo_recover"):
		key = "people_and_self"
		delta = {"H": 1}
		lines.append("一半给了人，一半给自己。这样的周末最好过。")

	result["key"] = key
	result["lines"] = lines
	result["state_delta"] = delta

	# same_zone_focus：两格同区域 → **该区域首个活动**收益 +1（一次）。
	# 「收益」= 首个活动 gain 里数值最大的那一项（gain 为空则按生命算），避免凭空造币种。
	var zone_a := String(filled[0].get("zone", ""))
	var zone_b := String(filled[1].get("zone", ""))
	if not zone_a.is_empty() and zone_a == zone_b:
		var gain = (filled[0]["activity"] as Dictionary).get("gain", {})
		var best_key := "H"
		var best_value := 0
		if gain is Dictionary:
			for stat in (gain as Dictionary).keys():
				var value := int(gain[stat])
				if value > best_value:
					best_value = value
					best_key = String(stat)
		delta[best_key] = int(delta.get(best_key, 0)) + 1
		result["same_zone"] = true
		result["state_delta"] = delta
		var merged: Array[String] = lines.duplicate()
		merged.append("两格都在同一片地方，脚熟，心也静。")
		result["lines"] = merged
	return result


## 投入结构人话（手账页那行总结）。**只报段数，不报好感分数**。
func weekend_structure_line(slots: Array) -> String:
	var counts := {"work": 0, "social": 0, "self": 0}
	var blanks := 0
	for slot in slots:
		if not (slot is Dictionary):
			continue
		var activity = (slot as Dictionary).get("activity")
		if not (activity is Dictionary) or (activity as Dictionary).is_empty():
			blanks += 1
			continue
		var raw := input_category_of(String((activity as Dictionary).get("activity_id", "")))
		if raw == "work" or raw == "solo_work":
			counts["work"] += 1
		elif raw == "social":
			counts["social"] += 1
		elif raw == "solo_recover":
			counts["self"] += 1
	var parts: Array[String] = []
	for pair in [["social", "给了人"], ["work", "给了技术"], ["self", "给了自己"]]:
		if int(counts[pair[0]]) > 0:
			parts.append("%s %d 格" % [pair[1], int(counts[pair[0]])])
	if parts.is_empty():
		return "这个周末，你什么都没安排。"
	var line := "这段周末，你%s。" % "、".join(parts)
	if blanks > 0:
		line += "　还有 %d 格留白。" % blanks
	return line


## 批量结算一个自由周末（§3.1：填格不结算，「就这样过」才一次性结算）。
## 逐格调 apply_weekend_activity()，再叠组合效果。
## 返回 {slot_results, combo, effects}：
## · slot_results[i] = {slotId, zone, activityId, targets, lines, relations}（relations 是人话短语）
## · combo = weekend_combo() 的原样返回
## · effects = 组合效果产生的人话行
func apply_weekend(slots: Array) -> Dictionary:
	var slot_results: Array = []
	var effects: Array[String] = []
	for slot in slots:
		if not (slot is Dictionary):
			continue
		var entry: Dictionary = {
			"slotId": String((slot as Dictionary).get("slotId", "")),
			"zone": String((slot as Dictionary).get("zone", "")),
			"activityId": "",
			"targets": [],
			"lines": [],
			"relations": [],
		}
		var activity = (slot as Dictionary).get("activity")
		if activity is Dictionary and not (activity as Dictionary).is_empty():
			var act := activity as Dictionary
			entry["activityId"] = String(act.get("activity_id", ""))
			var targets = (slot as Dictionary).get("targets", [])
			entry["targets"] = targets
			var before := {}
			for npc_id in affinity.keys():
				before[npc_id] = int(affinity[npc_id])
			var res: Dictionary = apply_weekend_activity(act, targets)
			entry["lines"] = res.get("lines", [])
			var phrases: Array[String] = []
			for npc_id in before.keys():
				var phrase := relation_phrase(String(npc_id), int(before[npc_id]), int(affinity[npc_id]))
				if not phrase.is_empty():
					phrases.append(phrase)
			entry["relations"] = phrases
		slot_results.append(entry)

	var combo: Dictionary = weekend_combo(slots)
	_apply_state_delta(combo.get("state_delta", {}))
	for line in combo.get("lines", []):
		effects.append(String(line))
	state_changed.emit(snapshot())
	return {"slot_results": slot_results, "combo": combo, "effects": effects}


## 组合效果的状态落点（S / O / H）。N 不进公开数值，组合也不使用 N。
func _apply_state_delta(delta) -> void:
	if not (delta is Dictionary):
		return
	var d := delta as Dictionary
	if int(d.get("S", 0)) != 0:
		skill = maxi(0, skill + int(d["S"]))
	if int(d.get("O", 0)) != 0:
		output = maxi(0, output + int(d["O"]))
	if int(d.get("H", 0)) != 0:
		health = clampi(health + int(d["H"]), 0, HEALTH_MAX)


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
			# ⚠ 决策拍的 `each` = 整个同事池（4 人）；活动拍的 `each`（apply_weekend_activity）
			# 只给同行者（targets）。两处语义不同是既有口径，本轮保留，改动前先看设计文档 §13.3。
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
	var tag_list = option.get("memory_tags")
	if tag_list is Array:
		# 累积进记忆墙的「旧事」池 —— 记忆类主动消息靠它才有可提的旧承诺。
		remember_tags(tag_list)
		for tag in tag_list:
			lines.append("记住了你：%s" % String(tag))
	var feedback := String(option.get("instant_feedback", ""))
	state_changed.emit(snapshot())
	return {"lines": lines, "feedback": feedback}


## B 件·在场一幕的应答结算（设计文档 §4：这是性格测量，不是好感度博弈）。
## **不碰任何数值** —— skill / output / health / 好感一律不动；好感照旧由活动自己的
## affinity_gain 在 apply_weekend_activity() 里给。这里只把选项的 memory_tags 翻成人话行。
## 返回 {lines, feedback, tags}：lines 供手账页展示（恒无数字），tags 供归档进 weekend_ledger。
func apply_encounter_option(option: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	var tags: Array[String] = []
	var raw_tags = option.get("memory_tags")
	if raw_tags is Array:
		remember_tags(raw_tags as Array)
		for tag in (raw_tags as Array):
			tags.append(String(tag))
	for tag in tags:
		lines.append("记住了你：%s" % tag)
	var feedback := String(option.get("instant_feedback", ""))
	return {"lines": lines, "feedback": feedback, "tags": tags}


## ---- D 件·回声（设计说明 §6.1）：世界记得你过怎样的周末 ----

## 从手账记录里挑出该在这里冒的那句回声。
## records = jsonl 解析出的周末手账数组；zone_code = 当前区域字母（A-H）。
## 规则：只挑 echoConsumed != true 的**最新一条**；它的某格 zone 字母前缀 == zone_code，
## 且活动在 echo_cfg.echoes 里有词；词条 npc 为 "any" 或等于该格同行者之一。
## 找不到就空手回 {}。纯函数：文件读写不在这里，消费走 consume_weekend_echo()。
func pick_weekend_echo(records: Array, zone_code: String, echo_cfg: Dictionary, npc_names: Dictionary) -> Dictionary:
	var entries = echo_cfg.get("echoes", echo_cfg)
	if not (entries is Dictionary):
		return {}
	for i in range(records.size() - 1, -1, -1):
		var rec = records[i]
		if not (rec is Dictionary) or bool(rec.get("echoConsumed", false)):
			continue
		for slot in rec.get("slots", []):
			if not (slot is Dictionary):
				continue
			var zone := String(slot.get("zone", ""))
			if zone.is_empty():
				continue
			var letter := String(zone.strip_edges().split("_")[0]).to_upper()
			if letter != zone_code:
				continue
			var act_id := String(slot.get("activityId", ""))
			var options = entries.get(act_id)
			if not (options is Array):
				continue
			var targets_v = slot.get("targets", [])
			var targets: Array = targets_v if targets_v is Array else []
			for opt in (options as Array):
				if not (opt is Dictionary):
					continue
				var who := String(opt.get("npc", "any"))
				if who != "any" and not (targets.has(who)):
					continue
				var line := String(opt.get("line", ""))
				if line.is_empty():
					continue
				var npc_id := String(targets[0]) if not targets.is_empty() else who
				var npc_name := String(npc_names.get(npc_id, npc_id)) if not npc_id.is_empty() else "有人"
				if npc_id == "any" or npc_id.is_empty():
					npc_name = "同事们"
				return {
					"month": int(rec.get("month", 0)),
					"slotId": String(slot.get("slotId", "")),
					"activityId": act_id,
					"npcId": npc_id,
					"npcName": npc_name,
					"line": line,
				}
	return {}


## 把某条手账标记为「回声已消费」（§6.1：只提一次，提完消费掉，不做复读机）。
## 整读整写 jsonl——一个存档最多 16 行，量级无所谓。
## 匹配键：month + 该条里出现过 slotId 的那条记录（一个周末一条记录）。
func consume_weekend_echo(file_path: String, month: int, slot_id: String) -> bool:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return false
	var lines: Array[String] = []
	while not f.eof_reached():
		var raw := f.get_line()
		if not raw.strip_edges().is_empty():
			lines.append(raw)
	f.close()
	var changed := false
	var out: Array[String] = []
	for raw in lines:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary and not changed \
				and int(parsed.get("month", -1)) == month:
			var hit := false
			for slot in parsed.get("slots", []):
				if slot is Dictionary and String(slot.get("slotId", "")) == slot_id:
					hit = true
					break
			if hit:
				parsed["echoConsumed"] = true
				changed = true
				out.append(JSON.stringify(parsed))
				continue
		out.append(raw)
	if not changed:
		return false
	var w := FileAccess.open(file_path, FileAccess.WRITE)
	if w == null:
		return false
	for line in out:
		w.store_line(line)
	w.close()
	return true


## 知心时刻触发条件（free_time_system hooks.intimate_moment）。
## 两条路径：
##   ① 好感够 Lv2 门槛（INTIMATE_MIN_AFFINITY = 40）；
##   ② D4 夜宵的 hooks.early_secret 命中 → apply_weekend_activity 落了
##      intimate_early_<npc> 旗标 → **提前解锁**，不再看好感。
## ⚠ ② 此前是**死旗标**：全库没有任何地方读它，"炭火让人诚实"那条收益
##   （好感少拿 1 换提前解锁）等于白给。2026-09-17 接上消费者。
func can_trigger_intimate(npc_id: String) -> bool:
	if intimate_used.has(npc_id):
		return false
	if flags.get("intimate_early_" + npc_id, false):
		return true
	return affinity_of(npc_id) >= INTIMATE_MIN_AFFINITY


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
