class_name StoryEventPanel
extends CanvasLayer

## 主线事件演出。
##
## 版式几代演进：
##   第一代 = 全屏压暗 + 土黄弹窗，玩家在"弹窗里"做选择。
##   第二代 = 场景全屏 + 立绘 + 底部对话条 + 结果拍 + 记忆便签 + 黑场入场卡。
##   第三代 = 本版。对话层改成戏剧演出：
##            黑色撕裂气泡、立绘压边、左上角日期时段牌、右下角操作提示，
##            以及最要紧的一条 —— beats 分镜脚本：事件可以排演一段戏，
##            而不是"NPC 说一句、玩家答一句"。
##
## beats（分镜）一个 beat 一个动作：
##   say       某人说话（气泡 + 名字牌 + 立绘聚焦）
##   narration 旁白（无立绘聚焦，人物退到背景）
##   interact  可交互物（翻开手册这类，点了才继续）
##   choice    三选一
## 没有 beats 的老事件自动退化成「入场卡 → 旁白 → 选择 → 结果」，行为不变。
##
## 三条红线（V5.27）：
##   1. 结果必须给，且只用行为语言 —— 永不出现数字。
##   2. 情境强度只走光影，不显示任何标签。
##   3. 独处事件 cast 为空 —— 画面上真的没有人。

signal choice_confirmed(event_id: String, choice_id: String, duration_minutes: int)
signal outcome_acknowledged(event_id: String, choice_id: String, duration_minutes: int)
signal decision_opened(event_id: String)
signal choice_hovered(event_id: String, choice_id: String)
## 手册阅读埋点回传（各章时长 / 跳过行为），由外部落盘
signal handbook_recorded(event_id: String, records: Dictionary)
## 结果拍浮出「记忆便签」时回传整条记录，由外部落盘。
## 便签是心湖记忆墙的唯一数据源：落了盘，玩家下次进游戏还能翻到自己当时贴了什么；
## 不落盘它就只是"弹一下就没了"的装饰。
signal memo_recorded(event_id: String, memo: Dictionary)

const HANDBOOK := preload("res://scripts/HandbookPanel.gd")
const TORN_BUBBLE := preload("res://scripts/ui/TornBubble.gd")

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const DOLL_ATLAS := "res://assets/characters/paper_doll_64/portraits/%s_walk_64.png"
const TYPE_INTERVAL := 0.022

## 入场拍：黑场里先把"这是哪一幕、哪一天、什么地方"压上来，再落进叙述。
const ENTRY_CARD_IN := 0.35
const ENTRY_HOLD := 1.45
const ENTRY_OUT := 0.5
## 黑场不完全捂住房间：留一点影子，玩家知道"人还站在那个屋里"。
const ENTRY_DIM := 0.62

## 立绘尺寸：说话人放大压边，旁听者缩小压暗。
## 像素图放大走 NEAREST 过滤，保住像素块硬边，不做线性模糊。
const FOCUS_SCALE := 4.3
const IDLE_SCALE := 2.3
## 水平落点（占总宽比例）。0.075 / 0.925 让立绘有一角实打实伸到画面外，形成"压边"。
const SLOT_X := {"left": 0.075, "right": 0.925}
const GROUND_Y := 0.86

## 区域内景图：剧情演出与可探索室内共用同一批场景美术。
const INTERIOR_BY_ZONE := {
	"A": "res://assets/场景内部图/熊起东方总部.png",
	"B": "res://assets/场景内部图/云栖科技丘.png",
	"C": "res://assets/场景内部图/创意水巷.png",
	"D": "res://assets/场景内部图/树影图书馆.png",
	"E": "res://assets/场景内部图/松风训练谷.png",
	"F": "res://assets/场景内部图/观澜展会码头.png",
	"G": "res://assets/场景内部图/暖邻康护院.png",
	"H": "res://assets/场景内部图/慢生活园.png",
}

const BEAR_LOADOUT_BY_ACTOR := {
	"小熊": "bear_green_cardigan",
	"王哥": "bear_plaid_glasses",
	"陈工": "bear_beige_blazer",
	"小林": "bear_green_cardigan",
	"老周": "bear_orange_blazer",
	"小赵": "bear_green_cardigan",
}

## 情境强度只做光影，不显示任何标签或数字（V5.27 红线：测量口径不下发前端）
const SITUATION_SHADE := {
	"weak": Color(0.05, 0.08, 0.16, 0.52),
	"medium": Color(0.06, 0.09, 0.14, 0.33),
	"strong": Color(0.12, 0.08, 0.05, 0.24),
}
const NOTE_TONE := {
	"gold": Color("f2c14e"),
	"gray": Color("9aa2ab"),
}

const BUBBLE_FILL := Color(0.05, 0.05, 0.07, 0.95)
const BUBBLE_FILL_HOT := Color(0.14, 0.13, 0.17, 0.97)
const BUBBLE_LINE := Color(0.97, 0.96, 0.92)
const PLATE_FILL := Color(0.97, 0.96, 0.93)
const PLATE_LINE := Color(0.06, 0.05, 0.08)
const INK := Color(0.10, 0.09, 0.12)
const PAD_X := 46.0

var _root: Control
var _stage_layer: Control
var _ui_layer: Control
var _handbook: CanvasLayer
var _event: Dictionary = {}
var _stage := "closed"
var _chosen_id := ""
var _actors: Array[Dictionary] = []
var _beats: Array = []
var _beat_index := -1
var _entry_fade: ColorRect
var _entry_card: Control
var _entry_age := 0.0
var _top_bar: Control
var _typewriter_label: Label
var _typewriter_full := ""
var _typewriter_shown := 0
var _typewriter_timer: Timer


func _ready() -> void:
	layer = 150
	_root = Control.new()
	_root.name = "EventOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_gui_input)
	add_child(_root)
	_root.hide()
	_stage_layer = Control.new()
	_stage_layer.name = "StageLayer"
	_stage_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage_layer)
	_ui_layer = Control.new()
	_ui_layer.name = "UiLayer"
	_ui_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ui_layer)
	_handbook = HANDBOOK.new()
	_handbook.name = "Handbook"
	_handbook.handbook_closed.connect(_on_handbook_closed)
	add_child(_handbook)
	_typewriter_timer = Timer.new()
	_typewriter_timer.wait_time = TYPE_INTERVAL
	add_child(_typewriter_timer)
	_typewriter_timer.timeout.connect(_tick_typewriter)


func present(event: Dictionary) -> void:
	_event = event.duplicate(true)
	_chosen_id = ""
	_beats = _event.get("beats", []) as Array
	if _beats.is_empty():
		_beats = [
			{"type": "narration", "text": String(_event.get("story", "事件内容待补充。"))},
			{"type": "choice"},
		]
	_beat_index = -1
	_build_stage()
	_show_entry()
	_root.show()


func dismiss() -> void:
	_stage = "closed"
	_stop_typewriter()
	_entry_fade = null
	_entry_card = null
	_root.hide()


func is_open() -> bool:
	return _root != null and _root.visible


func current_stage() -> String:
	return _stage


func beat_index() -> int:
	return _beat_index


## 入场拍的淡入/停留由 _process 自己按秒数推进，不用 Tween、不用 Timer：
## 玩家在淡入途中点击时不会留下"半个动画"去改已经释放的节点。
func _process(delta: float) -> void:
	if _stage != "entry":
		return
	_entry_age += delta
	var total := ENTRY_CARD_IN + ENTRY_HOLD + ENTRY_OUT
	var out := clampf((_entry_age - ENTRY_CARD_IN - ENTRY_HOLD) / ENTRY_OUT, 0.0, 1.0)
	if is_instance_valid(_entry_card):
		_entry_card.modulate.a = clampf(_entry_age / ENTRY_CARD_IN, 0.0, 1.0) * (1.0 - out)
	if is_instance_valid(_entry_fade):
		var dim_in := clampf((_entry_age - 0.15) / 0.7, 0.0, 1.0)
		_entry_fade.color.a = lerpf(1.0, ENTRY_DIM, dim_in) * (1.0 - out)
	if _entry_age >= total:
		_end_entry()


# ---------------------------------------------------------------- 场景层

func _build_stage() -> void:
	for child in _stage_layer.get_children():
		child.queue_free()
	_actors.clear()
	var size := _view_size()
	var zone := String(_event.get("locationId", "B"))
	var room := TextureRect.new()
	room.texture = _load_texture(String(INTERIOR_BY_ZONE.get(zone, INTERIOR_BY_ZONE["B"])))
	room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_layer.add_child(room)
	var shade := ColorRect.new()
	shade.color = _stage_shade()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_layer.add_child(shade)
	# 下半幅再压一层：气泡坐在暗角上才读得清字，也是剧场感的来源
	var floor_shade := ColorRect.new()
	floor_shade.color = Color(0.02, 0.02, 0.04, 0.40)
	floor_shade.position = Vector2(0, size.y * 0.60)
	floor_shade.size = Vector2(size.x, size.y * 0.40)
	floor_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_layer.add_child(floor_shade)
	_build_date_badge()
	_build_top_bar()
	for actor in _cast_list():
		_add_actor(actor)
	_layout_actors("")


## 光影 = 情境强度 × 时段：白天别把画面压死，深夜才沉下去。
## weak / medium / strong 只在明暗上有差别，不出现任何文字标签。
func _stage_shade() -> Color:
	var base: Color = SITUATION_SHADE.get(String(_event.get("situation", "medium")), SITUATION_SHADE["medium"])
	var hour := int(_event.get("hour", 12))
	if hour >= 8 and hour < 17:
		return Color(base.r, base.g, base.b, maxf(0.18, base.a - 0.16))
	if hour >= 19 or hour < 6:
		return Color(base.r, base.g, base.b, minf(0.74, base.a + 0.08))
	return base


## 左上角日期时段牌。玩家一眼知道"这是哪一天、什么时辰"——
## 整部戏的测量口径就建立在"这件事什么时候发生"上面，时间必须一直在场。
func _build_date_badge() -> void:
	var stamp := _date_stamp(int(_event.get("month", 1)), int(_event.get("day", 1)), int(_event.get("hour", 9)))
	var plate: Control = TORN_BUBBLE.new()
	plate.name = "DateBadge"
	plate.size = Vector2(212, 142)
	plate.position = Vector2(48, 34)
	plate.fill_color = PLATE_FILL
	plate.outline_color = PLATE_LINE
	plate.outline_width = 4.0
	plate.tail_side = "none"
	plate.jag = 9.0
	plate.shape_seed = 991
	_stage_layer.add_child(plate)
	var big := _label(stamp["date"], 40, INK, true)
	big.position = Vector2(26, 20)
	big.size = Vector2(160, 56)
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(big)
	var week := _label(stamp["weekday"], 19, INK)
	week.position = Vector2(28, 80)
	week.size = Vector2(160, 26)
	plate.add_child(week)
	var phase := _label(stamp["phase"], 22, INK, true)
	phase.position = Vector2(28, 106)
	phase.size = Vector2(160, 30)
	plate.add_child(phase)


## 顶栏在入场拍先藏着 —— 那一刻画面中央已经有事件卡，再顶一行同样的话是重复。
func _build_top_bar() -> void:
	_top_bar = Control.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.hide()
	_stage_layer.add_child(_top_bar)
	var act := _label(String(_event.get("actTitle", "主线事件")), 20, Color("ffe6b0"))
	act.position = Vector2(52, 190)
	act.size = Vector2(520, 32)
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_top_bar.add_child(act)
	var where := "%s · %s" % [String(_event.get("title", "")), String(_event.get("location", ""))]
	var place := _label(where, 18, Color("e8dcc4"))
	place.size = Vector2(508, 30)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	place.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	place.position = Vector2(-560, 192)
	_top_bar.add_child(place)


## 事件卡上的时间戳：只用事件自带的 month / day / hour，不另外读时钟。
func clock_text() -> String:
	return "第 %d 月 %d 日 · %02d:00" % [
		int(_event.get("month", 1)), int(_event.get("day", 1)), int(_event.get("hour", 9)),
	]


## 日期牌的显示口径：月/日 + 周几 + 时段，和 WorldClock 的 30 天月制对齐（不做真实历法）。
func _date_stamp(month: int, day: int, hour: int) -> Dictionary:
	const WEEKDAYS := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
	var total := (maxi(month, 1) - 1) * 30 + (maxi(day, 1) - 1)
	var phase := "上午"
	if hour < 6:
		phase = "深夜"
	elif hour < 8:
		phase = "清晨"
	elif hour < 12:
		phase = "上午"
	elif hour < 17:
		phase = "下午"
	elif hour < 19:
		phase = "傍晚"
	else:
		phase = "夜晚"
	return {
		"date": "%d/%d" % [maxi(month, 1), maxi(day, 1)],
		"weekday": WEEKDAYS[posmod(total, 7)],
		"phase": phase,
	}


## cast 兼容两种写法：
##   老格式 [{name, role, loadout, pos}]（E02-E04 在用）
##   新格式 cast 只列 id，speakers 字典给详情（E01 用它，同一角色跨 beat 复用一份档案）
func _cast_list() -> Array:
	var result: Array = []
	var speakers: Dictionary = _event.get("speakers", {})
	for entry in _event.get("cast", []) as Array:
		if entry is Dictionary:
			var actor := Dictionary(entry)
			if not actor.has("id"):
				actor["id"] = String(actor.get("name", "actor"))
			actor["loadout"] = _bear_loadout(actor)
			result.append(actor)
		elif entry is String:
			var id := String(entry)
			var profile := Dictionary(speakers.get(id, {}))
			if profile.is_empty():
				continue
			profile["id"] = id
			profile["loadout"] = _bear_loadout(profile)
			result.append(profile)
	return result


func _bear_loadout(actor: Dictionary) -> String:
	return String(BEAR_LOADOUT_BY_ACTOR.get(String(actor.get("name", "")), "bear_green_cardigan"))


## 立绘：直接取纸娃娃图集第一帧（down 方向），不引额外依赖。
## cast 为空 = 独处事件，画面上真的没有别人（这正是"没人看着"的视觉表达）。
func _add_actor(actor: Dictionary) -> void:
	var anchor := Node2D.new()
	anchor.name = "Actor_%s" % String(actor.get("id", "actor"))
	_stage_layer.add_child(anchor)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-24, -4), Vector2(24, -4), Vector2(30, 2), Vector2(18, 8), Vector2(-18, 8), Vector2(-30, 2)])
	shadow.color = Color(0.02, 0.03, 0.05, 0.34)
	anchor.add_child(shadow)
	var sprite := Sprite2D.new()
	sprite.texture = _load_texture(DOLL_ATLAS % String(actor.get("loadout", "bear_green_cardigan")))
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 128, 160)
	sprite.centered = false
	sprite.position = Vector2(-64, -144)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anchor.add_child(sprite)
	_actors.append({"data": actor, "anchor": anchor})


## 说话人：放大、压边、提亮。旁听者：缩小、后退、压暗。
## 谁在说话不用任何 UI 提示，看谁被推到了前面就知道。
func _layout_actors(focus_id: String) -> void:
	var size := _view_size()
	for entry in _actors:
		var actor: Dictionary = entry["data"]
		var anchor: Node2D = entry["anchor"]
		if not is_instance_valid(anchor):
			continue
		var side := String(actor.get("pos", "left"))
		var slot := float(SLOT_X.get(side, SLOT_X["left"]))
		var is_focus := String(actor.get("id", "")) == focus_id
		var scale := FOCUS_SCALE if is_focus else IDLE_SCALE
		if focus_id.is_empty():
			# 旁白拍：所有人一起退到背景，画面交给文字
			anchor.modulate = Color(0.72, 0.75, 0.82)
			anchor.scale = Vector2.ONE * IDLE_SCALE
			anchor.position = Vector2(size.x * slot, size.y * GROUND_Y)
			continue
		anchor.scale = Vector2.ONE * scale
		# 非说话人再往画面外让 4%，免得两个人压在一起
		var drift := 0.0 if is_focus else (-0.04 if side == "right" else 0.04)
		anchor.position = Vector2(size.x * (slot + drift), size.y * GROUND_Y)
		anchor.modulate = Color.WHITE if is_focus else Color(0.56, 0.60, 0.70)


# ---------------------------------------------------------------- 分镜

func _next_beat() -> void:
	_beat_index += 1
	if _beat_index >= _beats.size():
		_finish_without_choice()
		return
	var beat := Dictionary(_beats[_beat_index])
	match String(beat.get("type", "say")):
		"say":
			_show_say(beat)
		"interact":
			_show_interact(beat)
		"choice":
			_show_choices(String(beat.get("prompt", "")))
		_:
			_show_narration(String(beat.get("text", "")))


## 说话拍：气泡 + 名字牌 + 立绘聚焦。
func _show_say(beat: Dictionary) -> void:
	_stage = "say"
	_clear_ui()
	var speaker_id := String(beat.get("speaker", ""))
	_layout_actors(speaker_id)
	var text := String(beat.get("text", ""))
	var bubble := _make_bubble(true, minf(1240.0, _view_size().x - 200.0), text, 24)
	var body := _label("", 24, Color("f7f2e6"))
	body.position = Vector2(PAD_X, 26.0)
	body.size = Vector2(bubble.size.x - PAD_X * 2.0, bubble.size.y - 56.0)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_theme_constant_override("line_spacing", 10)
	bubble.add_child(body)
	_typewriter_label = body
	_start_typewriter(text)
	_add_name_plate(bubble, _speaker_profile(speaker_id))
	_add_key_hint(bubble, "点击继续")


## 旁白拍：没有名字、没有立绘聚焦。玩家在看场景，不是在看人。
func _show_narration(text: String) -> void:
	_stage = "narration"
	_clear_ui()
	_layout_actors("")
	var bubble := _make_bubble(false, minf(1240.0, _view_size().x - 200.0), text, 24)
	var body := _label("", 24, Color("efe6d4"))
	body.position = Vector2(PAD_X, 26.0)
	body.size = Vector2(bubble.size.x - PAD_X * 2.0, bubble.size.y - 56.0)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_theme_constant_override("line_spacing", 10)
	bubble.add_child(body)
	_typewriter_label = body
	_start_typewriter(text)
	_add_key_hint(bubble, "点击继续")


## 可交互拍：不推进剧情，等玩家去碰它。
## V5.27 对 E01 的要求是「手册翻章（永久改变）」——所以这必须是个真动作，不是一行文案。
func _show_interact(beat: Dictionary) -> void:
	_stage = "interact"
	_clear_ui()
	var text := String(beat.get("label", "可交互"))
	var hint_text := String(beat.get("hint", "点击查看"))
	var bubble := _make_bubble(false, 480.0, text + "\n" + hint_text, 24)
	bubble.fill_color = Color(0.07, 0.06, 0.09, 0.94)
	var mark := _label("◆", 22, Color("f2c14e"))
	mark.position = Vector2(PAD_X, 24.0)
	mark.size = Vector2(34, 32)
	bubble.add_child(mark)
	var title := _label(text, 24, Color("f7f2e6"), true)
	title.position = Vector2(PAD_X + 32.0, 24.0)
	title.size = Vector2(bubble.size.x - PAD_X * 2.0 - 32.0, 34.0)
	bubble.add_child(title)
	var hint := _label(hint_text, 20, Color("c9bda6"))
	hint.position = Vector2(PAD_X + 32.0, 62.0)
	hint.size = Vector2(bubble.size.x - PAD_X * 2.0 - 32.0, 30.0)
	bubble.add_child(hint)
	_add_key_hint(bubble, "点击翻开")


## 选择拍：三个撕纸片，竖排在画面中偏右（说话的对象在那边）。
func _show_choices(prompt: String) -> void:
	_stage = "choices"
	_stop_typewriter()
	# 犹豫时长从"选项出现在眼前"开始算，不能把读开场白的时间也算进去。
	decision_opened.emit(String(_event.get("id", "")))
	_clear_ui()
	var choices: Array = _event.get("choices", [])
	var size := _view_size()
	var bubble_w := minf(840.0, size.x * 0.52)
	var start_y := size.y * 0.28
	var caption_text := prompt if not prompt.is_empty() else String(_event.get("prompt", ""))
	if not caption_text.is_empty():
		var caption := _label(caption_text, 21, Color("e6d6b4"))
		caption.position = Vector2(size.x * 0.46, start_y - 48.0)
		caption.size = Vector2(720, 32)
		caption.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.05, 0.92))
		caption.add_theme_constant_override("outline_size", 6)
		_ui_layer.add_child(caption)
	for index in mini(choices.size(), 3):
		var choice: Dictionary = choices[index]
		var choice_id := String(choice.get("id", "option_%d" % index))
		var text := String(choice.get("text", ""))
		var lines := _wrapped_lines(text, bubble_w - 76.0, 22)
		var height := maxf(88.0, float(lines) * 34.0 + 40.0)
		var row: Control = TORN_BUBBLE.new()
		row.name = "Choice_%s" % choice_id
		row.size = Vector2(bubble_w, height)
		row.position = Vector2(size.x * 0.46, start_y + float(index) * (height + 16.0))
		row.fill_color = BUBBLE_FILL
		row.outline_color = BUBBLE_LINE
		row.outline_width = 3.0
		row.tail_side = "right"
		row.tail_at = 0.5
		row.tail_length = 26.0
		row.jag = 6.0
		row.shape_seed = 4100 + index
		_ui_layer.add_child(row)
		var label := _label(text, 22, Color("f7f2e6"))
		label.position = Vector2(34, 18)
		label.size = Vector2(bubble_w - 76.0, height - 36.0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("line_spacing", 8)
		row.add_child(label)
		var button := Button.new()
		button.name = "Hit_%s" % choice_id
		button.flat = true
		button.size = Vector2(bubble_w, height)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		var event_id := String(_event.get("id", ""))
		var duration_minutes := int(_event.get("durationMinutes", 45))
		button.mouse_entered.connect(func():
			row.fill_color = BUBBLE_FILL_HOT
			row.queue_redraw()
			choice_hovered.emit(event_id, choice_id))
		button.mouse_exited.connect(func():
			row.fill_color = BUBBLE_FILL
			row.queue_redraw())
		button.pressed.connect(func(): _on_choice_picked(event_id, choice_id, duration_minutes))
		row.add_child(button)


func _on_choice_picked(event_id: String, choice_id: String, duration_minutes: int) -> void:
	_chosen_id = choice_id
	choice_confirmed.emit(event_id, choice_id, duration_minutes)
	_show_outcome(choice_id)


func _show_outcome(choice_id: String) -> void:
	_stage = "outcome"
	_stop_typewriter()
	_clear_ui()
	_layout_actors("")
	var text := _outcome_text(choice_id)
	var width := minf(1180.0, _view_size().x - 200.0)
	# 气泡要同时装下正文和底部那行「你选择了 · X」——按正文算完高度再补一条
	var text_h := _bubble_height(text, width, 23)
	var bubble := _make_bubble_sized(false, width, text_h + 80.0)
	var body := _label("", 23, Color("f5eddc"))
	body.position = Vector2(PAD_X, 26.0)
	body.size = Vector2(bubble.size.x - PAD_X * 2.0, text_h - 62.0)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_theme_constant_override("line_spacing", 10)
	bubble.add_child(body)
	_typewriter_label = body
	_start_typewriter(text)
	var echo := _label("你选择了 · %s" % _choice_text(choice_id), 19, Color("b9ab90"))
	echo.position = Vector2(PAD_X, bubble.size.y - 66.0)
	echo.size = Vector2(bubble.size.x - 300.0, 32.0)
	echo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.add_child(echo)
	_add_memo_note(choice_id)
	_add_key_hint(bubble, "结束")


func _finish_without_choice() -> void:
	outcome_acknowledged.emit(String(_event.get("id", "")), _chosen_id, int(_event.get("durationMinutes", 45)))
	dismiss()


# ---------------------------------------------------------------- 入场拍

## 第一拍 · 入场：黑场 + 事件卡（幕名 / 事件名 / 地点 / 世界时间）。
## 卡片内容全部读事件数据，任何一个字都不写死在脚本里。
func _show_entry() -> void:
	_stage = "entry"
	_stop_typewriter()
	_typewriter_full = ""
	_typewriter_shown = 0
	_clear_ui()
	_entry_age = 0.0
	var size := _view_size()
	_entry_fade = ColorRect.new()
	_entry_fade.name = "EntryFade"
	_entry_fade.color = Color(0.02, 0.03, 0.05, 1.0)
	_entry_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_entry_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_entry_fade)
	_entry_card = Control.new()
	_entry_card.name = "EntryCard"
	_entry_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_card.position = Vector2(140.0, size.y * 0.34)
	_entry_card.modulate.a = 0.0
	_ui_layer.add_child(_entry_card)
	var clock := clock_text()
	var act := _label(String(_event.get("actTitle", "主线事件")), 24, Color("e0b878"))
	act.position = Vector2(0, 0)
	act.size = Vector2(900, 34)
	act.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_entry_card.add_child(act)
	var title := _label(String(_event.get("title", "")), 46, Color("f7ecd6"))
	title.position = Vector2(0, 44)
	title.size = Vector2(1100, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_entry_card.add_child(title)
	var rule := ColorRect.new()
	rule.color = Color(0.72, 0.55, 0.32, 0.65)
	rule.position = Vector2(2, 118)
	rule.size = Vector2(120, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_card.add_child(rule)
	var where := _label("%s · %s" % [String(_event.get("location", "")), clock], 24, Color("c2b399"))
	where.position = Vector2(0, 138)
	where.size = Vector2(1000, 34)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_entry_card.add_child(where)


## 入场卡退场：淡场和卡片一起收走，顶栏在这时候才出来。
func _end_entry() -> void:
	_clear_entry()
	if is_instance_valid(_top_bar):
		_top_bar.show()
	_next_beat()


func _clear_entry() -> void:
	if is_instance_valid(_entry_fade):
		_entry_fade.queue_free()
	if is_instance_valid(_entry_card):
		_entry_card.queue_free()
	_entry_fade = null
	_entry_card = null


# ---------------------------------------------------------------- 手册

func _open_handbook() -> void:
	_stage = "handbook"
	_stop_typewriter()
	_handbook.open()


func _on_handbook_closed(records: Dictionary) -> void:
	handbook_recorded.emit(String(_event.get("id", "")), records)
	_next_beat()


# ---------------------------------------------------------------- 交互

func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
	elif event is InputEventScreenTouch and event.pressed:
		_advance()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_advance()


## 点击继续：正在打字就先把字补满（不催玩家，但也不让他干等）
func _advance() -> void:
	match _stage:
		"closed", "handbook", "choices":
			return
	if _is_typing():
		_finish_typewriter()
		return
	match _stage:
		"entry":
			_end_entry()
		"interact":
			_open_handbook()
		"outcome":
			var duration := int(_event.get("durationMinutes", 45))
			var event_id := String(_event.get("id", ""))
			outcome_acknowledged.emit(event_id, _chosen_id, duration)
			dismiss()
		_:
			_next_beat()


# ---------------------------------------------------------------- 打字机

func _start_typewriter(text: String) -> void:
	_typewriter_full = text
	_typewriter_shown = 0
	if is_instance_valid(_typewriter_label):
		_typewriter_label.text = ""
		_typewriter_timer.start()


func _tick_typewriter() -> void:
	if not is_instance_valid(_typewriter_label):
		_stop_typewriter()
		return
	_typewriter_shown = mini(_typewriter_shown + 2, _typewriter_full.length())
	_typewriter_label.text = _typewriter_full.substr(0, _typewriter_shown)
	if _typewriter_shown >= _typewriter_full.length():
		_stop_typewriter()


func _is_typing() -> bool:
	return _typewriter_shown < _typewriter_full.length()


func _finish_typewriter() -> void:
	_typewriter_shown = _typewriter_full.length()
	if is_instance_valid(_typewriter_label):
		_typewriter_label.text = _typewriter_full
	_stop_typewriter()


func _stop_typewriter() -> void:
	if _typewriter_timer != null:
		_typewriter_timer.stop()


# ---------------------------------------------------------------- 零件

## 对话气泡：黑底白边的撕纸片，尖角指向说话人那一侧。
## 高度跟着文案行数走 —— 一句话的气泡矮，一段话的气泡高，不做固定框。
func _make_bubble(center: bool, width: float, text: String, font_size: int) -> Control:
	return _make_bubble_sized(center, width, _bubble_height(text, width, font_size))


func _make_bubble_sized(center: bool, width: float, height: float) -> Control:
	var size := _view_size()
	var bubble: Control = TORN_BUBBLE.new()
	bubble.name = "Bubble"
	bubble.size = Vector2(width, height)
	bubble.fill_color = BUBBLE_FILL
	bubble.outline_color = BUBBLE_LINE
	bubble.outline_width = 4.0
	bubble.jag = 9.0
	bubble.shape_seed = 7717
	bubble.tail_side = "none" if center else "left"
	bubble.tail_at = 0.34
	bubble.tail_length = 40.0
	bubble.position = Vector2(round((size.x - width) * 0.5), round(size.y - height - 92.0))
	_ui_layer.add_child(bubble)
	return bubble


func _bubble_height(text: String, width: float, font_size: int) -> float:
	if text.is_empty():
		return 128.0
	var lines := _wrapped_lines(text, width - PAD_X * 2.0, font_size)
	# 行高 = 字号 ×1.42（中文字体实际行高）+ line_spacing 12；上下各留 34px 内边距。
	# 估小了正文就会压到下面那行「你选择了」上面去。
	return maxf(128.0, float(lines) * (float(font_size) * 1.42 + 12.0) + 68.0)


## 名字牌：白底黑字的斜切牌，挂在气泡外侧。
## 它的职责是让玩家随时知道"现在是谁在说"——旧版只有一行贴在图上的小字，很容易读丢。
func _add_name_plate(bubble: Control, profile: Dictionary) -> void:
	if profile.is_empty():
		return
	var name := String(profile.get("name", ""))
	var role := String(profile.get("role", ""))
	if name.is_empty():
		return
	var text := "%s　%s" % [name, role] if not role.is_empty() else name
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 58.0
	var plate: Control = TORN_BUBBLE.new()
	plate.name = "NamePlate"
	plate.size = Vector2(width, 52.0)
	plate.position = Vector2(bubble.position.x + 22.0, bubble.position.y - 46.0)
	plate.fill_color = PLATE_FILL
	plate.outline_color = PLATE_LINE
	plate.outline_width = 4.0
	plate.tail_side = "left"
	plate.tail_at = 0.5
	plate.tail_length = 22.0
	plate.jag = 6.0
	plate.shape_seed = 3311
	_ui_layer.add_child(plate)
	var label := _label(text, 21, INK, true)
	label.position = Vector2(28, 11)
	label.size = Vector2(width - 56.0, 30.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(label)


## 记忆便签：右下角浮出的小卡片，金 / 灰两种，颜色即语气，不写数值。
func _add_memo_note(choice_id: String) -> void:
	var note: Dictionary = _memo_note(choice_id)
	if note.is_empty():
		return
	# 便签一露面就回传：玩家这时候已经做完选择、也看过结果了。
	# 记账时机放在「点结束」之前 —— 就算他当场退出游戏，这张便签也已经贴上墙了。
	memo_recorded.emit(String(_event.get("id", "")), _memo_payload(choice_id, note))
	var size := _view_size()
	var card := Panel.new()
	card.name = "MemoNote"
	card.position = Vector2(size.x - 396.0, size.y - 700.0)
	card.size = Vector2(320.0, 146.0)
	var tone := String(note.get("tone", "gold"))
	var fill: Color = NOTE_TONE.get(tone, NOTE_TONE["gold"])
	card.add_theme_stylebox_override("panel", _note_style(fill))
	_ui_layer.add_child(card)
	var caption := _label("心湖记忆墙 · 新便签", 18, Color("5b4326"))
	caption.position = Vector2(20, 16)
	caption.size = Vector2(280, 28)
	card.add_child(caption)
	var body := _label(String(note.get("text", "")), 21, Color("3d2f1d"))
	body.position = Vector2(20, 50)
	body.size = Vector2(280, 80)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	card.add_child(body)
	card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.45).set_delay(0.35)


## 右下角操作提示：那排「F 快进 / X 自动 / LOG」的等价物。
func _add_key_hint(bubble: Control, text: String) -> void:
	var box: Control = TORN_BUBBLE.new()
	box.size = Vector2(116.0, 36.0)
	box.position = Vector2(bubble.size.x - 186.0, bubble.size.y - 52.0)
	box.fill_color = PLATE_FILL
	box.outline_color = PLATE_LINE
	box.outline_width = 2.0
	box.tail_side = "none"
	box.jag = 4.0
	box.shape_seed = 5150
	bubble.add_child(box)
	var key := _label("空格", 16, INK, true)
	key.position = Vector2(12, 7)
	key.size = Vector2(92, 22)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key)
	var hint := _label(text, 16, Color("c4b9a2"))
	hint.position = Vector2(bubble.size.x - 312.0, bubble.size.y - 48.0)
	hint.size = Vector2(114, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bubble.add_child(hint)


func _clear_ui() -> void:
	for child in _ui_layer.get_children():
		child.queue_free()
	_entry_fade = null
	_entry_card = null


func _speaker_profile(speaker_id: String) -> Dictionary:
	var speakers: Dictionary = _event.get("speakers", {})
	if speakers.has(speaker_id):
		var profile := Dictionary(speakers[speaker_id])
		profile["id"] = speaker_id
		return profile
	for value in _cast_list():
		var actor := Dictionary(value)
		if String(actor.get("id", "")) == speaker_id:
			return actor
	return {}


func _outcome_text(choice_id: String) -> String:
	var outcomes: Dictionary = _event.get("outcome", {})
	return String(outcomes.get(choice_id, "你的选择被记录下来了。"))


func _memo_note(choice_id: String) -> Dictionary:
	var notes: Dictionary = _event.get("memoryNote", {})
	return Dictionary(notes.get(choice_id, {}))


## 便签的落盘记录：一次写全，读回时不需要再回查事件数据。
## 事件名 / 月日 / 选项文案 / 结果文案都带上了 —— 记忆墙要能独立成篇。
func _memo_payload(choice_id: String, note: Dictionary) -> Dictionary:
	return {
		"eventId": String(_event.get("id", "")),
		"eventTitle": String(_event.get("title", "")),
		"actTitle": String(_event.get("actTitle", "")),
		"month": int(_event.get("month", 1)),
		"day": int(_event.get("day", 1)),
		"choiceId": choice_id,
		"choiceText": _choice_text(choice_id),
		"text": String(note.get("text", "")),
		"tone": String(note.get("tone", "gold")),
		"outcome": _outcome_text(choice_id),
		"npc": _lead_actor_name(),
	}


## 便签挂靠的角色**显示名**（cast 第一位）。记忆墙拿它反查好感档、在便签角落贴一枚色点。
## 只存显示名不用 id：NPC 有两套 id 空间（npcs.json 的 wange / MonthlyLife 的 wang_ge），
## 名字是唯一两边都成立的 join key。独处事件 cast 为空 → 空串 → 墙上就不贴点。
func _lead_actor_name() -> String:
	for value in _cast_list():
		var actor := Dictionary(value)
		var who := String(actor.get("name", ""))
		if not who.is_empty():
			return who
	return ""


func _choice_text(choice_id: String) -> String:
	for value in _event.get("choices", []) as Array:
		var choice := Dictionary(value)
		if String(choice.get("id", "")) == choice_id:
			return String(choice.get("text", ""))
	return choice_id


## 估算文字在给定宽度下占几行。给气泡定高用，不依赖运行时字体度量 ——
## headless 下的 Y 轴度量是 GUI 的两倍，拿它算高度会全错（判据 DisplayServer.get_name()）。
func _wrapped_lines(text: String, width: float, font_size: int) -> int:
	if width <= 1.0:
		return 1
	var lines := 0
	# 必须按 \n 分段算 —— 整段丢给 get_string_size 会把换行当成一个很宽的单行，
	# 于是气泡高度算矮、正文被底边切掉。
	for paragraph in text.split("\n"):
		if paragraph.is_empty():
			lines += 1
			continue
		var advance := FONT.get_string_size(paragraph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		lines += maxi(1, int(ceil(advance.x / width)))
	return maxi(1, lines)


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1920, 1080)
	return vp.get_visible_rect().size


func _bold(font: Font, weight: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_embolden = weight
	return variation


func _load_texture(path: String) -> Texture2D:
	var imported := load(path) as Texture2D
	if imported != null:
		return imported
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _label(value: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(320, 40)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _bold(FONT, 0.6) if bold else FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _note_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.30, 0.24, 0.16, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style
