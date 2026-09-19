extends RefCounted

## NPC 主动消息规则核心（机制文档 §2「有人记得我」+ V5.27 §11.8/§11.9）。
##
## 只管「这个月该谁说话、说什么」，不管界面也不管存档——纯函数式：
## generate(ctx) 读一遍局面，吐出该发的消息数组，调用方自己存。
## 探针因此可以造任意局面（低生命 / 某关系等级 / 某记忆标签）直接断言。
##
## 三条红线：
## ① 消息里不出现好感分数、等级数字、测评结论——只说人话（数据层保证，本类不加工数值）。
## ② 训练谷邀约必须由共同经历引出（when.month_min 卡在对应幕之后），不许凭空出现。
## ③ 冷却 + 优先级防轰炸（机制文档 §5）：同 NPC 隔 N 月、每月最多 M 条。

const CONFIG_PATH := "res://data/story/npc_messages.json"

## ctx 字段（全部可选，缺了按「没发生」处理）：
##   month            int        当前月份
##   health           int        当前生命
##   forced_rest      bool       本月是否被摁着休息
##   levels           Dict       {npc_id: 关系等级}
##   flags            Dict       剧情标记（如 E28_signature_taken）
##   memory_tags      Array      已攒的记忆标签
##   cleared_duels    Array      已首通的训练谷关卡 id
##   sent             Dict       {msg_id: 发送月份}——once 去重就靠它
##   last_month_by_npc Dict      {npc_id: 上次发消息的月份}——冷却就靠它
##   npc_names        Dict       {npc_id: 显示名}——数据显示名，本类零硬编码
## 消息定义（data/story/npc_messages.json）支持的可选字段：
##   npc              String   固定发送者；from_top_buddy=true 时省略
##   from_top_buddy   bool     发送者改为「当时好感最高的挚友」（见 _top_buddy）
##   when.level_min   int      from_top_buddy 时兼作门槛：没人到这一档整条不触发
##   when.month_in    Array    白名单月份（如考核窗前一月）
##   when.sent_any    Array    二手传播链：数组内任一消息 id 已发过才触发（社交记忆 §11.8 第四层）
##   exempt_cooldown  bool     豁免同 NPC 冷却（解锁玩法 / 关键事件用）
## 返回 [{id, npc, npc_name, kind, text, month, read, unlocks_duel?}]
static func generate(ctx: Dictionary) -> Array:
	var cfg := load_config()
	var rules: Dictionary = cfg.get("rules", {})
	var cooldown := int(rules.get("per_npc_cooldown_months", 3))
	var max_per_month := int(rules.get("max_per_month", 2))
	var priority: Dictionary = rules.get("priority", {})
	var month := int(ctx.get("month", 1))
	var sent: Dictionary = ctx.get("sent", {})
	var last_month: Dictionary = ctx.get("last_month_by_npc", {})
	var names: Dictionary = ctx.get("npc_names", {})

	var packed: Array = []
	for msg in cfg.get("messages", []):
		var def: Dictionary = msg
		var msg_id := String(def.get("id", ""))
		if msg_id.is_empty() or sent.has(msg_id):
			continue  # once：发过就不再发
		var npc := String(def.get("npc", ""))
		if bool(def.get("from_top_buddy", false)):
			# 挚友干涉（V5.27 §11.7 Lv4）：发送者不是写死的人，而是「当时好感最高的那位」。
			# 没人到 level_min 档 → 整条不触发（宁可漏发，也不让普通同事说挚友的话）。
			var levels: Dictionary = ctx.get("levels", {})
			npc = _top_buddy(levels, int((def.get("when", {}) as Dictionary).get("level_min", 4)))
			if npc.is_empty():
				continue
		if not _match(def.get("when", {}), ctx, npc):
			continue
		if not bool(def.get("exempt_cooldown", false)):
			# 训练谷邀约走 exempt：它解锁玩法，不能被冷却挡住。
			var prev := int(last_month.get(npc, -999))
			if month - prev < cooldown:
				continue
		packed.append({"def": def, "idx": packed.size(), "npc": npc})

	# 优先级高的先发；同优先级按数据文件里的声明顺序（先声明者先发）。
	packed.sort_custom(func(a, b):
		var pa := int(priority.get(String((a["def"] as Dictionary).get("kind", "")), 0))
		var pb := int(priority.get(String((b["def"] as Dictionary).get("kind", "")), 0))
		if pa != pb:
			return pa > pb
		return int(a["idx"]) < int(b["idx"])
	)

	var out: Array = []
	for i in mini(packed.size(), max_per_month):
		var item: Dictionary = packed[i]
		var def: Dictionary = (item["def"] as Dictionary)
		var npc := String(item.get("npc", def.get("npc", "")))
		var entry := {
			"id": String(def.get("id", "")),
			"npc": npc,
			"npc_name": String(names.get(npc, npc)),
			"kind": String(def.get("kind", "")),
			"text": String(def.get("text", "")),
			"month": month,
			"read": false,
		}
		var unlocks = def.get("unlocks_duel")
		if unlocks != null and String(unlocks) != "":
			entry["unlocks_duel"] = String(unlocks)
		out.append(entry)
	return out


## when 条件解析。空 when = 永不触发（无条件广播会变成轰炸，宁可漏发）。
static func _match(when: Dictionary, ctx: Dictionary, npc: String) -> bool:
	if when.is_empty():
		return false
	var month := int(ctx.get("month", 1))
	if when.has("month_min") and month < int(when.get("month_min", 0)):
		return false
	if when.has("month_max") and month > int(when.get("month_max", 9999)):
		return false
	if when.has("month_in"):
		# 白名单月份（如考核窗前一月）。比 month_min/month_max 更适合「每 6 个月一次」的节奏。
		# JSON 数字在 Godot 里是 float，这里逐个 int() 比较，别依赖 has() 的隐式数值比较。
		var hit := false
		for v in (when.get("month_in", []) as Array):
			if int(v) == month:
				hit = true
				break
		if not hit:
			return false
	if when.has("health_max") and int(ctx.get("health", 99)) > int(when.get("health_max", 0)):
		return false
	if when.has("health_min") and int(ctx.get("health", 0)) < int(when.get("health_min", 0)):
		return false
	if when.has("forced_rest") and bool(ctx.get("forced_rest", false)) != bool(when.get("forced_rest", false)):
		return false
	if when.has("level_min"):
		var levels: Dictionary = ctx.get("levels", {})
		if int(levels.get(npc, 0)) < int(when.get("level_min", 0)):
			return false
	if when.has("flags_any"):
		var flags: Dictionary = ctx.get("flags", {})
		if not _any_key_in(flags, when.get("flags_any", [])):
			return false
	if when.has("tags_any"):
		var tags: Array = ctx.get("memory_tags", [])
		if not _any_in_list(tags, when.get("tags_any", [])):
			return false
	if when.has("sent_any"):
		# 二手传播（社交记忆，V5.27 §11.8 第四层）：前一条消息发出去之后，
		# 这话才轮得到说——「A 跟你聊过 B，B 后来才有下文」。
		# sent 在 generate 返回后才由调用方更新，所以同一轮内 A、B 不会同月连发。
		var sent_seen: Dictionary = ctx.get("sent", {})
		if not _any_key_in(sent_seen, when.get("sent_any", [])):
			return false
	if when.has("duel_cleared_all"):
		var cleared: Array = ctx.get("cleared_duels", [])
		for need in (when.get("duel_cleared_all", []) as Array):
			if not cleared.has(String(need)):
				return false
	return true


## 挚友干涉的发送者：levels 里 ≥ level_min 且好感最高的那位。
## 平局取先遇到的 —— 调用方（MonthlyLife）按 NPC_NAMES 定义顺序填 levels，
## 该顺序前四位与 SOCIAL_POOL 一致（王哥 → 小林 → 小赵 → 老周），平局因此按名单定序。
## （NPC_NAMES 里多出的「熊总」不在 SOCIAL_POOL、也没有任何好感来源，永远 0 分，不会当选。）
## 没人到档位 → 返回空串，调用方据此整条跳过。
static func _top_buddy(levels: Dictionary, level_min: int) -> String:
	var best := ""
	var best_level := level_min - 1
	for raw_id in levels.keys():
		var lv := int(levels[raw_id])
		if lv > best_level:
			best_level = lv
			best = String(raw_id)
	return best


static func _any_key_in(flags: Dictionary, keys) -> bool:
	for k in (keys as Array):
		if flags.has(String(k)):
			return true
	return false


static func _any_in_list(haystack: Array, needles) -> bool:
	for n in (needles as Array):
		if haystack.has(String(n)):
			return true
	return false


static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("NpcMessageSystem：找不到 %s，本月无主动消息。" % CONFIG_PATH)
		return {}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	push_warning("NpcMessageSystem：%s 不是对象，本月无主动消息。" % CONFIG_PATH)
	return {}
