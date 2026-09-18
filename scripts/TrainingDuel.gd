class_name TrainingDuel
extends RefCounted
## 训练谷 · 熊熊有招 —— 纯规则核心（Batch 4）。
## 规则唯一口径：data/story/training_valley.json + 机制文档 §7。
## 核心顺序不可改：先投骰 → 攻方 0/1 张进攻/调整卡 → 守方 0/1 张防御卡 → 结算 → 换人。
## 测评红线（机制文档 §10）：胜负 / 骰运 / 卡牌使用 / 选择角色一律不进职业测评，
## 本类不读写任何测评概念，snapshot 只暴露白名单键。
## AI 决策全部只看状态、不看 rng —— 保证探针可复现。

const CONFIG_PATH := "res://data/story/training_valley.json"

## 白名单：snapshot() 只允许出现这些顶层键（probe_training_duel 会断言）
const SNAPSHOT_KEYS := [
	"level_id", "partner_id", "opponent", "hp", "max_hp", "hands", "actor", "phase",
	"rounds_done", "over", "winner", "current_roll", "last_turn", "turn_count",
]

var level: Dictionary = {}
## 熊友搭档（Batch 5 §6.3）：{"npc_id","name","ability","value"}；空 = 自己上。
## 四个旋钮只作用玩家侧：hand_bonus / hand_cap_bonus / damage_bonus / guard_bonus。
var _partner: Dictionary = {}
var rng: RandomNumberGenerator

var max_hp := 20
var hp := {"player": 20, "opponent": 20}
var hands := {"player": [], "opponent": []}  # 卡 id 数组（可重复，公共卡池随机）
var pool: Array = []                          # 卡池（卡 id 数组）
var cards_by_id: Dictionary = {}

var actor := "player"      # "player" | "opponent"（玩家先手）
var phase := "roll"        # "roll" -> "attack" -> "defend" -> 结算后回到 "roll"
var rounds_done := 0
var over := false
var winner := ""           # "" | "player" | "opponent"

var current_roll := 0
var _extra_total := 0      # 连续推进累计的追加伤害
var _double := false       # 乘胜追击标记
var _guard := 0            # 先挡一下（守方）标记
var turn_count := 0
var last_turn: Dictionary = {}
var log: Array = []        # 逐回合结算记录（探针断言用）
var _rules: Dictionary = {}  # create() 时缓存，别每掷一次骰就读一次盘


static func load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("TrainingDuel: 读不到 %s" % CONFIG_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


## 建一局。rng 由调用方注入（探针用固定种子复现骰运）。
## partner 可选：{"npc_id","name","ability","value"}，能力只作用玩家侧。
static func create(p_level: Dictionary, p_rng: RandomNumberGenerator, p_partner := {}) -> TrainingDuel:
	var cfg := load_config()
	var d: TrainingDuel = new()
	d.level = p_level
	d.rng = p_rng
	d._rules = cfg.get("rules", {})
	d._partner = p_partner if p_partner is Dictionary else {}
	var rules: Dictionary = d._rules
	d.max_hp = int(rules.get("hp", 20))
	d.hp = {"player": d.max_hp, "opponent": d.max_hp}
	for card: Dictionary in cfg.get("cards", []):
		d.cards_by_id[String(card.get("id"))] = card
		d.pool.append(String(card.get("id")))
	var base_hand := int(rules.get("start_hand", 3))
	for i in base_hand + d._ability_value("hand_bonus"):
		d.hands["player"].append(d._draw_one())
	for i in base_hand:
		d.hands["opponent"].append(d._draw_one())
	return d


## 搭档能力（只玩家侧）。name 不匹配就返回 0，等于没有加成。
func _ability_value(name: String) -> int:
	if String(_partner.get("ability", "")) != name:
		return 0
	return int(_partner.get("value", 0))


func _draw_one() -> String:
	return pool[rng.randi_range(0, pool.size() - 1)]


func is_over() -> bool:
	return over


func defender_id() -> String:
	return "opponent" if actor == "player" else "player"


## ── 阶段 1：投骰 ──────────────────────────────────────────────
## 返回 0 表示当前不在 roll 阶段（越序调用被拒）。
func roll() -> int:
	if over or phase != "roll":
		return 0
	current_roll = rng.randi_range(1, int(_rules.get("dice_sides", 6)))
	phase = "attack"
	return current_roll


## ── 阶段 2：攻方出 0/1 张进攻/调整卡 ─────────────────────────
## 返回 false = 越序（不在 attack 阶段 / 没这张卡）。攻方是当前 actor（双方都可能），
## 玩家侧的输入合法性由 UI 层把守，规则层只认阶段。
func play_attack_card(card_id: String) -> bool:
	if over or phase != "attack":
		return false
	var hand: Array = hands[actor]
	if not hand.has(card_id):
		return false
	var card: Dictionary = cards_by_id.get(card_id, {})
	if card.is_empty() or String(card.get("timing", "")) != "attack":
		return false
	hand.erase(card_id)
	match String(card.get("effect", "")):
		"damage_double":
			_double = true
		"reroll":
			# 重投一次，必须接受新点数（立即生效）
			current_roll = rng.randi_range(1, int(_rules.get("dice_sides", 6)))
		"extra_roll":
			_extra_total += rng.randi_range(1, int(_rules.get("dice_sides", 6)))
		"heal_3":
			var heal := int(_rules.get("heal_amount", 3))
			hp[actor] = mini(int(hp[actor]) + heal, max_hp)
		_:
			pass
	phase = "defend"
	return true


func pass_attack() -> void:
	if not over and phase == "attack":
		phase = "defend"


## ── 阶段 3：守方出 0/1 张防御卡 ──────────────────────────────
func play_defend_card(card_id: String) -> bool:
	if over or phase != "defend":
		return false
	var def_id := defender_id()
	var hand: Array = hands[def_id]
	if not hand.has(card_id):
		return false
	var card: Dictionary = cards_by_id.get(card_id, {})
	if String(card.get("timing", "")) != "defend":
		return false
	hand.erase(card_id)
	if String(card.get("effect", "")) == "reduce_3":
		_guard = int(_rules.get("guard_reduce", 3))
		# 搭档「留一手」只给玩家侧（老周）
		if defender_id() == "player":
			_guard += _ability_value("guard_bonus")
	_settle()
	return true


func pass_defend() -> void:
	if over or phase != "defend":
		return
	_settle()


## ── 结算 ─────────────────────────────────────────────────────
func _settle() -> void:
	var raw := (current_roll + _extra_total) * (2 if _double else 1)
	# 搭档「进攻性格」只给玩家侧（小林）
	if actor == "player":
		raw += _ability_value("damage_bonus")
	var damage: int = maxi(raw - _guard, 0)
	var def_id := defender_id()
	hp[def_id] = maxi(int(hp[def_id]) - damage, 0)
	turn_count += 1
	last_turn = {
		"round": rounds_done + 1,
		"actor": actor,
		"roll": current_roll,
		"extra": _extra_total,
		"double": _double,
		"guard": _guard,
		"damage": damage,
		"defender": def_id,
	}
	log.append(last_turn.duplicate())
	# 复位回合中间量
	current_roll = 0
	_extra_total = 0
	_double = false
	_guard = 0
	if int(hp[def_id]) <= 0:
		over = true
		winner = actor
		phase = "over"
		return
	if actor == "player":
		# 每个完整回合恒由玩家先手（规则：玩家先手）
		actor = "opponent"
	else:
		# 双方各行动过一次 = 一个完整回合
		rounds_done += 1
		_maybe_draw()
		actor = "player"
	phase = "roll"


func _maybe_draw() -> void:
	var every := int(_rules.get("draw_every_rounds", 2))
	var cap := int(_rules.get("hand_cap", 5))
	if every <= 0 or rounds_done % every != 0:
		return
	for side in ["player", "opponent"]:
		# 搭档「细心兜底」只放宽玩家侧上限（小赵）
		var side_cap: int = cap + (_ability_value("hand_cap_bonus") if side == "player" else 0)
		if hands[side].size() < side_cap:
			hands[side].append(_draw_one())


## ── AI（风格化，只看状态不看 rng）─────────────────────────────
## 攻方决策：返回要出的卡 id，或 "" 不出。
func ai_attack_decision() -> String:
	if phase != "attack" or actor != "opponent":
		return ""
	var hand: Array = hands["opponent"]
	var my_hp := int(hp["opponent"])
	var foe_hp := int(hp["player"])
	var style := String(level.get("ai_style", "teaching"))
	var has := func(cid: String) -> bool: return hand.has(cid)
	match style:
		"teaching":
			# 教学型：出牌直接、容错高 —— 有乘胜追击就放大，血少先补给
			if has.call("double_down") and current_roll >= 4:
				return "double_down"
			if has.call("supply") and my_hp <= 8:
				return "supply"
		"aggressive":
			# 进攻型：高点数扩大伤害，低点数赌重投，几乎不留防御
			if has.call("double_down") and current_roll >= 4:
				return "double_down"
			if has.call("extra_roll") and current_roll >= 4:
				return "extra_roll"
			if has.call("reroll") and current_roll <= 2:
				return "reroll"
			if has.call("supply") and my_hp <= 6:
				return "supply"
		"steady":
			# 稳健型：重视续航，留防御牌；够本才放大
			if has.call("supply") and my_hp <= 10:
				return "supply"
			if has.call("double_down") and current_roll >= 3:
				return "double_down"
		"tactical":
			# 算计型：算终结与反制时机
			if has.call("double_down") and current_roll * 2 >= foe_hp:
				return "double_down"
			if has.call("extra_roll") and current_roll + 3 >= foe_hp:
				return "extra_roll"
			if has.call("double_down") and current_roll >= 5:
				return "double_down"
			if has.call("supply") and my_hp <= 6:
				return "supply"
	return ""


## 守方决策（AI 在守方时调用）：返回 "guard" 或 ""。
func ai_defend_decision(incoming_damage: int) -> String:
	if phase != "defend" or actor == "opponent":
		return ""
	if not hands["opponent"].has("guard"):
		return ""
	var my_hp := int(hp["opponent"])
	var style := String(level.get("ai_style", "teaching"))
	match style:
		"teaching":
			return "guard"  # 教学型：示范防御怎么用
		"aggressive":
			return "guard" if my_hp <= 5 else ""
		"steady":
			return "guard" if (incoming_damage >= 5 or my_hp <= 8) else ""
		"tactical":
			return "guard" if (incoming_damage >= my_hp - 3 or incoming_damage >= 6) else ""
	return ""


## AI 整个攻方行动（投骰 + 出牌决策）。面板与探针共用。
## 返回 {roll, card}；card 为 "" 表示不出。
func ai_full_attack() -> Dictionary:
	var r := roll()
	if r == 0:
		return {"roll": 0, "card": ""}
	var cid := ai_attack_decision()
	if cid != "":
		play_attack_card(cid)
	else:
		pass_attack()
	return {"roll": r, "card": cid}


## AI 守方自动应答（攻方是玩家、进入 defend 阶段后调用）。
func ai_auto_defend() -> void:
	if phase != "defend" or actor != "player":
		return
	var raw := (current_roll + _extra_total) * (2 if _double else 1)
	if ai_defend_decision(raw) == "guard":
		play_defend_card("guard")
	else:
		pass_defend()


## ── 快照（键白名单，绝不含测评字段）─────────────────────────
func snapshot() -> Dictionary:
	return {
		"level_id": String(level.get("id", "")),
		"partner_id": String(_partner.get("npc_id", "")),
		"opponent": String(level.get("opponent", "")),
		"hp": hp.duplicate(),
		"max_hp": max_hp,
		"hands": {"player": (hands["player"] as Array).duplicate(), "opponent": (hands["opponent"] as Array).duplicate()},
		"actor": actor,
		"phase": phase,
		"rounds_done": rounds_done,
		"over": over,
		"winner": winner,
		"current_roll": current_roll,
		"last_turn": last_turn.duplicate(),
		"turn_count": turn_count,
	}
