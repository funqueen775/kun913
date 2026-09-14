extends Control
## 开场两屏（标题 → 认识小镇），数据驱动。
##
## 移植自「熊心壮职」React 前端的 TitleScreen / TownIntroScreen，
## 但视图全部用 Godot 的 Control 节点重建——JSX/CSS 在这里用不了。
##
## 数据源：res://data/story/intro.json（文案、色板、版式参数都在那儿，改文案不用碰本文件）
##         路径按《前后端协作架构与开发规范》§4 —— data/story/ 放剧情内容与配置。
## 人物头像：直接裁 kun913 自带的纸娃娃图集（assets/characters/paper_doll_64），
##           不依赖美术额外出图；纸娃娃是像素图，放大必须用 nearest 过滤。
## 其他贴图：ResourceLoader.exists() 兜底，图没到位就渲染纯色版，图放进去自动生效。
##
## 【版式怎么来的】本文件里所有坐标 = web 的 CSS 设计值 ×DESIGN_SCALE，一处都别凭感觉改：
##   第 1 屏  → web/src/screens/TitleScreen.css（两块独立的牌：瓦顶横幅 + 菜单牌）
##   第 2 屏  → web/src/screens/TownIntroScreen.css + web/src/components/ui.css 的 .frame
##   装饰件  → scripts/ui/IntroDeco.gd（瓦顶/宝石/钟楼/藤叶/顶栏图标，形状照抄 ui.tsx 的 SVG）
##   色值    → data/story/intro.json 的 palette，禁止在本文件里写死颜色
##
## 挂法：新建 Control 场景挂本脚本即可（见 Intro.tscn）。
##       本脚本不改 project.godot 的 main_scene，不影响现有地图调试入口。

const DATA_PATH := "res://data/story/intro.json"
## 人物名单的单一来源：与地图内 NPC 共用一份，见《前后端协作架构与开发规范》§4。
## intro.json 里已不再存人物，只有 castSource 指回这里。
const NPCS_PATH := "res://data/town/npcs.json"
const DEFAULT_FONT := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
## 第 2 屏木框背后的世界地图（参考图里框外能看到小镇和 A/B/C 区名牌）
const TOWN_MAP := "res://assets/town/workplace_town_reference.png"
const DECO := preload("res://scripts/ui/IntroDeco.gd")

## 设计稿 1600x900 → 工程 viewport 1920x1080
const DESIGN_SCALE := 1.2

var _d: Dictionary = {}        # intro.json 全文
var _cast: Array = []          # 人物名单（来自 npcs.json，不是 intro.json）
var _font: Font = null
var _pal: Dictionary = {}      # 色板（Color）
var _met: Dictionary = {}      # 版式参数（float）
var _fv: Dictionary = {}       # 字间距 -> FontVariation 缓存

var _stage: Control = null     # 当前屏的容器，换屏时整体清掉
var _screen := "title"
var _page := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_data()
	_show_title()


# ------------------------------------------------------------------ 数据

func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("找不到 %s" % DATA_PATH)
		return
	var txt := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s 不是合法 JSON 对象" % DATA_PATH)
		return
	_d = parsed
	_cast = _load_npcs(NPCS_PATH)
	print("[IntroSequence] 人物名单 %d 位，来源 %s" % [_cast.size(), NPCS_PATH])

	var palette: Dictionary = _d.get("palette", {})
	for k in palette.keys():
		_pal[k] = Color.html(str(palette[k]))

	var metrics: Dictionary = _d.get("metrics", {})
	for k in metrics.keys():
		var v: Variant = metrics[k]
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			_met[k] = float(v)

	if ResourceLoader.exists(DEFAULT_FONT):
		_font = load(DEFAULT_FONT)


## 读人物名单。读不到就返回空数组（名单页会是空的，但不会崩，
## 控制台会有 push_error 提示），地图那边也读同一个文件。
func _load_npcs(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("找不到 %s" % path)
		return []
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s 不是合法 JSON 对象" % path)
		return []
	return parsed.get("npcs", [])


func px(v: float) -> float:
	return v * DESIGN_SCALE


func col(key: String) -> Color:
	return _pal.get(key, Color.MAGENTA)


func met(key: String, fallback: float) -> float:
	return float(_met.get(key, fallback))


# ------------------------------------------------------------------ 通用零件

## 带字间距的字体（CSS 的 letter-spacing 在 Godot 里靠 FontVariation.spacing_glyph）
func _font_sp(tracking: float) -> Font:
	if _font == null:
		return null
	var key := int(round(tracking * 10.0))
	if not _fv.has(key):
		var fv := FontVariation.new()
		fv.base_font = _font
		fv.spacing_glyph = int(round(px(tracking)))
		_fv[key] = fv
	return _fv[key]


func _flat(bg: Color, border: Color, width: float, radius: float, bottom_bevel: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if width > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(round(px(width))))
	sb.set_corner_radius_all(int(round(px(radius))))
	if bottom_bevel:
		# CSS 的 0 3px 0 rgba(91,58,38,.36)：硬底边（厚度），用很小的模糊半径近似
		sb.shadow_color = Color(border.r, border.g, border.b, 0.36)
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(0.0, px(3.0))
	return sb


func _place(c: Control, x: float, y: float, w: float = -1.0, h: float = -1.0) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2(px(x), px(y))
	if w >= 0.0:
		c.size = Vector2(px(w), c.size.y)
		c.custom_minimum_size.x = px(w)
	if h >= 0.0:
		c.size = Vector2(c.size.x, px(h))
		c.custom_minimum_size.y = px(h)


func _mk_label(text: String, fsize: float, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		tracking: float = 0.0, outline: Color = Color(0, 0, 0, 0), outline_w: float = 0.0,
		wrap_width: float = 0.0) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.horizontal_alignment = align
	# ⚠ autowrap 的坑：容器在宽度还是 0 的时候量最小高度，autowrap 一开就会把
	#   「一段话」算成「一行一个字」的竖排高度，页签/页码竖排、页脚挤出屏都是它。
	#   所以：短文本一律不换行；只有段落这种确定宽度的文本才开，且必须同时给
	#   custom_minimum_size.x（wrap_width，设计稿像素），让高度按真实宽度算。
	if wrap_width > 0.0:
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size.x = px(wrap_width)
	else:
		lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	var f := _font_sp(tracking)
	if f != null:
		lb.add_theme_font_override("font", f)
	lb.add_theme_font_size_override("font_size", int(round(px(fsize))))
	lb.add_theme_color_override("font_color", color)
	if outline_w > 0.0:
		lb.add_theme_color_override("font_outline_color", outline)
		lb.add_theme_constant_override("outline_size", int(round(px(outline_w))))
	return lb


## 小牌：方角细边，装页码 / 提示 / 存档条这类小信息
func _mk_plate(child: Control, pad: float = 8.0) -> PanelContainer:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override(
		"panel", _flat(col("creamLight"), col("ink"), 2.0, met("radiusSm", 6.0)))
	var mg := MarginContainer.new()
	for side in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + side, int(px(pad + 4.0)))
	for side in ["top", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, int(px(pad * 0.5 + 2.0)))
	mg.add_child(child)
	wrap.add_child(mg)
	return wrap


## 按钮：圆角很小、底边只有薄薄一层，不做厚重立体投影
func _mk_button(text: String, variant: String = "primary") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var f := _font_sp(3.0)
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", int(round(px(20.0))))

	var base := col("brick")
	var hover := col("brickDark")
	var fg := col("titleOnWood")
	var border := col("brickDark") if variant == "primary" else col("ink")
	match variant:
		"secondary":
			base = col("creamLight")
			hover = col("cream")
			fg = col("ink")
		"exit":
			base = col("green")
			hover = col("leaf")
			fg = col("titleOnWood")
			border = col("ink")

	btn.add_theme_stylebox_override("normal", _flat(base, border, 2.0, met("radiusSm", 6.0), true))
	btn.add_theme_stylebox_override("hover", _flat(hover, border, 2.0, met("radiusSm", 6.0), true))
	btn.add_theme_stylebox_override("pressed", _flat(border, border, 2.0, met("radiusSm", 6.0)))
	btn.add_theme_stylebox_override("focus", _flat(base, border, 2.0, met("radiusSm", 6.0)))
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	return btn


## 顶栏小方钮（参考图右上角那三个）
func _mk_icon_button(icon: String, label: String) -> Control:
	var kind := DECO.Kind.ICON_HELP
	match icon:
		"report":
			kind = DECO.Kind.ICON_DOC
		"settings":
			kind = DECO.Kind.ICON_SLIDER
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override(
		"panel", _flat(col("cream"), col("ink"), 2.0, met("radiusMd", 10.0), true))
	wrap.tooltip_text = label
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px(56.0), px(56.0))
	var deco: Control = DECO.new()
	deco.setup(kind, _pal, px(1.6), false, _font)
	deco.position = Vector2(px((56.0 - 32.0 * 1.6) * 0.5), px((56.0 - 32.0 * 1.6) * 0.5))
	holder.add_child(deco)
	wrap.add_child(holder)
	return wrap


## 贴图零件。两种写法：
##   { "image": "res://..." }                        整张图
##   { "atlas": "res://...", "region": [x,y,w,h] }   从图集里裁一块
## 图不存在时返回空 TextureRect（不报错，占位仍在，版式不跳）。
func _mk_art(cfg: Dictionary) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 像素图放大必须 nearest
	if cfg.has("atlas"):
		var atlas_path := str(cfg["atlas"])
		if ResourceLoader.exists(atlas_path):
			var at := AtlasTexture.new()
			at.atlas = load(atlas_path)
			var r: Array = cfg.get("region", [0, 0, 64, 80])
			if r.size() >= 4:
				at.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
			tr.texture = at
	elif cfg.has("image"):
		var img_path := str(cfg["image"])
		if ResourceLoader.exists(img_path):
			tr.texture = load(img_path)
	return tr


## 从人物条目推出头像贴图配置（裁纸娃娃图集的朝下站立帧）
func _portrait_cfg(who: Dictionary) -> Dictionary:
	var pd: Dictionary = _d.get("paperDoll", {})
	var pattern := str(pd.get("atlasPattern", ""))
	var loadout := str(who.get("loadout", ""))
	if pattern == "" or loadout == "":
		return {}
	return {
		"atlas": pattern.replace("{loadout}", loadout),
		"region": pd.get("portraitRegion", [0, 0, 64, 80]),
	}


# ------------------------------------------------------------------ 装饰件与底图

## 铺一张等比铺满（cover）的底图；图不存在就退成纯色底
func _add_bg(parent: Control, path: String, fallback: Color) -> void:
	if path != "" and ResourceLoader.exists(path):
		var bg := TextureRect.new()
		bg.texture = load(path)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(bg)
	else:
		var rect := ColorRect.new()
		rect.color = fallback
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(rect)


func _mk_deco(kind: int, x: float, y: float, scale: float, flip: bool = false) -> Control:
	var deco: Control = DECO.new()
	deco.setup(kind, _pal, scale, flip, _font)
	deco.position = Vector2(px(x), px(y))
	return deco


func _clear_stage() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null


# ------------------------------------------------------------------ 标题屏（第 1 屏）

func _show_title() -> void:
	_clear_stage()
	_screen = "title"
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	var ts: Dictionary = _d.get("titleScreen", {})

	# 底图：专门的夜景标题画面（月夜小熊镇 + 湖心熊石雕塑），不是游戏内的俯视地图
	_add_bg(_stage, str(ts.get("background", "")), col("woodDark"))

	# 右上三颗方钮：CSS 是 top:56 / right:34 / gap:12
	var top_items: Array = ts.get("topbar", [])
	var bw := 56.0
	var gap := 12.0
	var total := bw * float(top_items.size()) + gap * float(maxi(top_items.size() - 1, 0))
	var bx := 1600.0 - 34.0 - total
	for item in top_items:
		var btn := _mk_icon_button(str(item.get("icon", "")), str(item.get("label", "")))
		_place(btn, bx, 56.0, bw, bw)
		_stage.add_child(btn)
		bx += bw + gap

	# 左列：上「瓦顶 + 米黄横幅」，下「菜单牌」，两块独立的牌（Stack 在 CSS 里是 top:206 / left:92 / width:560）
	var stack_left := 92.0
	var stack_width := 560.0
	var stack_top := 206.0

	# --- 标题牌 ---
	var banner_w := 520.0
	var banner_x := stack_left + (stack_width - banner_w) * 0.5
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override(
		"panel", _flat(col("creamLight"), col("ink"), 3.0, met("radiusMd", 10.0), true))
	var hair := Control.new()   # ::before 那圈细描边（inset 6px）
	hair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hair.offset_left = px(6.0)
	hair.offset_top = px(6.0)
	hair.offset_right = -px(6.0)
	hair.offset_bottom = -px(6.0)
	hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hair_panel := Panel.new()
	hair_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hair_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hair_panel.add_theme_stylebox_override(
		"panel", _flat(Color(0, 0, 0, 0), Color(col("ink").r, col("ink").g, col("ink").b, 0.4), 1.0, met("radiusSm", 6.0)))
	hair.add_child(hair_panel)
	var title_lb := _mk_label(str(ts.get("title", "")), 58.0, col("ink"),
		HORIZONTAL_ALIGNMENT_CENTER, 14.0, col("creamLight"), 2.0)
	title_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var banner_pad := MarginContainer.new()
	for side in ["left", "right"]:
		banner_pad.add_theme_constant_override("margin_" + side, int(px(30.0)))
	banner_pad.add_theme_constant_override("margin_top", int(px(30.0)))
	banner_pad.add_theme_constant_override("margin_bottom", int(px(26.0)))
	banner_pad.add_child(title_lb)
	banner.add_child(banner_pad)
	_stage.add_child(banner)
	# 先按内容撑开量出高度，再定位（Label 的高度取决于字体，不能硬编码）
	banner.size = Vector2(px(banner_w), 0.0)
	banner.custom_minimum_size.x = px(banner_w)
	var banner_h := maxf(px(30.0 + 26.0 + 58.0 * 1.2), banner.get_combined_minimum_size().y)
	banner.size = Vector2(px(banner_w), banner_h)
	banner.position = Vector2(px(banner_x), px(stack_top))
	banner.add_child(hair)

	# 瓦顶骑在标题牌上沿（CSS：宽 560、top:-46、水平居中；SVG viewBox 540 → 缩放 560/540）
	_stage.add_child(_mk_deco(DECO.Kind.ROOF,
		stack_left + (stack_width - 560.0) * 0.5, stack_top - 46.0, px(560.0 / 540.0)))

	# --- 菜单牌 ---
	var menu_w := 500.0
	var menu_x := stack_left + (stack_width - menu_w) * 0.5
	var menu_top := stack_top + banner_h / DESIGN_SCALE + 22.0
	var menu := PanelContainer.new()
	menu.add_theme_stylebox_override(
		"panel", _flat(col("cream"), col("ink"), 3.0, met("radiusMd", 10.0), true))
	var menu_pad := MarginContainer.new()
	for side in ["left", "right"]:
		menu_pad.add_theme_constant_override("margin_" + side, int(px(56.0)))
	menu_pad.add_theme_constant_override("margin_top", int(px(36.0)))
	menu_pad.add_theme_constant_override("margin_bottom", int(px(32.0)))
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", int(px(10.0)))
	var row: HBoxContainer = null
	var pending: Array = []     # 攒到一起再加，避免 Container 反复重排
	for item in ts.get("menu", []):
		var variant := str(item.get("variant", "primary"))
		var btn := _mk_button(str(item.get("label", "")), variant)
		btn.custom_minimum_size.y = px(54.0)
		var id := str(item.get("id", ""))
		btn.pressed.connect(_on_menu.bind(id))
		if variant == "secondary":
			# 次级按钮两两并排一行（CSS：.title-screen__row，2 列等宽）
			if row == null or row.get_child_count() >= 2:
				row = HBoxContainer.new()
				row.add_theme_constant_override("separation", int(px(10.0)))
				pending.append(row)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(btn)
			continue
		pending.append(btn)
	for node in pending:
		menu_box.add_child(node)
	menu_pad.add_child(menu_box)
	menu.add_child(menu_pad)
	_stage.add_child(menu)
	menu.size = Vector2(px(menu_w), menu.get_combined_minimum_size().y)
	menu.position = Vector2(px(menu_x), px(menu_top))

	# 菜单牌顶上的小宝石（CSS：top:-17、水平居中；SVG viewBox 30 → 1:1 渲染）
	_stage.add_child(_mk_deco(DECO.Kind.GEM, menu_x + (menu_w - 30.0) * 0.5, menu_top - 17.0, px(1.0)))


func _on_menu(id: String) -> void:
	match id:
		"new", "continue", "load":
			# TODO: continue / load 需要先 GET /api/v1/sessions/{id} 恢复进度，再决定去哪一屏
			_goto_intro(0)
		"exit":
			get_tree().quit()
		_:
			print("[IntroSequence] 菜单「%s」还没有实现" % id)


# ------------------------------------------------------------------ 开场屏（第 2 屏）

## 木框 + 羊皮纸：外层深棕木框（圆角 16、内边距 16），里面一张羊皮纸（圆角 6）
## 参考图的关键是**内外色差**：外框深棕、内容米黄，别把外框也做成米黄。
func _mk_parchment_frame() -> Control:
	# .frame：inset 108px 70px 48px
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	frame.position = Vector2(px(70.0), px(108.0))
	frame.size = Vector2(px(1600.0 - 140.0), px(900.0 - 108.0 - 48.0))
	frame.add_theme_stylebox_override(
		"panel", _flat(col("wood"), col("woodDark"), 3.0, met("radiusLg", 16.0)))

	var frame_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		frame_pad.add_theme_constant_override("margin_" + side, int(px(16.0)))

	# .frame__paper：内层浅木色（padding 8）
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override(
		"panel", _flat(col("woodLight"), Color(0, 0, 0, 0), 0.0, met("radiusMd", 10.0)))
	var paper_pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		paper_pad.add_theme_constant_override("margin_" + side, int(px(8.0)))

	# .frame__paper-inner：真正的羊皮纸（padding 16px 22px + 2px 描边 + 内圈细线）
	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override(
		"panel", _flat(col("cream"), col("ink"), 2.0, met("radiusSm", 6.0)))
	# ⚠ 这个节点名字被 tools/verify_intro.gd 断言（find_child("Parchment")），改名会挂验收
	var inner_pad := MarginContainer.new()
	inner_pad.name = "Parchment"
	for side in ["left", "right"]:
		inner_pad.add_theme_constant_override("margin_" + side, int(px(22.0)))
	for side in ["top", "bottom"]:
		inner_pad.add_theme_constant_override("margin_" + side, int(px(16.0)))

	# ⚠ 内圈细描边必须挂在 inner 上，**不能**挂进 Parchment：挂进去它就成了 Parchment
	#   的第 0 个子节点，tools/verify_intro.gd 就找不到内容列了。
	#   PanelContainer 会把子节点拉伸到内容区，holder 铺满、里面的 Panel 再缩 7px，
	#   正好等于 CSS 的 ::before（inset 7px），也不需要额外容器。
	inner.add_child(_mk_hairline())
	inner.add_child(inner_pad)
	frame.add_child(frame_pad)
	frame_pad.add_child(paper)
	paper.add_child(paper_pad)
	paper_pad.add_child(inner)
	return frame


## 羊皮纸内圈那圈细描边（CSS 的 ::before，inset 7px）
func _mk_hairline() -> Control:
	var holder := Control.new()
	holder.name = "Hairline"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = px(7.0)
	panel.offset_top = px(7.0)
	panel.offset_right = -px(7.0)
	panel.offset_bottom = -px(7.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := col("ink")
	panel.add_theme_stylebox_override(
		"panel", _flat(Color(0, 0, 0, 0), Color(ink.r, ink.g, ink.b, 0.32), 2.0, met("radiusXs", 4.0)))
	holder.add_child(panel)
	return holder


## 整屏外壳：木框 + 羊皮纸 + 钟楼 + 三处藤叶，摆在世界地图背景之上
func _build_shell() -> Control:
	var shell := Control.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_bg(shell, TOWN_MAP, col("green"))

	var frame := _mk_parchment_frame()
	shell.add_child(frame)

	# 钟楼骑在外框上沿正中（CSS：top:-40、渲染宽 106；SVG viewBox 124 → 缩放 106/124）
	shell.add_child(_mk_deco(DECO.Kind.CREST, 800.0 - 53.0, 108.0 - 40.0, px(106.0 / 124.0)))
	# 藤叶：左下 / 右上（镜像）/ 右下（小一号）；SVG viewBox 54 → 渲染 56/48
	shell.add_child(_mk_deco(DECO.Kind.LEAF, 70.0 - 10.0, 108.0 + 744.0 - 56.0 - 10.0 + 10.0, px(56.0 / 54.0)))
	shell.add_child(_mk_deco(DECO.Kind.LEAF, 1530.0 - 56.0 - 10.0 + 10.0, 108.0 - 8.0 + 8.0, px(56.0 / 54.0), true))
	shell.add_child(_mk_deco(DECO.Kind.LEAF, 1530.0 - 48.0 - 10.0 + 10.0, 108.0 + 744.0 - 48.0 - 8.0 + 8.0, px(48.0 / 54.0)))
	return shell


func _goto_intro(page: int) -> void:
	_clear_stage()
	_screen = "intro"
	_stage = _build_shell()
	add_child(_stage)

	var ins: Dictionary = _d.get("introScreen", {})
	var pages: Array = ins.get("pages", [])
	if pages.is_empty():
		push_error("intro.json 里没有 pages")
		return
	_page = clampi(page, 0, pages.size() - 1)
	var page_data: Dictionary = pages[_page]

	# ⚠ Parchment 不是 _stage 的直接子节点：外壳层级是
	#   木框 → 内边距 → 浅木纸 → 内边距 → 羊皮纸(PanelContainer) → MarginContainer("Parchment")
	#   所以必须用 find_child 递归找。用 get_node("Parchment") 会返回 null，
	#   下一行 add_child 直接报错，整屏内容（页签/正文/footer）全都建不出来。
	#   owned=false 是因为这些节点都是代码 new 出来的，没有 owner。
	var parchment: MarginContainer = _stage.find_child("Parchment", true, false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(px(0.0)))
	parchment.add_child(column)

	# 顶栏：返回 / 标题条 / 状态牌（CSS：高 50、间距 16）
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(px(16.0)))
	var back_wrap := Control.new()
	back_wrap.custom_minimum_size = Vector2(px(168.0), px(50.0))
	var back := _mk_button("返回", "secondary")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.pressed.connect(_on_back)
	back_wrap.add_child(back)
	top.add_child(back_wrap)

	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_stylebox_override(
		"panel", _flat(col("creamLight"), col("ink"), 2.0, met("radiusSm", 6.0)))
	var t_lb := _mk_label("认识小熊镇", 24.0, col("ink"), HORIZONTAL_ALIGNMENT_CENTER, 5.0)
	var s_lb := _mk_label("先了解这里怎么过，再决定怎么开始", 12.0, col("brownText"),
		HORIZONTAL_ALIGNMENT_CENTER, 1.0)
	titles.add_child(t_lb)
	titles.add_child(s_lb)
	top.add_child(titles)

	var status := PanelContainer.new()
	status.custom_minimum_size = Vector2(px(112.0), px(50.0))
	status.add_theme_stylebox_override(
		"panel", _flat(col("green"), col("ink"), 2.0, met("radiusSm", 6.0)))
	var st_lb := _mk_label("L1 新人", 15.0, col("titleOnWood"), HORIZONTAL_ALIGNMENT_CENTER, 1.0)
	st_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_child(st_lb)
	top.add_child(status)

	top.custom_minimum_size.y = px(50.0)
	column.add_child(top)

	# 顶部页签（参考图里很小很矮）
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", int(px(8.0)))
	var tabs_pad := MarginContainer.new()
	tabs_pad.add_theme_constant_override("margin_top", int(px(12.0)))
	tabs_pad.add_child(tabs)
	for i in pages.size():
		var p: Dictionary = pages[i]
		var lb := _mk_label(str(p.get("tab", "")), 15.0,
			col("titleOnWood") if i == _page else col("ink"), HORIZONTAL_ALIGNMENT_CENTER, 2.0)
		var tab := PanelContainer.new()
		tab.add_theme_stylebox_override("panel", _flat(
			col("brick") if i == _page else col("creamLight"), col("ink"), 2.0, met("radiusSm", 6.0)))
		tab.custom_minimum_size = Vector2(0.0, px(36.0))
		var tab_pad := MarginContainer.new()
		for side in ["left", "right"]:
			tab_pad.add_theme_constant_override("margin_" + side, int(px(22.0)))
		var tab_lb := lb
		tab_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tab_pad.add_child(tab_lb)
		tab.add_child(tab_pad)
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		tab.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_goto_intro(idx))
		tabs.add_child(tab)
	column.add_child(tabs_pad)

	# 主体（高度按设计稿扣出来：羊皮纸内容区 664 - 顶栏50 - 页签(12+36) - 页码(10+32) - 页脚(12+44)）
	var body_wrap := MarginContainer.new()
	body_wrap.add_theme_constant_override("margin_top", int(px(14.0)))
	body_wrap.custom_minimum_size.y = px(454.0)
	body_wrap.add_child(_build_cast_page() if bool(page_data.get("cast", false)) else _build_article_page(page_data))
	column.add_child(body_wrap)

	# 页码
	var pager_pad := MarginContainer.new()
	pager_pad.add_theme_constant_override("margin_top", int(px(10.0)))
	var pager_row := HBoxContainer.new()
	pager_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pager_row.add_child(_mk_plate(_mk_label("%d / %d" % [_page + 1, pages.size()], 14.0, col("ink"))))
	pager_pad.add_child(pager_row)
	column.add_child(pager_pad)

	# 页脚：提示 / 上一页 / 跳过 / 继续
	var footer_pad := MarginContainer.new()
	footer_pad.add_theme_constant_override("margin_top", int(px(12.0)))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", int(px(16.0)))
	footer.custom_minimum_size.y = px(44.0)
	var hint := _mk_plate(_mk_label(str(ins.get("footerHint", "")), 15.0, col("brownText")), 8.0)
	hint.custom_minimum_size = Vector2(px(330.0), px(44.0))
	footer.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var is_last := _page == pages.size() - 1
	var prev := _mk_button("上一页", "secondary")
	prev.custom_minimum_size = Vector2(px(120.0), px(44.0))
	prev.disabled = _page == 0
	prev.pressed.connect(func() -> void: _goto_intro(_page - 1))
	footer.add_child(prev)
	var skip := _mk_button("跳过", "secondary")
	skip.custom_minimum_size = Vector2(px(120.0), px(44.0))
	skip.pressed.connect(_on_done)
	footer.add_child(skip)
	var main_btn := _mk_button(str(ins.get("doneLabel", "继续")) if is_last else "继续", "primary")
	main_btn.custom_minimum_size = Vector2(px(320.0), px(44.0))
	main_btn.pressed.connect(_on_footer_button.bind(is_last))
	footer.add_child(main_btn)
	footer_pad.add_child(footer)
	column.add_child(footer_pad)


func _build_article_page(page_data: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(18.0)))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", int(px(14.0)))
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_col.add_theme_stylebox_override(
		"panel", _flat(col("creamLight"), col("ink"), 2.0, met("radiusSm", 6.0)))
	var text_pad := MarginContainer.new()
	for side in ["left", "right"]:
		text_pad.add_theme_constant_override("margin_" + side, int(px(30.0)))
	for side in ["top", "bottom"]:
		text_pad.add_theme_constant_override("margin_" + side, int(px(26.0)))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(px(8.0)))
	inner.add_child(_mk_label(str(page_data.get("kicker", "")), 14.0, col("brownText"), HORIZONTAL_ALIGNMENT_LEFT, 2.0))
	inner.add_child(_mk_label(str(page_data.get("title", "")), 42.0, col("ink"), HORIZONTAL_ALIGNMENT_LEFT, 6.0))
	# 段落宽度：羊皮纸内容区 1368 - 插图 450 - 间距 18 - 文本框左右内边距 60 = 840（设计稿像素）
	for para in page_data.get("body", []):
		inner.add_child(_mk_label(str(para), 18.0, col("ink"), HORIZONTAL_ALIGNMENT_LEFT, 0.0,
			Color(0, 0, 0, 0), 0.0, 840.0))
	text_pad.add_child(inner)
	text_col.add_child(text_pad)
	row.add_child(text_col)

	# 右侧插图位：美术没到位就留一块空羊皮纸，尺寸稳定不跳版
	var art_holder := PanelContainer.new()
	art_holder.custom_minimum_size = Vector2(px(450.0), px(420.0))
	art_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art_holder.add_theme_stylebox_override(
		"panel", _flat(col("creamLight"), col("ink"), 2.0, met("radiusSm", 6.0)))
	var art_cfg: Dictionary = page_data.get("art", {})
	if not art_cfg.is_empty():
		var art_pad := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			art_pad.add_theme_constant_override("margin_" + side, int(px(6.0)))
		art_pad.add_child(_mk_art(art_cfg))
		art_holder.add_child(art_pad)
	row.add_child(art_holder)
	return row


func _build_cast_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(14.0)))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for who in _cast:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", int(px(6.0)))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override(
			"panel", _flat(col("creamLight"), col("ink"), 2.0, met("radiusSm", 6.0)))
		var card_pad := MarginContainer.new()
		for side in ["left", "right"]:
			card_pad.add_theme_constant_override("margin_" + side, int(px(16.0)))
		card_pad.add_theme_constant_override("margin_top", int(px(28.0)))
		card_pad.add_theme_constant_override("margin_bottom", int(px(20.0)))
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", int(px(4.0)))

		# 头像：裁纸娃娃图集（第 1 行朝下、第 1 列站立帧），像素图用 nearest
		var portrait_row := HBoxContainer.new()
		portrait_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var portrait := PanelContainer.new()
		portrait.custom_minimum_size = Vector2(px(112.0), px(112.0))
		portrait.add_theme_stylebox_override("panel", _flat(col("cream"), col("ink"), 2.0, 56.0))
		var p_cfg := _portrait_cfg(who)
		if not p_cfg.is_empty():
			portrait.add_child(_mk_art(p_cfg))
		portrait_row.add_child(portrait)
		body.add_child(portrait_row)

		body.add_child(_mk_label(str(who.get("name", "")), 24.0, col("ink"), HORIZONTAL_ALIGNMENT_CENTER, 3.0))
		body.add_child(_mk_label(str(who.get("role", "")), 14.0, col("brownText"), HORIZONTAL_ALIGNMENT_CENTER, 1.0))
		body.add_child(_mk_label(str(who.get("place", "")), 13.0, col("brownText"), HORIZONTAL_ALIGNMENT_CENTER, 0.0))
		# 台词宽度：卡片 = (1368 - 4×间距14) / 5 ≈ 262，再扣左右内边距 32 → 230（设计稿像素）
		var line_lb := _mk_label(str(who.get("line", "")), 14.0, col("ink"),
			HORIZONTAL_ALIGNMENT_CENTER, 0.0, Color(0, 0, 0, 0), 0.0, 230.0)
		line_lb.custom_minimum_size.y = px(96.0)
		body.add_child(line_lb)
		if str(who.get("note", "")) != "":
			var badge_row := HBoxContainer.new()
			badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
			badge_row.add_child(_mk_plate(_mk_label(str(who["note"]), 12.0, col("brick")), 6.0))
			body.add_child(badge_row)
		card_pad.add_child(body)
		card.add_child(card_pad)
		row.add_child(card)
	return row


func _on_back() -> void:
	_show_title()


func _on_done() -> void:
	_on_footer_button(true)


func _on_footer_button(is_last: bool) -> void:
	if not is_last:
		_goto_intro(_page + 1)
		return
	# 开场走完 → 交还给地图场景
	var next_id := str(_d.get("nextScreen", {}).get("id", "game"))
	print("[IntroSequence] 开场结束，切到 %s（res://Main.tscn）" % next_id)
	get_tree().change_scene_to_file("res://Main.tscn")
