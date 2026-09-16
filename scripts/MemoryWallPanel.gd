extends CanvasLayer
## 心湖记忆墙 —— 把一路攒下的「记忆便签」贴成一墙。
##
## 这是 V5.27 里「有人记得我」那条线的承载体：
##   金便签 = 你自己觉得站得住的（纸色偏暖）
##   灰便签 = 你心里还留着疙瘩的（纸色偏冷）
## 颜色即语气，**永不出现任何数值** —— 和剧情面板同一条红线。
##
## 数据源：user://workplace_town_memos.jsonl（WorkplaceTown 在结果拍逐条追加）
## 老存档回填：更早的版本只把 choiceId 写进了 workplace_town_events.jsonl，
##   没有便签文案。这里拿 eventId + choiceId 回查事件数据里的 memoryNote 补一次，
##   补完写回 memos.jsonl —— 一次性迁移，之后不再依赖老文件。
##
## 美术图到位后只改 WALL_TEXTURE 常量，布局不动。

signal wall_closed()

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

const MEMO_PATH := "user://workplace_town_memos.jsonl"
const LEGACY_PATH := "user://workplace_town_events.jsonl"

const PAGE_W := 1348.0
const PAGE_H := 848.0
const PAD := 64.0
## 竖直滚动条是**占位**的：它一出现，内容区就少 10px。
## 三列宽度必须按「减掉滚动条之后」的宽度去分，否则最右一列的边框会被裁掉。
const SCROLLBAR := 10.0
const CONTENT_W := PAGE_W - PAD * 2.0 - SCROLLBAR
const STRIP_W := PAGE_W - PAD * 2.0
const COLS := 3
const GAP_X := 41.0
const NOTE_W := (CONTENT_W - GAP_X * 2.0) / COLS
## 卡高 216 + 行距 38 = 一屏刚好两行（470）—— 滚动区高度必须取整行，
## 否则第二行会被视口拦腰切断，纸片看着像坏了。
const NOTE_H := 216.0
const GAP_Y := 38.0

const SCROLL_Y := 152.0
const SCROLL_H := NOTE_H * 2.0 + GAP_Y
const STRIP_Y := 634.0
const STRIP_H := 132.0
## 卡面上沿那条胶带是画在卡框**外面**的（y = -11），滚动区必须留出内边距，
## 否则滚到顶/底时最外面那一行的胶带会被视口切掉，纸片就"没贴住"。
const WALL_PAD := 14.0
## 选中的那张"被从墙上拿起来"的抬升量。
const LIFT := 6.0

const PAPER := Color("efe4cf")
const PAPER_DARK := Color("e2d4b8")
const INK := Color("352b1e")
const INK_SOFT := Color("6d5c46")
const NOTE_LINE := Color(0.32, 0.27, 0.19, 0.9)

## 金 / 灰两副纸。纸色就是语气，卡面上不再贴任何标签。
const TONE := {
	"gold": {"paper": Color("f4dfa4"), "line": Color("b08a37")},
	"gray": {"paper": Color("d5d2ca"), "line": Color("6e6f74")},
}
## 手贴的痕迹：固定角度轮换（不随机，免得每次开墙都在抖）。
const TILT := [-2.1, 1.5, -0.9, 2.3, -1.4, 0.8]

var _root: Control
var _scroll: ScrollContainer
var _wall: Control
var _empty_label: Label
var _count_label: Label
var _detail_title: Label
var _detail_body: Label

var _notes: Array = []
var _cards: Array = []
var _selected := -1
var _catalog: Array = []


func _ready() -> void:
	# 压在剧情面板(150)与手册(160)之上：从小镇 HUD 打开时不能被别的层遮住。
	layer = 170
	_root = Control.new()
	_root.name = "MemoryWallOverlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_build_shell()
	_root.hide()


# ---------------------------------------------------------------- 对外

## records 传空数组就从 user:// 读；显式给数据是为了验收脚本能灌样例。
func open(records: Array = []) -> void:
	show_records(records if not records.is_empty() else _load_records())


## 直接铺给定的一组记录，不碰磁盘。空数组 = 空墙（验收脚本要看空状态）。
func show_records(records: Array) -> void:
	_notes = records
	_selected = -1
	_cards.clear()
	_rebuild()
	_root.show()


func close() -> void:
	if _root == null or not _root.visible:
		return
	_root.hide()
	wall_closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


func note_count() -> int:
	return _notes.size()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 骨架

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var page := Panel.new()
	page.name = "Page"
	page.size = Vector2(PAGE_W, PAGE_H)
	page.add_theme_stylebox_override("panel", _paper_style())
	_root.add_child(page)
	var size := _view_size()
	page.position = Vector2(round((size.x - PAGE_W) * 0.5), round((size.y - PAGE_H) * 0.5))

	var title := _label("心湖记忆墙", 42, INK, true, 700.0)
	title.position = Vector2(PAD, 38)
	title.size = Vector2(700, 58)
	page.add_child(title)

	# 语气说明写在标题下面 —— 玩家第一次进来得知道冷暖两种纸是干什么的。
	var sub := _label("金便签，是你自己觉得站得住的；灰便签，是你心里还留着疙瘩的。", 20, INK_SOFT, false, 900.0)
	sub.position = Vector2(PAD, 100)
	sub.size = Vector2(900, 30)
	page.add_child(sub)

	_count_label = _label("", 22, INK, false, 460.0)
	_count_label.position = Vector2(PAGE_W - PAD - 460.0, 52)
	_count_label.size = Vector2(460, 32)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page.add_child(_count_label)

	_scroll = ScrollContainer.new()
	_scroll.name = "WallScroll"
	_scroll.position = Vector2(PAD, SCROLL_Y)
	_scroll.size = Vector2(CONTENT_W, SCROLL_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_theme_constant_override("scrollbar_width", 10)
	page.add_child(_scroll)

	_wall = Control.new()
	_wall.name = "Wall"
	_wall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_wall)

	_empty_label = _label("墙上还是空的。\n\n做完第一个选择，第一张便签就会贴上来。", 26, INK_SOFT, false, CONTENT_W)
	_empty_label.position = Vector2(0, 150)
	_empty_label.size = Vector2(CONTENT_W, 110)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.hide()
	_wall.add_child(_empty_label)

	var strip := Panel.new()
	strip.name = "DetailStrip"
	strip.position = Vector2(PAD, STRIP_Y)
	strip.size = Vector2(STRIP_W, STRIP_H)
	strip.add_theme_stylebox_override("panel", _strip_style())
	page.add_child(strip)

	_detail_title = _label("", 18, INK_SOFT, false, STRIP_W - 48.0)
	_detail_title.position = Vector2(24, 14)
	_detail_title.size = Vector2(STRIP_W - 48.0, 26)
	strip.add_child(_detail_title)

	# 回看那一刻：当时的选项 + 当时的结果。
	# ⚠ Label **默认不裁剪**：不设 max_lines_visible 的话，长结果会直接画出条外、
	# 压到下方页面空白上（视觉上像鬼影）。条高只够三行，超出用省略号收。
	_detail_body = _label("", 19, INK, false, STRIP_W - 48.0)
	_detail_body.max_lines_visible = 3
	_detail_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_body.position = Vector2(24, 44)
	_detail_body.size = Vector2(STRIP_W - 48.0, 84)
	_detail_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	strip.add_child(_detail_body)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "合上记忆"
	close_button.size = Vector2(200, 56)
	close_button.position = Vector2(PAGE_W - PAD - 200.0, PAGE_H - 74.0)
	_style_close(close_button)
	close_button.pressed.connect(close)
	page.add_child(close_button)


# ---------------------------------------------------------------- 铺墙

func _rebuild() -> void:
	for child in _wall.get_children():
		if child == _empty_label:
			continue
		_wall.remove_child(child)
		child.queue_free()
	var rows := int(ceil(float(_notes.size()) / float(COLS)))
	# 空墙也要留出高度，否则 _empty_label 的坐标会被 ScrollContainer 压掉。
	_wall.custom_minimum_size = Vector2(
		CONTENT_W,
		maxf(SCROLL_H, WALL_PAD * 2.0 + float(rows) * NOTE_H + maxf(0.0, float(rows - 1)) * GAP_Y)
	)
	_update_count()
	if _notes.is_empty():
		_empty_label.show()
		# 详情条这时候不写"还没有便签"——中间那句已经说过了，重复等于噪音。
		# 改成回答玩家真正会问的那个问题：这东西是从哪来的。
		_detail_title.text = "便签从哪来"
		_detail_body.text = "每次主线事件落幕，结果拍上浮出的那张小卡片会被贴到这儿，按时间从旧到新。同一件事重来一次，会盖掉同名的那张。"
		return
	_empty_label.hide()
	for index in _notes.size():
		_build_note(index, Dictionary(_notes[index]))
	# 默认选中最后一张：玩家最想看的通常是"刚贴上去的那张"。
	_select(_notes.size() - 1)
	# 顺手把它滚进视野 —— 否则高亮在屏幕外，下面的详情条就对不上人。
	_snap_to_latest()


## 滚到墙尾（最新那张）。
## ⚠ 必须等两帧：ScrollContainer 的 sort_children 是**延后**跑的，本帧它的可滚范围
## 还是 0，这时候设 scroll_vertical 会被 Range 直接夹回 0 —— 表现就是"滚不动"。
## 用 ensure_control_visible() 同理不稳：它也要先有内容高度才算得出目标位置。
func _snap_to_latest() -> void:
	if _cards.is_empty():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if _cards.is_empty():
		return
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _build_note(index: int, memo: Dictionary) -> void:
	var card := Button.new()
	card.name = "Note%d" % index
	card.position = _base_position(index)
	card.size = Vector2(NOTE_W, NOTE_H)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(_select.bind(index))
	# 手贴的痕迹：绕中心转一个小角度。父层不裁剪，所以角会微微出框，更像纸。
	card.pivot_offset = card.size * 0.5
	card.rotation = deg_to_rad(TILT[index % TILT.size()])
	_wall.add_child(card)
	_cards.append(card)
	_refresh_card(index)

	# 胶带：卡面上沿压的一小条，贴纸感的全部来源。
	var tape := ColorRect.new()
	tape.color = Color(1, 1, 1, 0.24)
	tape.position = Vector2(NOTE_W * 0.5 - 54.0, -11.0)
	tape.size = Vector2(108, 24)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tape)

	var meta := _label("%s · %s" % [_date_text(memo), String(memo.get("eventTitle", ""))], 18, INK_SOFT, false, NOTE_W - 56.0)
	meta.position = Vector2(28, 26)
	meta.size = Vector2(NOTE_W - 56.0, 26)
	card.add_child(meta)

	# 便签正文按 25px 排：一张卡内宽 320，最长的一条是 12 个汉字（300px），
	# 27px 会把它挤到第二行只剩一个「还」字。
	var body := _label(String(memo.get("text", "")), 25, INK, true, NOTE_W - 56.0)
	body.position = Vector2(28, 74)
	body.size = Vector2(NOTE_W - 56.0, 96)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	card.add_child(body)

	# 回填来的便签标一下出处：玩家能看出这张是从老存档里救回来的。
	if bool(memo.get("rescued", false)):
		var rescued := _label("· 从旧记录里找回", 15, INK_SOFT, false, 220.0)
		rescued.position = Vector2(28, NOTE_H - 40.0)
		rescued.size = Vector2(220, 24)
		card.add_child(rescued)


func _refresh_card(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card: Button = _cards[index]
	if card == null or not is_instance_valid(card):
		return
	var palette: Dictionary = TONE.get(String(Dictionary(_notes[index]).get("tone", "gold")), TONE["gold"])
	var paper := Color(palette["paper"])
	var line := Color(palette["line"])
	# 选中 = 深色粗边框 + 整张往上抬 6px：一墙纸里最像「这张被拿起来了」的提示。
	var on := index == _selected
	card.position = _base_position(index) + (Vector2(0, -LIFT) if on else Vector2.ZERO)
	card.add_theme_stylebox_override("normal", _note_box(paper, 5.0 if on else 2.0, line if on else NOTE_LINE))
	card.add_theme_stylebox_override("hover", _note_box(paper.lightened(0.07), 3.0, line))
	card.add_theme_stylebox_override("pressed", _note_box(paper.darkened(0.05), 5.0, line))


## 卡片在网格里的固定落点。选中抬升是叠在它上面的偏移，不写进这里。
func _base_position(index: int) -> Vector2:
	return Vector2(
		float(index % COLS) * (NOTE_W + GAP_X),
		WALL_PAD + float(index / COLS) * (NOTE_H + GAP_Y)
	)


func _select(index: int) -> void:
	if index < 0 or index >= _notes.size():
		return
	var previous := _selected
	_selected = index
	_refresh_card(previous)
	_refresh_card(index)
	var memo := Dictionary(_notes[index])
	var tone_name := "灰便签" if String(memo.get("tone", "gold")) == "gray" else "金便签"
	_detail_title.text = "%s · %s · %s" % [_date_text(memo), String(memo.get("eventTitle", "")), tone_name]
	var choice := String(memo.get("choiceText", ""))
	# 事件数据里的结果文案常用 "\n\n" 分段（剧情面板上是两段话），
	# 搬进这一条窄条里要把空行收掉，不然三行额度全被吃掉。
	var outcome := String(memo.get("outcome", "")).replace("\n\n", "\n").strip_edges()
	var head := ""
	if not choice.is_empty():
		head = "你当时选了「%s」。" % choice
	_detail_body.text = ("%s\n%s" % [head, outcome]).strip_edges()


func _update_count() -> void:
	var gold := 0
	for value in _notes:
		if String(Dictionary(value).get("tone", "gold")) != "gray":
			gold += 1
	var gray := _notes.size() - gold
	if _notes.is_empty():
		_count_label.text = ""
		return
	_count_label.text = "共 %d 张便签　·　金 %d　·　灰 %d" % [_notes.size(), gold, gray]


# ---------------------------------------------------------------- 数据

## 两个路径都做成参数（默认真实存档）：验收探针可以指着临时文件跑完整的
## 「去重 + 回填 + 写回」链路，而不用去动玩家的真实存档。
func _load_records(memo_path: String = MEMO_PATH, legacy_path: String = LEGACY_PATH) -> Array:
	var by_event: Dictionary = {}
	var order: Array = []
	for line in _read_lines(memo_path):
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var row := Dictionary(parsed)
		var event_id := String(row.get("eventId", ""))
		if event_id.is_empty():
			continue
		if not by_event.has(event_id):
			order.append(event_id)
		# 同一事件重玩以最后一次为准：后写的覆盖先写的。
		by_event[event_id] = row
	# 老存档回填（一次性）。
	var rescued: Array = []
	for entry in _legacy_choices(legacy_path):
		var event_id := String(entry.get("eventId", ""))
		if event_id.is_empty() or by_event.has(event_id):
			continue
		var memo := _memo_from_catalog(event_id, String(entry.get("choiceId", "")), int(entry.get("worldMinute", 0)))
		if memo.is_empty():
			continue
		order.append(event_id)
		by_event[event_id] = memo
		rescued.append(memo)
	if not rescued.is_empty():
		_append_lines(memo_path, rescued)
	var records: Array = []
	for event_id in order:
		records.append(by_event[event_id])
	records.sort_custom(func(a, b): return int(Dictionary(a).get("worldMinute", 0)) < int(Dictionary(b).get("worldMinute", 0)))
	return records


## 老记录只有 choiceId，没有便签文案 —— 这里把文案 join 回来。
func _legacy_choices(path: String = LEGACY_PATH) -> Array:
	var by_event: Dictionary = {}
	var order: Array = []
	for line in _read_lines(path):
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var row := Dictionary(parsed)
		var event_id := String(row.get("eventId", ""))
		if event_id.is_empty() or String(row.get("choiceId", "")).is_empty():
			continue
		if not by_event.has(event_id):
			order.append(event_id)
		by_event[event_id] = row
	var out: Array = []
	for event_id in order:
		out.append(by_event[event_id])
	return out


func _memo_from_catalog(event_id: String, choice_id: String, world_minute: int) -> Dictionary:
	var event := _catalog_event(event_id)
	if event.is_empty():
		return {}
	var note := Dictionary((event.get("memoryNote", {}) as Dictionary).get(choice_id, {}))
	if note.is_empty():
		return {}
	var choice_text := ""
	for value in event.get("choices", []) as Array:
		var choice := Dictionary(value)
		if String(choice.get("id", "")) == choice_id:
			choice_text = String(choice.get("text", ""))
			break
	return {
		"eventId": event_id,
		"eventTitle": String(event.get("title", "")),
		"actTitle": String(event.get("actTitle", "")),
		"month": int(event.get("month", 1)),
		"day": int(event.get("day", 1)),
		"choiceId": choice_id,
		"choiceText": choice_text,
		"text": String(note.get("text", "")),
		"tone": String(note.get("tone", "gold")),
		"outcome": String((event.get("outcome", {}) as Dictionary).get(choice_id, "")),
		"worldMinute": world_minute,
		"rescued": true,
	}


## 事件目录只以 WorldClock 的 MAIN_EVENTS 为准 —— 这里不复制一份数值。
## 用 get_script_constant_map() 而不是 autoload 单例：面板可能在任何时机被 new 出来。
func _catalog_event(event_id: String) -> Dictionary:
	if _catalog.is_empty():
		var script := load("res://scripts/WorldClock.gd")
		if script == null:
			return {}
		_catalog = script.get_script_constant_map().get("MAIN_EVENTS", []) as Array
	for value in _catalog:
		var event := Dictionary(value)
		if String(event.get("id", "")) == event_id:
			return event
	return {}


func _read_lines(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var lines: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if not line.is_empty():
			lines.append(line)
	file.close()
	return lines


func _append_lines(path: String, rows: Array) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	for row in rows:
		file.store_line(JSON.stringify(row))
	file.close()


func _date_text(memo: Dictionary) -> String:
	return "第 %d 月 %d 日" % [int(memo.get("month", 1)), int(memo.get("day", 1))]


# ---------------------------------------------------------------- 样式

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


## wrap_width 必须在创建时就给对：autowrap 的最小高度按当时的 size.x 算，
## 先给 320 再被容器拉到 900 的话，高度会按 320 算，正文被底边切掉。
func _label(value: String, font_size: int, color: Color, bold: bool = false, wrap_width: float = 320.0) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(wrap_width, 40)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _bold(FONT, 0.6) if bold else FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color(0.28, 0.22, 0.15, 0.85)
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0, 9)
	return style


func _strip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER_DARK
	style.border_color = Color(0.32, 0.25, 0.17, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style


func _note_box(fill: Color, border: float, line: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(int(border))
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.30)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _style_close(button: Button) -> void:
	button.add_theme_font_override("font", _bold(FONT, 0.5))
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("171208"))
	button.add_theme_stylebox_override("normal", _close_box(PAPER_DARK))
	button.add_theme_stylebox_override("hover", _close_box(Color("d6c5a3")))
	button.add_theme_stylebox_override("pressed", _close_box(Color("c9b795")))


func _close_box(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.32, 0.25, 0.17, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	return style
