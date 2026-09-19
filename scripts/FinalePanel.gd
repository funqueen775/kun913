extends CanvasLayer
## 终局演出（Batch 5 第 3 轮 · 6E）。
##
## M6-E24（第 48 月 · 传承与新局终局答辩）结算后，由 WorkplaceTown 触发。
## 三块内容：
##   ① 六幕回放条 —— 呼应你走过的 48 个月（纯幕标题，不出现月份数字）。
##   ② 四只熊告别卡 —— 按各自好感档取不同台词 + 档色徽章（零分数 / 零等级数字）。
##   ③ 底部「查看我的职业报告」—— 复用 ReportPanel.open()，把终局交棒给服务端报告。
##
## 人格卡徽章：终局顶部那枚「四熊档色徽章条」本身即你的职场人格侧写
##   （四位同仁眼中的你），不碰后端报告、不显示任何数值。
##
## 红线（与记忆墙 / NPC 消息同源）：好感分数、等级数字、测评结论一概不出现；
## 档位只翻成人话（RELATION_STAGE_TEXT）与色点（TIER_DOT）。

signal finale_closed

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const FAREWELL_PATH := "res://data/story/finale_farewell.json"
const REPORT_PANEL := preload("res://scripts/ReportPanel.gd")

const COLOR_DIM := Color(0.04, 0.06, 0.05, 0.66)
const COLOR_WOOD := Color("54321f")
const COLOR_BORDER := Color("d49a4c")
const COLOR_PAPER := Color("f5ecd7")
const COLOR_INK := Color("4a3a20")
const COLOR_SUB := Color("7a6547")
const COLOR_TITLE := Color("ffe5a8")
const COLOR_ACCENT := Color("ef9f27")

## 档色徽章（与记忆墙 RELATION_DOT 同源：Lv1-2 蓝 / Lv3 黄 / Lv4-5 金）。
## ⚠ 只管关系档；绝不等同于任何分数。
const TIER_DOT := {
	1: Color("6f9ec4"), 2: Color("6f9ec4"),
	3: Color("d9b441"), 4: Color("b08a37"), 5: Color("b08a37"),
}
const DOT := 18.0

var _bears: Array = []          # relation_overview() 输出：[{id,name,level,stage,pips}]
var _farewell: Dictionary = {}   # npc_id -> 实际渲染的告别台词（供探针断言）
var _badge: Dictionary = {}      # npc_id -> 档色（Color，供探针断言）
var _replay_titles: Array = []   # 六幕标题（供探针断言）
var _replay_head: String = "你走过的六幕"  # 回放条小标题（数据里给了就用数据的）
var _on_view_report: Callable = Callable()

var _panel: Panel
var _content: VBoxContainer
var _scroll: ScrollContainer
var _replay_strip: HBoxContainer  # 供探针断言「不横向溢出」
var _report_btn: Button


func _ready() -> void:
	layer = 210
	visible = false
	_build_static()


## bears = MonthlyLife.relation_overview() 的返回值；on_view_report 留空则默认开报告面板。
func setup(bears: Array, on_view_report: Callable = Callable()) -> void:
	_bears = bears
	_on_view_report = on_view_report
	_load_farewell()
	_build_content()
	visible = true


# ------------------------------------------------------------------ 静态骨架

func _build_static() -> void:
	var dim := ColorRect.new()
	dim.color = COLOR_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.position = Vector2(180, 56)
	# 高度留够：内容高约 710，滚动区 = 高 - 220；压到 948 时会顶破 → 右缘挂一条多余滚动条。
	_panel.size = Vector2(1560, 996)
	_panel.add_theme_stylebox_override("panel", _style(COLOR_PAPER, COLOR_WOOD, 12, 7))
	add_child(_panel)

	var title := _label("四 十 八 个 月 ， 到 此 一 程", 34, COLOR_INK)
	title.position = Vector2(40, 26)
	title.size = Vector2(900, 48)
	_panel.add_child(title)

	var sub := _label("六幕剧情都走完了。有些熊，你会一直记得。", 17, COLOR_SUB)
	sub.position = Vector2(40, 78)
	sub.size = Vector2(900, 28)
	_panel.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 120)
	scroll.size = Vector2(_panel.size.x - 56, _panel.size.y - 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_scroll = scroll

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.custom_minimum_size.x = scroll.size.x - 24
	_content.add_theme_constant_override("separation", 14)
	scroll.add_child(_content)

	_report_btn = _button("查看我的职业报告")
	_report_btn.position = Vector2(_panel.size.x - 340, _panel.size.y - 78)
	_report_btn.size = Vector2(300, 52)
	_report_btn.add_theme_stylebox_override("normal", _style(Color("e8dcc0"), COLOR_BORDER, 8, 2))
	_report_btn.add_theme_stylebox_override("hover", _style(Color("f0e6cf"), COLOR_ACCENT, 8, 2))
	_report_btn.add_theme_stylebox_override("pressed", _style(Color("ded0ad"), COLOR_ACCENT, 8, 2))
	_report_btn.pressed.connect(_on_report_pressed)
	_panel.add_child(_report_btn)


# ------------------------------------------------------------------ 内容构建

func _load_farewell() -> void:
	_farewell = {}
	_badge = {}
	_replay_titles = []
	var f := FileAccess.open(FAREWELL_PATH, FileAccess.READ)
	if f == null:
		push_warning("FinalePanel：找不到 %s" % FAREWELL_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var cfg: Dictionary = parsed
	_replay_titles = Array(cfg.get("acts", []))
	_replay_head = String(cfg.get("replay_title", _replay_head))
	var bears_cfg: Dictionary = cfg.get("bears", {})
	for row in _bears:
		var d: Dictionary = row
		var npc_id := String(d.get("id", ""))
		var level := int(d.get("level", 1))
		var bc: Dictionary = bears_cfg.get(npc_id, {})
		var tier_key := "lv_low" if level <= 2 else ("lv_high" if level >= 5 else "lv_mid")
		_farewell[npc_id] = String(bc.get(tier_key, "一路顺风。"))
		_badge[npc_id] = TIER_DOT.get(level, TIER_DOT[1])


func _build_content() -> void:
	_clear(_content)
	_build_replay()
	_build_badge_row()
	_build_bear_cards()


## ① 六幕回放条：六段幕标题，纯叙事，不出现月份数字。
## ⚠ 段宽必须按可用宽度反算：写死 238 会凑出 6×238+5×14=1498 > 内容宽 1480 →
##   第六幕被右边缘裁掉，而纯数据断言查不出来（所以探针额外断言「不溢出」）。
func _build_replay() -> void:
	var head := _label(_replay_head, 20, COLOR_INK)
	_content.add_child(head)
	_replay_strip = HBoxContainer.new()
	_replay_strip.add_theme_constant_override("separation", 14)
	var count: int = maxi(_replay_titles.size(), 1)
	var seg_w: int = int(floor((_content.custom_minimum_size.x - 14.0 * float(count - 1)) / float(count)))
	for t in _replay_titles:
		var seg := Panel.new()
		seg.custom_minimum_size = Vector2(seg_w, 64)
		seg.add_theme_stylebox_override("panel", _style(Color("ece0c6"), COLOR_BORDER, 6, 2))
		var lab := _label(String(t), 15, COLOR_INK)
		# 用 FULL_RECT 预设让文字填满段格再双向居中；别再手动 position+size，
		# 那样会先按 CENTER 锚点算偏移、矩形对不上，文字会被上/下裁掉。
		lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seg.add_child(lab)
		_replay_strip.add_child(seg)
	_content.add_child(_replay_strip)


## ② 人格卡徽章条：四枚档色点 + 关系档人话，即「四位同仁眼中的你」。
func _build_badge_row() -> void:
	var head := _label("你的职场人格侧写 · 四位同仁眼中的你", 20, COLOR_INK)
	_content.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	for d in _bears:
		var dd: Dictionary = d
		var npc_id := String(dd.get("id", ""))
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(DOT, DOT)
		dot.size = Vector2(DOT, DOT)
		dot.color = _badge.get(npc_id, TIER_DOT[1])
		cell.add_child(dot)
		var txt := _label("%s · %s" % [String(dd.get("name", npc_id)), String(dd.get("stage", ""))], 15, COLOR_SUB)
		cell.add_child(txt)
		row.add_child(cell)
	_content.add_child(row)


## ③ 四只熊告别卡：档色徽章 + 名字 + 分档台词（零数字）。
func _build_bear_cards() -> void:
	var head := _label("他们来告别", 20, COLOR_INK)
	_content.add_child(head)
	for d in _bears:
		var dd: Dictionary = d
		var npc_id := String(dd.get("id", ""))
		var card := Panel.new()
		card.custom_minimum_size = Vector2(_content.custom_minimum_size.x, 88)
		card.add_theme_stylebox_override("panel", _style(Color("f0e6cf"), COLOR_BORDER, 8, 3))
		var inner := HBoxContainer.new()
		inner.position = Vector2(18, 13)
		inner.size = Vector2(card.custom_minimum_size.x - 36, 66)
		inner.add_theme_constant_override("separation", 14)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(DOT, DOT)
		dot.size = Vector2(DOT, DOT)
		dot.color = _badge.get(npc_id, TIER_DOT[1])
		inner.add_child(dot)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 6)
		var name_lab := _label(String(dd.get("name", npc_id)), 18, COLOR_INK)
		var line := _label(_farewell.get(npc_id, "一路顺风。"), 16, COLOR_SUB)
		vbox.add_child(name_lab)
		vbox.add_child(line)
		inner.add_child(vbox)

		card.add_child(inner)
		_content.add_child(card)


# ------------------------------------------------------------------ 报告交棒

func _on_report_pressed() -> void:
	# 先退场再交棒：本面板 layer=210 高于 ReportPanel 的 200，不先关掉会把
	# 报告面板整个压住 —— 报告其实已经生成，玩家却永远只能看到终局页。
	close()
	if _on_view_report.is_valid():
		_on_view_report.call()
		return
	var rp = REPORT_PANEL.new()
	get_tree().root.add_child(rp)
	rp.open()


func close() -> void:
	visible = false
	finale_closed.emit()


# ------------------------------------------------------------------ 工具

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _style(fill: Color, border: Color, corner: int, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_corner_radius_all(corner)
	s.set_border_width_all(width)
	return s


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", COLOR_INK)
	return b
