extends CanvasLayer
## 消息匣 —— NPC 主动消息的收件箱（机制文档 §2「有人记得我」+ V5.27 §11.8）。
##
## 「有人记得我」这条线，靠的是**在不该有人找你的时候，有人找了你**：
## 低生命时的一句关心、旧承诺被重提、幕末的一句复盘邀约。
## 展示红线（同记忆墙）：**永不出现数值** —— 没有好感分数、没有等级数字、
## 没有「第几次」。时间只写「第 N 月」，类别只写人话词（关心 / 旧事 / 邀约 / 近了）。
##
## 数据源只有一处：MonthlyLife.messages（跨月时由 NpcMessageSystem 生成）。
## 本面板只读不写，标已读由 MonthlyLife.mark_messages_read() 负责。

signal inbox_closed()

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

## 设计分辨率 1920×1080（窗口 1280×720 会缩 0.667），坐标按设计空间写。
const PAGE_W := 920.0
const PAGE_H := 720.0
const PAGE_X := (1920.0 - PAGE_W) * 0.5
const PAGE_Y := (1080.0 - PAGE_H) * 0.5

const PAD := 40.0
const SCROLLBAR := 10.0
const CONTENT_W := PAGE_W - PAD * 2.0 - SCROLLBAR
const SCROLL_Y := 132.0
const SCROLL_H := PAGE_H - SCROLL_Y - 76.0

const PAPER := Color("efe4cf")
const PAPER_DARK := Color("e2d4b8")
const INK := Color("352b1e")
const INK_SOFT := Color("6d5c46")
const LINE := Color(0.32, 0.27, 0.19, 0.55)

## 四类触发的人话标签 + 左侧色条。词要短，长了对不齐会挤掉正文。
const KIND_LABEL := {
	"state": "关心",
	"memory": "旧事",
	"story": "邀约",
	"relation": "近了",
}
const KIND_COLOR := {
	"state": Color("c2704f"),
	"memory": Color("b3892f"),
	"story": Color("4a7f74"),
	"relation": Color("6a6494"),
}

var _life
var _root: Control
var _list: VBoxContainer
var _scroll: ScrollContainer
var _empty_label: Label
var _count_label: Label


func setup(life) -> void:
	_life = life


func _ready() -> void:
	layer = 175
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_build_shell()
	_root.hide()


func _build_shell() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.06, 0.05, 0.04, 0.62)
	# 点遮罩空白处关闭：和记忆墙一致，别让玩家去找右上角那个小叉。
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	_root.add_child(shade)

	# ⚠ 用 Panel 不用 PanelContainer：容器会把**所有**子节点重排到同一块矩形
	# （标题/分隔线/滚动区/关闭钮会全叠在一起）。本页是绝对坐标手工布局。
	# 卡片内部另说 —— 那里是「一个 HBox 撑满一张纸」，PanelContainer 正合适。
	var page := Panel.new()
	page.position = Vector2(PAGE_X, PAGE_Y)
	page.size = Vector2(PAGE_W, PAGE_H)
	page.add_theme_stylebox_override("panel", _page_style())
	_root.add_child(page)

	var title := _label("消息匣", 32, INK)
	title.position = Vector2(PAD, 26)
	title.size = Vector2(CONTENT_W, 42)
	page.add_child(title)

	_count_label = _label("", 17, INK_SOFT)
	_count_label.position = Vector2(PAD, 74)
	_count_label.size = Vector2(CONTENT_W, 26)
	page.add_child(_count_label)

	var divider := ColorRect.new()
	divider.color = LINE
	divider.position = Vector2(PAD, 112)
	divider.size = Vector2(CONTENT_W, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(PAD, SCROLL_Y)
	_scroll.size = Vector2(CONTENT_W + SCROLLBAR, SCROLL_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.x = CONTENT_W
	_list.add_theme_constant_override("separation", 14)
	_scroll.add_child(_list)

	_empty_label = _label("", 20, INK_SOFT)
	_empty_label.position = Vector2(PAD, SCROLL_Y + 24.0)
	_empty_label.size = Vector2(CONTENT_W, 120)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.hide()
	page.add_child(_empty_label)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.position = Vector2(PAGE_W - PAD - 108.0, PAGE_H - 60.0)
	close_button.size = Vector2(108, 40)
	close_button.add_theme_font_override("font", FONT)
	close_button.add_theme_font_size_override("font_size", 19)
	_style_close(close_button)
	close_button.pressed.connect(close)
	page.add_child(close_button)


## 打开并铺当前消息。标已读（红点清零）由调用方在打开时做。
func open() -> void:
	show_messages(_life.messages if _life != null else [])


## 直接铺给定消息（探针可直测，不依赖 MonthlyLife 实例）。
func show_messages(records: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	# 新的在上：最后收到的在最前面。
	var ordered := records.duplicate()
	ordered.reverse()
	var unread := 0
	for record in ordered:
		if not bool((record as Dictionary).get("read", false)):
			unread += 1
		_list.add_child(_build_message_card(record))
	var total := ordered.size()
	if total == 0:
		_empty_label.text = "还没有人找你说话。\n等你在这个地方待久了，会有人主动想起你的。"
		_empty_label.show()
		_count_label.text = ""
	else:
		_empty_label.hide()
		_count_label.text = "共 %d 条 · 未读 %d 条" % [total, unread]
	_scroll.scroll_vertical = 0
	_root.show()


func close() -> void:
	if _root == null or not _root.visible:
		return
	_root.hide()
	inbox_closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


func _build_message_card(msg: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CONTENT_W, 0)
	card.add_theme_stylebox_override("panel", _card_style(bool(msg.get("read", false))))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	# 左侧色条：类别的颜色。宽 6px，靠最小尺寸撑住，不吃正文宽度。
	var bar := ColorRect.new()
	bar.color = KIND_COLOR.get(String(msg.get("kind", "")), INK_SOFT)
	bar.custom_minimum_size = Vector2(6, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	row.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)

	var who := _label(String(msg.get("npc_name", "")), 23, INK)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)

	if not bool(msg.get("read", false)):
		var dot := _label("●", 16, Color("c2704f"))
		head.add_child(dot)

	var kind := _label(KIND_LABEL.get(String(msg.get("kind", "")), ""), 17,
		KIND_COLOR.get(String(msg.get("kind", "")), INK_SOFT))
	head.add_child(kind)

	var when := _label("第 %d 月" % int(msg.get("month", 1)), 17, INK_SOFT)
	head.add_child(when)

	var text := _label(String(msg.get("text", "")), 20, Color("40341f"))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = CONTENT_W - 60.0
	body.add_child(text)

	return card


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _page_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color("8a6f4a")
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	return style


## 未读的卡片纸色更亮一点，读过的压暗——一眼能分新旧。
func _card_style(read: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER_DARK if read else Color("f7eeda")
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _style_close(button: Button) -> void:
	button.add_theme_color_override("font_color", INK)
	button.add_theme_stylebox_override("normal", _close_box(PAPER_DARK))
	button.add_theme_stylebox_override("hover", _close_box(Color("d6c5a3")))


func _close_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("8a6f4a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style
