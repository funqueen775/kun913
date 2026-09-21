extends CanvasLayer
## 「我的报告」全屏面板（Batch 3，2026-09-17；版式 2026-09-19 重构对齐设计图）。
## 数据链路红线：报告只在服务端算（loader.py L7「scoring_cards 不得下发前端」），
## 这里**只渲染** ApiClient.fetch_report() 拉回来的 JSON，本地不算任何分。
## 拉取流程：open() → 状态条「正在生成…」→ ApiClient.generate_report() →
##   report_ready(report) → render(report)；report_failed(reason) → 状态条说明原因 + 可重试。
## 版式（对照设计图）：白卡 + 琥珀主色 + 每卡左侧竖排标题色条 + 三栏非对称网格，
## 左=行为风格总览（速写+六柱雷达）/能力六维（条形+补强注释），中=性格测评（五维+晋升窗口）/
## 终局评价（终局身份+关键时刻），右=岗位匹配。单屏不滚动。
## 探针：build/probe_report_panel.gd（喂契约 fixture）、build/probe_report_render_live.gd（喂真报告）。

signal closed

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

# 与设计图同源的暖色系统（色值集中在这几行）。
const COLOR_DIM := Color(0.05, 0.06, 0.05, 0.55)
const COLOR_CARD := Color("ffffff")
const COLOR_LINE := Color("e6e1d4")
const COLOR_INK := Color("3b2e22")
const COLOR_INK_2 := Color("6b5c4a")
const COLOR_INK_3 := Color("9c8d7a")
const COLOR_BRAND := Color("c07f2a")
const COLOR_BRAND_DEEP := Color("9c6420")
const COLOR_BRAND_SOFT := Color("f6e8d2")
const COLOR_GREEN := Color("2e8b57")
const COLOR_GREEN_BG := Color("eaf4ec")
const COLOR_BRICK := Color("c2554a")
const COLOR_BRICK_BG := Color("fbefec")
const COLOR_TRACK := Color("f0ebdf")
const COLOR_CHIP_BG := Color("faf8f2")
const COLOR_SOFT_BG := Color("fbfaf5")
const COLOR_STRIP_2 := Color("a8763a")

const PANEL_RECT := Rect2(0, 0, 1920, 1080)
const COL_LEFT_W := 460.0
const COL_RIGHT_W := 470.0
## 全屏放大系数：逻辑字号 ×FS，配合窗口 1536x864（canvas_items 缩放 0.8）。
## 1.55 太小、2.0 太大导致内容裁切 → 取 1.7：正文物理显示 ≈17.7px，内容基本完整放下。
const FS := 1.7


class RadarChart:
	extends Control
	## 六边形雷达（纯 _draw，不依赖贴图）。rows: [{pillar, score, cap}]。

	const INK := Color("3b2e22")
	const INK_2 := Color("6b5c4a")
	const BRAND := Color("c07f2a")

	var rows: Array = []
	var font: Font = null

	func _ring(cx: float, cy: float, rr: float, angles: PackedFloat32Array) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in angles.size():
			pts.append(Vector2(cx + rr * cos(angles[i]), cy + rr * sin(angles[i])))
		return pts

	func _draw() -> void:
		if rows.size() < 3 or font == null:
			return
		var cx := size.x / 2.0
		var cy := size.y / 2.0
		var r := minf(size.x, size.y) / 2.0 - 15.0
		var n := rows.size()
		var angles := PackedFloat32Array()
		for i in n:
			angles.append(-PI / 2.0 + TAU * float(i) / float(n))
		var grid := Color(0.35, 0.27, 0.18, 0.16)
		for k in [1.0 / 3.0, 2.0 / 3.0, 1.0]:
			draw_polyline(_ring(cx, cy, r * k, angles), grid, 1.0)
		var outer := _ring(cx, cy, r, angles)
		for i in n:
			draw_line(Vector2(cx, cy), outer[i], grid, 1.0)
		var data := PackedVector2Array()
		for i in n:
			var sc := clampf(float(rows[i].get("score", 0)), 0.0, 100.0) / 100.0
			data.append(Vector2(cx + r * sc * cos(angles[i]), cy + r * sc * sin(angles[i])))
		var fill := Color("c07f2a")
		fill.a = 0.26
		draw_colored_polygon(data, fill)
		draw_polyline(data, BRAND, 2.0)
		for i in n:
			draw_circle(data[i], 2.5, BRAND)
		for i in n:
			var p: Vector2 = outer[i]
			var nx := cos(angles[i])
			var ny := sin(angles[i])
			var txt := String(rows[i].get("pillar", ""))
			var val_txt := str(int(rows[i].get("score", 0)))
			var align := HORIZONTAL_ALIGNMENT_CENTER
			var pos := Vector2()
			if absf(nx) < 0.35:
				pos = Vector2(cx - 84.0, p.y + (22.0 if ny > 0.0 else -9.0))
			elif nx > 0.0:
				align = HORIZONTAL_ALIGNMENT_LEFT
				pos = Vector2(p.x + 14.0, p.y - 9.0)
			else:
				align = HORIZONTAL_ALIGNMENT_RIGHT
				pos = Vector2(p.x - 14.0, p.y - 9.0)
			draw_string(font, pos, txt, align, 150, 20, INK)
			draw_string(font, pos + Vector2(0, 26), val_txt, align, 150, 16, INK_2)


var _report: Dictionary = {}
var _dim: ColorRect
var _panel: Panel
var _hint: Label
var _main: HBoxContainer
var _col_left: VBoxContainer
var _col_mid: VBoxContainer
var _col_right: VBoxContainer
var _meta_box: HBoxContainer
var _status_pill: PanelContainer
var _status: Label
var _retry_btn: Button
var _close_btn: Button
var _sketch_label: Label
var _radar_chart: RadarChart
var _pillar_box: VBoxContainer
var _pillar_notes: Label
var _topics_box: VBoxContainer
var _five_box: VBoxContainer
var _promo_chips: FlowContainer
var _promo_final: RichTextLabel
var _jobs_box: VBoxContainer
var _job_note: Label
var _replay_box: VBoxContainer

func _ready() -> void:
	layer = 200
	visible = false
	_build_static()
	# 只连一次；处理器里用 visible 判断是否消费，避免面板关着时收包。
	ApiClient.report_ready.connect(_on_report_ready)
	ApiClient.report_failed.connect(_on_report_failed)


# ------------------------------------------------------------------ 开合

func open() -> void:
	visible = true
	_report = {}
	_clear_dynamic()
	_hint.visible = false
	_set_loading_state()
	# 两段式：POST 让服务端结算生成 → 成功自动接 GET 拉回整份报告（见 ApiClient.generate_report）。
	ApiClient.generate_report()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()


# ------------------------------------------------------------------ 静态骨架

func _build_static() -> void:
	_dim = ColorRect.new()
	_dim.color = COLOR_DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _board_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	# 内容区整体放进 ScrollContainer：FS=2.0 后单屏放不下就纵向滚动，不截断内容。
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	root.add_child(_build_head())

	_main = HBoxContainer.new()
	_main.add_theme_constant_override("separation", 14)
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_main)

	_col_left = VBoxContainer.new()
	_col_left.custom_minimum_size.x = COL_LEFT_W
	_col_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_left.add_theme_constant_override("separation", 10)
	_main.add_child(_col_left)

	_col_mid = VBoxContainer.new()
	_col_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_mid.size_flags_stretch_ratio = 0.62
	_col_mid.add_theme_constant_override("separation", 10)
	_main.add_child(_col_mid)

	_col_right = VBoxContainer.new()
	_col_right.custom_minimum_size.x = COL_RIGHT_W
	_col_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_right.add_theme_constant_override("separation", 10)
	_main.add_child(_col_right)

	_build_overview_card()
	_build_pillar_card()
	_build_topics_card()
	_build_five_card()
	_build_replay_card()
	_build_jobs_card()

	var foot := _label("— 报告由服务端结算，仅反映游戏内真实行为 —", 11, COLOR_INK_2)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.custom_minimum_size.y = 14
	root.add_child(foot)

	_hint = _label("", 15, COLOR_INK_2)
	_hint.size = Vector2(900, 80)
	_hint.position = Vector2(PANEL_RECT.size.x / 2.0 - 450, PANEL_RECT.size.y / 2.0 - 40)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	_panel.add_child(_hint)


func _build_head() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.custom_minimum_size.y = 48

	var title_area := VBoxContainer.new()
	title_area.add_theme_constant_override("separation", 1)
	title_area.add_child(_label("我的报告", 22, COLOR_INK))
	title_area.add_child(_label("48 个月 · 行为测评", 11, COLOR_INK_3))
	head.add_child(title_area)

	_meta_box = HBoxContainer.new()
	_meta_box.add_theme_constant_override("separation", 8)
	_meta_box.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_meta_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	_status_pill = PanelContainer.new()
	_status = _label("", 13, COLOR_GREEN)
	_status_pill.add_child(_status)
	_status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_status_pill)

	_retry_btn = _button("重新拉取", false)
	_retry_btn.visible = false
	_retry_btn.pressed.connect(open)
	_retry_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_retry_btn)

	_close_btn = _button("关闭", true)
	_close_btn.pressed.connect(close)
	_close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_close_btn)

	return head


## 卡片：顶部通宽琥珀色标题条（横排白字）+ 下方内容区；卡片带轻阴影提升层次。
func _card(title: String, accent: Color, hint: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	var card_sb := _flat(COLOR_CARD, COLOR_LINE, 16, 1, Vector4(0, 0, 0, 0))
	card_sb.shadow_color = Color(0.30, 0.24, 0.15, 0.09)
	card_sb.shadow_size = 10
	card_sb.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", card_sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	card.add_child(vb)

	# 顶部标题条：accent 背景，只圆上两角，与卡片边框衔接。
	var head_sb := StyleBoxFlat.new()
	head_sb.bg_color = accent
	head_sb.corner_radius_top_left = 16
	head_sb.corner_radius_top_right = 16
	head_sb.corner_radius_bottom_left = 0
	head_sb.corner_radius_bottom_right = 0
	head_sb.content_margin_left = 16
	head_sb.content_margin_right = 14
	head_sb.content_margin_top = 5
	head_sb.content_margin_bottom = 5
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", head_sb)
	vb.add_child(head)

	var head_box := HBoxContainer.new()
	head_box.add_theme_constant_override("separation", 9)
	head.add_child(head_box)
	# 标题前的白色圆点装饰，让色条不死板。
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(6, 6)
	var dot_sb := StyleBoxFlat.new()
	dot_sb.bg_color = Color(1, 1, 1, 0.92)
	dot_sb.set_corner_radius_all(3)
	dot.add_theme_stylebox_override("panel", dot_sb)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_box.add_child(dot)
	head_box.add_child(_label(title, 15, Color.WHITE))
	if not hint.is_empty():
		head_box.add_child(_label(hint, 11, Color(1, 1, 1, 0.82)))

	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 12)
	body_margin.add_theme_constant_override("margin_right", 12)
	body_margin.add_theme_constant_override("margin_top", 10)
	body_margin.add_theme_constant_override("margin_bottom", 10)
	vb.add_child(body_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	body_margin.add_child(vbox)
	return card


func _card_body(card: PanelContainer) -> VBoxContainer:
	# 卡片结构：Panel > VBox > [标题条, MarginContainer > VBox]；内容区就是那个 VBox。
	var vb := card.get_child(0) as VBoxContainer
	var margin := vb.get_child(1) as MarginContainer
	return margin.get_child(0) as VBoxContainer


func _build_overview_card() -> void:
	# 行为风格总览：人格速写 + 六柱雷达（对照设计图合并为一张卡）。
	var card := _card("行为风格总览", COLOR_BRAND, "一句话看懂你的行为风格")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col_left.add_child(card)
	var body := _card_body(card)

	var soft := PanelContainer.new()
	soft.add_theme_stylebox_override("panel",
		_flat(Color("f6e8d2"), Color("c07f2a", 0.22), 11, 1, Vector4(11, 11, 9, 9)))
	_sketch_label = _label("", 12, COLOR_INK, 300, true)
	soft.add_child(_sketch_label)
	body.add_child(soft)

	var divider := ColorRect.new()
	divider.color = COLOR_LINE
	divider.custom_minimum_size.y = 1
	body.add_child(divider)

	_radar_chart = RadarChart.new()
	_radar_chart.font = FONT
	_radar_chart.custom_minimum_size = Vector2(170, 170)
	_radar_chart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_radar_chart)


func _build_pillar_card() -> void:
	# 能力六维：六根横向条 + 单行补强注释。
	var card := _card("能力六维", COLOR_BRAND_DEEP, "按在册事件归一化")
	_col_left.add_child(card)
	var body := _card_body(card)

	_pillar_box = VBoxContainer.new()
	_pillar_box.add_theme_constant_override("separation", 2)
	body.add_child(_pillar_box)

	_pillar_notes = _label("", 9, COLOR_INK_2, 300, true)
	body.add_child(_pillar_notes)


func _build_topics_card() -> void:
	# 行为专题：决策风格 / 价值观 / 归因方式 / 未来取向（对照设计图左下模块）。
	var card := _card("行为专题", COLOR_BRAND_DEEP, "关键场景里的行为倾向")
	_col_left.add_child(card)
	var body := _card_body(card)
	_topics_box = VBoxContainer.new()
	_topics_box.add_theme_constant_override("separation", 2)
	body.add_child(_topics_box)


func _build_five_card() -> void:
	# 性格测评：五维条 + 六次晋升窗口（对照设计图合并为一张卡）。
	var card := _card("性格测评", COLOR_BRAND, "48 个月行为 · 0-10 分")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col_mid.add_child(card)
	var body := _card_body(card)
	_five_box = VBoxContainer.new()
	_five_box.add_theme_constant_override("separation", 6)
	# 弹性吸收卡片余量：五行行盒各自 EXPAND，把拉伸摊成均匀行距，不出现整块空洞。
	_five_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_five_box)
	var divider := ColorRect.new()
	divider.color = COLOR_LINE
	divider.custom_minimum_size.y = 1
	body.add_child(divider)
	_promo_chips = FlowContainer.new()
	_promo_chips.add_theme_constant_override("h_separation", 8)
	_promo_chips.add_theme_constant_override("v_separation", 6)
	body.add_child(_promo_chips)


func _build_jobs_card() -> void:
	var card := _card("岗位匹配", COLOR_BRAND, "按你的行为画像匹配")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_col_right.add_child(card)
	var body := _card_body(card)
	_jobs_box = VBoxContainer.new()
	_jobs_box.add_theme_constant_override("separation", 10)
	_jobs_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_jobs_box)
	_job_note = _label("", 11, COLOR_INK_3, 300, true)
	_job_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_job_note)


func _build_replay_card() -> void:
	# 终局评价：终局身份标签 + 关键时刻（对照设计图合并为一张卡）。
	var card := _card("终局评价", COLOR_STRIP_2, "印象最深的选择")
	_col_mid.add_child(card)
	var body := _card_body(card)
	_promo_final = RichTextLabel.new()
	_promo_final.bbcode_enabled = true
	_promo_final.fit_content = true
	_promo_final.scroll_active = false
	_promo_final.add_theme_font_override("normal_font", _vfont(16))
	_promo_final.add_theme_font_size_override("normal_font_size", 16)
	_promo_final.add_theme_color_override("default_color", COLOR_INK_2)
	_promo_final.add_theme_constant_override("line_separation", -8)
	_promo_final.custom_minimum_size.x = 520
	body.add_child(_promo_final)
	var divider := ColorRect.new()
	divider.color = COLOR_LINE
	divider.custom_minimum_size.y = 1
	body.add_child(divider)
	_replay_box = VBoxContainer.new()
	_replay_box.add_theme_constant_override("separation", 8)
	body.add_child(_replay_box)


# ------------------------------------------------------------------ 数据入口

func _on_report_ready(report: Dictionary) -> void:
	if not visible:
		return
	_report = report
	render(report)


func _on_report_failed(reason: String) -> void:
	if not visible:
		return
	_set_failed_state(String(reason))


## 渲染整份报告（也供探针直接喂 fixture / 真报告，不走网络）。
func render(report: Dictionary) -> void:
	_report = report
	_clear_dynamic()
	if report.is_empty() or not report.has("layers"):
		_set_failed_state("报告内容为空。")
		return
	_set_ready_state()
	var persona: Dictionary = report.get("layers", {}).get("persona", {})
	_fill_header(report)
	_fill_sketch(String(persona.get("personaSketch", "")))
	_fill_radar(persona.get("radar", []))
	_fill_topics(persona.get("topics", []))
	_fill_bigfive(persona.get("bigfive", []))
	_fill_promo(persona.get("promotionTrack", {}))
	_fill_jobs(persona.get("career", {}))
	_fill_replay(report.get("evidenceReplay", []))


# ------------------------------------------------------------------ 各节渲染

func _fill_header(report: Dictionary) -> void:
	_clear(_meta_box)
	_meta_chip("共 %d 次选择" % int(report.get("decisionCount", 0)))
	var ver := String(report.get("scoringVersion", ""))
	if not ver.is_empty():
		_meta_chip("口径 %s" % ver)
	var t := String(report.get("generatedAt", ""))
	if not t.is_empty():
		t = t.replace("T", " ")
		var plus := t.find("+")
		if plus > 0:
			t = t.substr(0, plus)
		t = t.trim_suffix(" ")
		if t.length() > 16:
			t = t.substr(0, 16)
		_meta_chip(t)


func _meta_chip(text: String) -> void:
	_meta_box.add_child(_pill(text, COLOR_CHIP_BG, COLOR_INK_2, COLOR_LINE, 999, 12, 5, 12))


func _fill_sketch(sketch: String) -> void:
	_sketch_label.text = sketch


func _fill_radar(rows: Array) -> void:
	_clear(_pillar_box)
	_pillar_notes.text = ""
	_radar_chart.rows = rows
	_radar_chart.queue_redraw()
	if rows.is_empty():
		_pillar_notes.text = "能力六柱：这一局的证据还不够下结论。"
		return
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name := _label(String(row.get("pillar", "")), 11, COLOR_INK_2)
		name.custom_minimum_size.x = 96
		line.add_child(name)
		line.add_child(_bar(float(row.get("score", 0)), 100.0, 8, COLOR_BRAND))
		var val := _label("%d / %d" % [int(row.get("score", 0)), int(row.get("cap", 0))], 10, COLOR_INK_3)
		val.custom_minimum_size.x = 84
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(val)
		_pillar_box.add_child(line)
	var notes := ""
	for row in rows:
		var note := String(row.get("note", ""))
		if not note.is_empty():
			notes += "· %s：%s\n" % [String(row.get("pillar", "")), note]
	_pillar_notes.text = notes.trim_suffix("\n")


func _fill_topics(topics: Array) -> void:
	_clear(_topics_box)
	if topics.is_empty():
		return
	for t in topics:
		if not bool(t.get("displayable", true)):
			continue
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var title := _label(String(t.get("title", "")), 11, COLOR_INK)
		box.add_child(title)
		var count := 0
		for b in t.get("bullets", []):
			if count >= 1:
				break
			var line := _label("%s：%s" % [String(b.get("label", "")), String(b.get("value", ""))],
				9, COLOR_INK_2, 300, true)
			box.add_child(line)
			count += 1
		_topics_box.add_child(box)


func _fill_bigfive(rows: Array) -> void:
	_clear(_five_box)
	for row in rows:
		var cn := String(row.get("traitCn", ""))
		# 每维一个弹性行盒：卡片被拉伸时五行均分留白，不出现整块空洞。
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name := _label(cn, 12, COLOR_INK)
		name.custom_minimum_size.x = 84
		line.add_child(name)
		var behavior: Variant = row.get("behavior")
		var val := _label("", 11, COLOR_INK_3)
		val.custom_minimum_size.x = 96
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if behavior is float or behavior is int:
			line.add_child(_bar(float(behavior), 10.0, 10, COLOR_BRAND))
			val.text = "%s / 10" % _f1(behavior)
		else:
			line.add_child(Control.new())  # 占位，保持行高一致
			val.text = "证据不足"
		line.add_child(val)
		var ev := _label("%d 条" % int(row.get("evidenceCount", 0)), 10, COLOR_INK_3)
		ev.custom_minimum_size.x = 60
		ev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(ev)
		box.add_child(line)
		var note := String(row.get("note", ""))
		if not note.is_empty():
			box.add_child(_label(note, 9, COLOR_INK_3, 300, true))
		_five_box.add_child(box)


func _fill_promo(track: Dictionary) -> void:
	_clear(_promo_chips)
	_promo_final.text = ""
	var windows: Array = track.get("windows", [])
	for w in windows:
		var passed := bool(w.get("passed", false))
		var txt := "第 %d 月　%s" % [int(w.get("month", 0)),
			("✓ L%d" % int(w.get("levelAfter", 0))) if passed else "—"]
		if passed:
			_promo_chips.add_child(_pill(txt, COLOR_GREEN_BG, COLOR_GREEN, Color("2e8b57", 0.35), 999, 10, 3, 10))
		else:
			_promo_chips.add_child(_pill(txt, COLOR_CHIP_BG, COLOR_INK_2, COLOR_LINE, 999, 10, 3, 10))
	var grade: Dictionary = track.get("finalGrade", {})
	if grade.is_empty():
		return
	var label := String(grade.get("label", ""))
	var line := String(grade.get("line", ""))
	var head := "终局 [color=#9c6420]%s[/color]（L%d%s）" % [
		String(grade.get("grade", "")), int(grade.get("level", 1)),
		(" " + label) if not label.is_empty() else ""]
	if not line.is_empty():
		head += "　·　%s" % line
	_promo_final.text = head


func _fill_jobs(career: Dictionary) -> void:
	_clear(_jobs_box)
	_job_note.text = ""
	var top3: Array = career.get("top3", [])
	if top3.is_empty():
		_jobs_box.add_child(_label("本局暂无匹配岗位画像，走完更多剧情再来看看。", 12, COLOR_INK_3, 280, true))
	else:
		for i in mini(top3.size(), 3):
			_jobs_box.add_child(_job_row(i, top3[i] as Dictionary))
	var note := String(career.get("note", ""))
	if not note.is_empty():
		_job_note.text = note


## 单个岗位推荐卡：排名徽章 + 岗位名 + 看重特质徽章 + 匹配分 + 匹配条 + 五维小徽章。
func _job_row(idx: int, job: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	# 三张卡交替底色，避免同色堆叠成"砖墙"。
	var bg := COLOR_SOFT_BG if idx % 2 == 1 else COLOR_CARD
	row.add_theme_stylebox_override("panel", _flat(bg, COLOR_LINE, 13, 1, Vector4(12, 12, 8, 8)))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)

	hb.add_child(_rank_badge(["一", "二", "三"][idx], idx == 0))

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 4)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(main)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := _label(String(job.get("title", "")), 13, COLOR_INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var phrase := String(job.get("emphasisPhrase", ""))
	if not phrase.is_empty():
		head.add_child(_pill("看重「%s」" % phrase, COLOR_BRAND_SOFT, COLOR_BRAND_DEEP,
			Color("c07f2a", 0.25), 6, 7, 2, 9))
	var score := float(job.get("score", 0))
	var score_lbl := _label("%.1f 分" % score, 14, COLOR_BRAND_DEEP)
	score_lbl.custom_minimum_size.x = 86
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(score_lbl)
	main.add_child(head)

	main.add_child(_bar(score, 100.0, 5, COLOR_BRAND))

	var line_txt := String(job.get("line", ""))
	if not line_txt.is_empty():
		main.add_child(_label(line_txt, 11, COLOR_INK_2, 250, true))

	var dims: Array = job.get("dims", [])
	if not dims.is_empty():
		var fc := FlowContainer.new()
		fc.add_theme_constant_override("h_separation", 4)
		fc.add_theme_constant_override("v_separation", 3)
		for d in dims:
			fc.add_child(_dim_chip(d as Dictionary))
		main.add_child(fc)
	return row


func _rank_badge(rank: String, gold: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(34, 34)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("b07f28") if gold else COLOR_BRAND_DEEP
	sb.set_corner_radius_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var b := _label(rank, 15, Color.WHITE)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(b)
	return p


## 小徽章（岗位看重特质 / 五维匹配）。gap < 1 视为合拍（绿），否则差一截（砖红）。
## 证据不足的维度后端按契约发 actual/gap=null（留空不估算）：不硬转数字，
## 给一枚「证据不足」灰徽章，绝不拿 0 分假数据顶替。
func _dim_chip(d: Dictionary) -> PanelContainer:
	var cn := String(d.get("traitCn", ""))
	var actual: Variant = d.get("actual")
	if actual == null or not (actual is float or actual is int):
		return _pill("%s 证据不足" % cn, COLOR_CHIP_BG, COLOR_INK_2, COLOR_LINE, 6, 8, 2, 9)
	var av := float(actual)
	var iv := float(d.get("ideal", 0))
	var gap_v: Variant = d.get("gap")
	var gap := absf(float(gap_v) if (gap_v is float or gap_v is int) else av - iv)
	var ok := gap < 1.0
	var txt := "%s %.1f/%.1f %s" % [cn, av, iv, "✓" if ok else "▼"]
	if ok:
		return _pill(txt, COLOR_GREEN_BG, COLOR_GREEN, Color("2e8b57", 0.4), 6, 8, 2, 9)
	return _pill(txt, COLOR_BRICK_BG, COLOR_BRICK, Color("c2554a", 0.4), 6, 8, 2, 9)


func _fill_replay(rows: Array) -> void:
	_clear(_replay_box)
	for i in mini(rows.size(), 2):
		_replay_box.add_child(_replay_item(rows[i] as Dictionary))
	if rows.size() > 2:
		_replay_box.add_child(_label("…… 共 %d 条" % rows.size(), 11, COLOR_INK_3))
	elif rows.is_empty():
		_replay_box.add_child(_label("关键时刻：数据还没攒够。", 12, COLOR_INK_2))


func _replay_item(e: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(COLOR_SOFT_BG, COLOR_LINE, 11, 1, Vector4(9, 9, 7, 7)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	p.add_child(vb)
	var when := "第 %d 个月 · %s · 犹豫 %.0f 秒" % [
		int(e.get("month", 0)), String(e.get("nodeId", "")),
		float(e.get("hesitationMs", 0)) / 1000.0]
	if int(e.get("switchCount", 0)) > 0:
		when += " · 反复 %d 次" % int(e.get("switchCount", 0))
	vb.add_child(_label(when, 10, COLOR_INK_3, 330, true))
	var snippet := String(e.get("snippet", ""))
	if snippet.length() > 48:
		snippet = snippet.substr(0, 48) + "…"
	vb.add_child(_label(snippet, 11, COLOR_INK, 330, true))
	return p


# ------------------------------------------------------------------ 状态

func _set_loading_state() -> void:
	_status.text = "● 正在生成…"
	_status_style(COLOR_BRAND_SOFT, COLOR_BRAND_DEEP)
	_retry_btn.visible = false


func _set_ready_state() -> void:
	_status.text = "● 已生成"
	_status_style(COLOR_GREEN_BG, COLOR_GREEN)
	_retry_btn.visible = false
	# 失败态提示（如「上一个请求还在路上」）必须在成功渲染后清除，
	# 否则会残留悬浮在面板中央。
	_hint.visible = false


func _set_failed_state(reason: String) -> void:
	_status.text = "● 生成失败"
	_status_style(COLOR_BRICK_BG, COLOR_BRICK)
	_retry_btn.visible = true
	_hint.text = reason
	_hint.visible = true


func _status_style(bg: Color, fg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_status_pill.add_theme_stylebox_override("panel", sb)
	_status.add_theme_color_override("font_color", fg)


# ------------------------------------------------------------------ 小构件

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _clear_dynamic() -> void:
	_clear(_meta_box)
	_clear(_pillar_box)
	_clear(_topics_box)
	_clear(_five_box)
	_clear(_promo_chips)
	_clear(_jobs_box)
	_clear(_replay_box)
	_sketch_label.text = ""
	_pillar_notes.text = ""
	_promo_final.text = ""
	_job_note.text = ""
	_radar_chart.rows = []
	_radar_chart.queue_redraw()


func _f1(v) -> String:
	if v is float or v is int:
		return "%.1f" % float(v)
	return str(v)


func _bar(value: float, max_v: float, h: float, fill: Color) -> ProgressBar:
	var bh := h * FS
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = max_v
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, bh)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = COLOR_TRACK
	bg.set_corner_radius_all(int(bh / 2.0))
	bar.add_theme_stylebox_override("background", bg)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill
	fill_sb.set_corner_radius_all(int(bh / 2.0))
	bar.add_theme_stylebox_override("fill", fill_sb)
	return bar


func _pill(text: String, bg: Color, fg: Color, border := Color.TRANSPARENT,
		radius := 999, pad_x := 10, pad_y := 4, size := 11) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, size, fg))
	return p


## min_w > 0 时锚定最小宽度；wrap=true 才开自动换行。
## 默认不换行：autowrap Label 在容器里以 1px 宽度算最小尺寸时高度会爆炸
## （实测长文本 min=(1,1011)），所以只有真正多行的文本才开换行并给宽度锚点。
## 字体统一：直接用原始字体（NotoSansCJKsc 真实行高 ≈1.62×字号，并不虚高）。
## ⚠ 不要用 FontVariation 负间距压行高：spacing 会直接削减字体 get_height，
## 0.8/0.5 会把行高压到 0.3×，再叠 line_spacing 负值 → 单行 min 高度塌成 0，
## 文本整块不渲染（窗口模式实测 13px min=(330,0)）。行距靠 line_spacing=-4
## 轻压即可（单行不受影响，多行 9px 也有 10.6px/行，不重叠）。
func _vfont(_font_size: int) -> Font:
	return FONT


func _label(text: String, font_size: int, color: Color, min_w := 0.0, wrap := false) -> Label:
	var fs: int = max(1, int(round(font_size * FS)))
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _vfont(fs))
	label.add_theme_font_size_override("font_size", fs)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing", -6)
	if min_w > 0.0:
		label.custom_minimum_size.x = min_w * FS
	return label


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(140, 52)
	var sb := StyleBoxFlat.new()
	if primary:
		sb.bg_color = COLOR_BRAND
		sb.set_corner_radius_all(9)
		b.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate()
		hover.bg_color = COLOR_BRAND_DEEP
		b.add_theme_stylebox_override("hover", hover)
		var pressed := sb.duplicate()
		pressed.bg_color = COLOR_BRAND_DEEP.darkened(0.1)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
	else:
		sb.bg_color = COLOR_CARD
		sb.border_color = COLOR_LINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		b.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate()
		hover.bg_color = COLOR_CHIP_BG
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_color_override("font_color", COLOR_INK_2)
		b.add_theme_color_override("font_hover_color", COLOR_INK)
	return b


func _board_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	# 面板底用柔和米白，纯白卡片 + 轻阴影浮在其上，层次更分明。
	sb.bg_color = Color("f4f0e4")
	sb.border_color = COLOR_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(24)
	sb.shadow_color = Color(0.24, 0.19, 0.11, 0.16)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 10)
	return sb


func _flat(bg: Color, border: Color, radius: int, border_w: int = 0,
		m: Vector4 = Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	sb.content_margin_left = m.x
	sb.content_margin_right = m.y
	sb.content_margin_top = m.z
	sb.content_margin_bottom = m.w
	return sb
