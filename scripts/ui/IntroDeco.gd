extends Control
## 开场的矢量装饰件：瓦顶 / 宝石 / 钟楼 / 藤叶 / 顶栏图标。
##
## 形状数据照抄 `web/src/components/ui.tsx` 里那几个 SVG（同一套设计稿，参考图里最关键
## 的「贵」感来源就是它们）。**不用 SVG 文件**：Godot 4.3 只在编辑器导入时处理 .svg，
## `--script`/headless 下不会生成 import，工程里多一层资产依赖不值得。
##
## 画法三条：
##   · 填充用 draw_colored_polygon
##   · 描边用 _outline()：逐边 draw_line + 顶点补圆 —— SVG 里 stroke-linejoin 基本都是
##     round，补圆正好等于 round join；直接用 draw_polyline 的直角缺口会很难看
##   · 圆角矩形用 draw_style_box（StyleBoxFlat 原生支持圆角 + 描边）
##
## 坐标一律按 SVG 的 viewBox 画，靠 draw_set_transform 乘 art_scale。

enum Kind { ROOF, GEM, CREST, LEAF, ICON_DOC, ICON_SLIDER, ICON_HELP }

## 各装饰件的 viewBox 尺寸
const VB := {
	Kind.ROOF: Vector2(540, 70),
	Kind.GEM: Vector2(30, 30),
	Kind.CREST: Vector2(124, 96),
	Kind.LEAF: Vector2(54, 54),
	Kind.ICON_DOC: Vector2(32, 32),
	Kind.ICON_SLIDER: Vector2(32, 32),
	Kind.ICON_HELP: Vector2(32, 32),
}

var kind: int = Kind.ROOF
var pal: Dictionary = {}      ## 色名 -> Color（用 intro.json 的 palette）
var art_scale: float = 1.0
var flip: bool = false
var font: Font = null


func setup(p_kind: int, p_pal: Dictionary, p_scale: float, p_flip: bool = false, p_font: Font = null) -> void:
	kind = p_kind
	pal = p_pal
	art_scale = p_scale
	flip = p_flip
	font = p_font
	var vb: Vector2 = VB[kind]
	size = vb * art_scale
	queue_redraw()


func c(name: String, alpha: float = 1.0) -> Color:
	var col: Color = pal.get(name, Color.MAGENTA)
	col.a = alpha
	return col


# ------------------------------------------------------------------ 画图工具

func _fill(pts: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(pts, color)


func _outline(pts: PackedVector2Array, color: Color, w: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	for i in n:
		draw_line(pts[i], pts[(i + 1) % n], color, w, true)
		draw_circle(pts[i], w * 0.5, color)


func _shape(pts: PackedVector2Array, fill: Color, stroke: Color, w: float) -> void:
	if w > 0.0:
		_outline(pts, stroke, w)      # 先描边，再把填充压在上面，边缘更干净
	_fill(pts, fill)


func _round_rect(r: Rect2, fill: Color, stroke: Color, w: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	if w > 0.0:
		sb.border_color = stroke
		sb.set_border_width_all(int(round(w)))
	sb.set_corner_radius_all(int(round(radius)))
	draw_style_box(sb, r)


func _dot(center: Vector2, radius: float, fill: Color, stroke: Color, w: float) -> void:
	if w > 0.0:
		draw_circle(center, radius + w * 0.5, stroke)
	draw_circle(center, radius, fill)


func _path(pts: PackedVector2Array, color: Color, w: float) -> void:
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], color, w, true)
	draw_circle(pts[0], w * 0.5, color)
	draw_circle(pts[pts.size() - 1], w * 0.5, color)


func _pairs(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, raw.size(), 2):
		out.append(Vector2(raw[i], raw[i + 1]))
	return out


# ------------------------------------------------------------------ 绘制入口

func _draw() -> void:
	var s := art_scale
	var xform := Vector2.ZERO
	var xscale := Vector2(s, s)
	if flip:
		xform = Vector2(VB[kind].x * s, 0.0)
		xscale = Vector2(-s, s)
	draw_set_transform(xform, 0.0, xscale)

	match kind:
		Kind.ROOF:
			_draw_roof()
		Kind.GEM:
			_draw_gem()
		Kind.CREST:
			_draw_crest()
		Kind.LEAF:
			_draw_leaf()
		Kind.ICON_DOC:
			_draw_icon_doc()
		Kind.ICON_SLIDER:
			_draw_icon_slider()
		Kind.ICON_HELP:
			_draw_icon_help()


# ------------------------------------------------------------------ 各装饰件

## 瓦顶：骑在标题横幅上沿。参考图标题牌的「房顶」就是它
func _draw_roof() -> void:
	var ink := c("ink")
	var brick := c("brick")
	var brick_dark := c("brickDark")

	# 屋面
	_shape(_pairs([14, 62, 526, 62, 470, 30, 270, 6, 70, 30]), brick, ink, 3.4)
	# 屋面暗色带
	_fill(_pairs([54, 50, 486, 50, 470, 40, 270, 20, 70, 40]), brick_dark)
	# 瓦缝
	draw_line(Vector2(118, 40), Vector2(422, 40), c("ink", 0.5), 2.0, true)
	# 檐口横梁
	_round_rect(Rect2(22, 54, 496, 13), brick_dark, ink, 3.0, 4.0)
	# 正中菱形宝石
	_shape(_pairs([270, 18, 282, 30, 270, 42, 258, 30]), c("titleOnWood"), ink, 2.4)


## 小宝石：菜单牌正中那一颗
func _draw_gem() -> void:
	var ink := c("ink")
	_shape(_pairs([15, 2, 28, 15, 15, 28, 2, 15]), c("orange"), ink, 2.6)
	_shape(_pairs([15, 8, 22, 15, 15, 22, 8, 15]), c("titleOnWood"), ink, 1.8)


## 钟楼：骑在木质外框上沿正中
func _draw_crest() -> void:
	var ink := c("ink")
	_shape(_pairs([14, 50, 62, 12, 110, 50]), c("orange"), ink, 3.2)
	_round_rect(Rect2(8, 47, 108, 12), c("orangeDark"), ink, 3.0, 4.0)
	_round_rect(Rect2(30, 58, 64, 34), c("brick"), ink, 3.0, 3.0)
	_dot(Vector2(62, 34), 13.0, c("titleOnWood"), ink, 3.0)
	# 表针
	draw_line(Vector2(62, 34), Vector2(62, 26), ink, 2.4, true)
	draw_line(Vector2(62, 34), Vector2(69, 38), ink, 2.4, true)
	_round_rect(Rect2(38, 66, 13, 11), c("titleOnWood"), ink, 2.0, 2.0)
	_round_rect(Rect2(73, 66, 13, 11), c("titleOnWood"), ink, 2.0, 2.0)
	_round_rect(Rect2(55, 74, 14, 18), c("wood"), ink, 2.4, 2.0)


## 藤叶：木框四角。参考图里爬满框的花叶，是最重要的质感来源
func _draw_leaf() -> void:
	var ink := c("ink")
	# 叶柄（SVG 的二次贝塞尔 M6 48 Q20 36 26 14，按 6 段折线近似）
	_path(_pairs([6, 48, 9.5, 42.7, 13.1, 37.6, 16.8, 32.7, 20.3, 27.6, 23.4, 21.9, 26, 14]),
		c("leaf"), 3.2)
	_leaf_blade(Vector2(12, 33), 9.0, 5.4, -40.0, c("leaf"), ink)
	_leaf_blade(Vector2(25, 23), 9.0, 5.4, -14.0, c("grass"), ink)
	_leaf_blade(Vector2(17, 44), 8.0, 5.0, -62.0, c("grass"), ink)


func _leaf_blade(center: Vector2, rx: float, ry: float, deg: float, fill: Color, stroke: Color) -> void:
	var pts := PackedVector2Array()
	var a := deg_to_rad(deg)
	for i in 24:
		var t := TAU * float(i) / 24.0
		var p := Vector2(cos(t) * rx, sin(t) * ry).rotated(a) + center
		pts.append(p)
	_shape(pts, fill, stroke, 1.6)


# ------------------------------------------------------------------ 顶栏图标（32x32）

func _draw_icon_doc() -> void:
	var ink := c("ink")
	_shape(_pairs([7, 4, 19, 4, 25, 10, 25, 28, 7, 28]), c("creamLight"), ink, 2.6)
	_path(_pairs([19, 4, 19, 10, 25, 10]), ink, 2.6)
	draw_line(Vector2(11, 16), Vector2(21, 16), ink, 2.4, true)
	draw_line(Vector2(11, 21), Vector2(18, 21), ink, 2.4, true)


func _draw_icon_slider() -> void:
	var ink := c("ink")
	draw_line(Vector2(6, 11), Vector2(26, 11), ink, 2.6, true)
	draw_line(Vector2(6, 21), Vector2(26, 21), ink, 2.6, true)
	_dot(Vector2(12, 11), 4.0, c("creamLight"), ink, 2.6)
	_dot(Vector2(21, 21), 4.0, c("creamLight"), ink, 2.6)


func _draw_icon_help() -> void:
	if font == null:
		return
	var size_px := 26.0
	draw_string(font, Vector2(0, 23), "?", HORIZONTAL_ALIGNMENT_CENTER, 32.0, int(size_px), c("ink"))
