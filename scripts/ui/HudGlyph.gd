extends Control
## 右上角圆钮的矢量小图标（2026-09-17 晚：用户嫌单字圆钮丑，换成图形）。
## kind 直接用 defs 里的汉字标识：力=闪电（精力）/ 忆=相片（记忆墙）/
## 账=手账本（周末手账）/ 设=齿轮（设置）。画布 48x48 与圆钮同大，
## 图标主体约 26px 居中；配色贴 HUD 色板（暖金 / 橙 / 金 / 深棕描边）。
## 刻意不加 class_name：探针与 WorkplaceTown 都走 preload（理由同 _memory_wall）。

const COLOR_MAIN := Color("ffe5a8")
const COLOR_ACCENT := Color("ef9f27")
const COLOR_MID := Color("d49a4c")
const COLOR_OUTLINE := Color("23170f")

var kind := "设"


func _draw() -> void:
	match kind:
		"生":
			_draw_heart()
		"力":
			_draw_bolt()
		"忆":
			_draw_photo()
		"账":
			_draw_book()
		"设":
			_draw_gear()
		"信":
			_draw_envelope()
		"处":
			_draw_steps()
		_:
			_draw_gear()


## 信 = 信封：NPC 主动消息的收件箱（机制文档 §2「有人记得我」）。
## 外框 + V 形封口，封口线用中间色——和手账本的记录线同一套配色。
func _draw_envelope() -> void:
	draw_rect(Rect2(11, 15, 26, 19), COLOR_MAIN, false, 2.5)
	var flap := PackedVector2Array([
		Vector2(11, 15), Vector2(24, 26), Vector2(37, 15),
	])
	draw_polyline(flap, COLOR_MID, 2.0, true)


## 生 = 爱心：「生活」钮（精力 / 周末 / 熊友三页合一，2026-09-18 拍板）。
## 爱心 = 生活与关系的总隐喻：两圆一三角拼成，橙填充 + 深棕描边。
## ⚠ 两个圆的描边只画外弧，避免和三角的交叠线打架（draw_arc 的起止角算过）。
func _draw_heart() -> void:
	var left := Vector2(18.5, 19.5)
	var right := Vector2(29.5, 19.5)
	draw_circle(left, 6.2, COLOR_ACCENT)
	draw_circle(right, 6.2, COLOR_ACCENT)
	var tip := PackedVector2Array([
		Vector2(12.7, 22.5), Vector2(35.3, 22.5), Vector2(24.0, 37.0),
	])
	draw_colored_polygon(tip, COLOR_ACCENT)
	var outline := tip.duplicate()
	outline.append(tip[0])
	draw_polyline(outline, COLOR_OUTLINE, 2.0, true)
	draw_arc(left, 6.2, PI * 0.75, PI * 1.9, 16, COLOR_OUTLINE, 2.0, true)
	draw_arc(right, 6.2, PI * 1.1, PI * 2.25, 16, COLOR_OUTLINE, 2.0, true)


## 力 = 闪电：能量/精力的通用符号，橙填充 + 深棕描边。
func _draw_bolt() -> void:
	var pts := PackedVector2Array([
		Vector2(27, 7), Vector2(16, 25), Vector2(22, 25),
		Vector2(20, 41), Vector2(32, 20), Vector2(25, 20), Vector2(30, 7),
	])
	draw_colored_polygon(pts, COLOR_ACCENT)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, COLOR_OUTLINE, 2.0, true)


## 忆 = 相片：相框 + 太阳 + 两座山，「记忆墙」的图画隐喻。
func _draw_photo() -> void:
	draw_rect(Rect2(11, 14, 26, 21), COLOR_MAIN, false, 2.5)
	draw_circle(Vector2(18.5, 20), 2.4, COLOR_ACCENT)
	var hills := PackedVector2Array([
		Vector2(13, 33), Vector2(21, 23), Vector2(26, 28),
		Vector2(30, 24), Vector2(35, 33),
	])
	draw_colored_polygon(hills, COLOR_MID)


## 账 = 手账本：本子 + 顶部装订环 + 三条记录线，对应「周末手账」。
func _draw_book() -> void:
	draw_rect(Rect2(15, 12, 18, 25), COLOR_MAIN, false, 2.5)
	draw_arc(Vector2(20, 12), 2.4, 0, TAU, 20, COLOR_ACCENT, 2.0, true)
	draw_arc(Vector2(28, 12), 2.4, 0, TAU, 20, COLOR_ACCENT, 2.0, true)
	for y in [20, 25, 30]:
		draw_line(Vector2(19.5, float(y)), Vector2(28.5, float(y)), COLOR_MID, 2.0)


## 处 = 阶梯：三级台阶 + 最高一级上的小圆点（你站在哪儿）。
## 「你的处境」这一页的隐喻：稳定 / 观察 / 危急本来就是一级级上去的，
## 而且看得见自己在哪一级 —— 正对剧情册 §2.4 的明示原则。
## ⚠ 顶点顺序必须是「绕一圈的简单多边形」：8 个点首尾相接、不许有共线重叠的边。
## 2026-09-18 首版写成 6 点且缺底边，draw_colored_polygon 直接报
## "Invalid polygon data, triangulation failed"（三角化失败，图标整只不画）。
func _draw_steps() -> void:
	var treads := PackedVector2Array([
		Vector2(11, 35), Vector2(11, 30),
		Vector2(20, 30), Vector2(20, 22),
		Vector2(29, 22), Vector2(29, 14),
		Vector2(38, 14), Vector2(38, 35),
	])
	draw_colored_polygon(treads, COLOR_MAIN)
	var outline := treads.duplicate()
	outline.append(treads[0])
	draw_polyline(outline, COLOR_OUTLINE, 2.0, true)
	# 站在最高一级上的那个点：底边正好贴住台阶面（y=14）。
	draw_circle(Vector2(33.5, 11.0), 3.0, COLOR_ACCENT)


## 设 = 齿轮：8 齿 + 盘体 + 中心孔，设置的通用符号。
func _draw_gear() -> void:
	var center := Vector2(24, 24)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		var p1 := center + dir * 7.0 + side * 3.0
		var p2 := center + dir * 12.5 + side * 3.0
		var p3 := center + dir * 12.5 - side * 3.0
		var p4 := center + dir * 7.0 - side * 3.0
		draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), COLOR_MAIN)
	draw_circle(center, 8.5, COLOR_MAIN)
	draw_arc(center, 4.0, 0, TAU, 24, COLOR_OUTLINE, 2.0, true)
