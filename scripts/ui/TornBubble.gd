class_name TornBubble
extends Control

## P5 式撕裂纹理件：不规则多边形 + 粗描边 + 单侧尖角。
##
## 用途：对话气泡（黑底白字）、名字牌（白底黑字，tail 指向说话人）、
## 日期牌（白底黑字，tail 关掉）、选项条（黑底白字，右尖角）。
##
## 形状一律用 _draw() 画，不用 SVG / 贴图：headless 下不处理 SVG 资源，
## 而且这块要跟着窗口尺寸重算，画出来比贴图更稳。

var fill_color := Color(0.05, 0.05, 0.07, 0.94)
var outline_color := Color(0.97, 0.96, 0.92)
var outline_width := 3.0
## left / right / none
var tail_side := "left"
## 尖角在对应边上的位置，0..1
var tail_at := 0.36
var tail_length := 34.0
## 边缘锯齿幅度：0 = 规则矩形。
## 实际幅度自适应收敛到 min(jag, 短边 × 10%)：对话条有一千多像素长，
## 固定 13px 的扰动摊上去会连成直线，看不出撕；而日期牌只有一两百像素，
## 用大件的幅度又会被撕碎。
var jag := 26.0
var shape_seed := 20260916


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var pts := outline_points()
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_color)
	if outline_width > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, outline_color, outline_width, true)


## 轮廓按顺时针走：上 → 右 → 下 → 左，尖角插在指定边的腰部。
## 尖角会画到 rect 之外（x < 0 或 x > size.x），这是刻意的——
## 气泡的角必须伸到画面边缘，才像"从画外刺进来"。
func outline_points() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	if w <= 8.0 or h <= 8.0:
		return PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var j := minf(jag, minf(w, h) * 0.10)
	# 尖角位置按边分别夹取：右边是自上而下走的，尖角不能越过 (w, h*0.44) 那个折点，
	# 否则多边形会自交、填充出缺口。
	var at := h * clampf(tail_at, 0.08, 0.92)
	if tail_side == "right":
		at = h * clampf(tail_at, 0.08, 0.40)
	# 长边按每 ~60px 一个折点来排。
	# 关键教训：折点必须跟边长成比例，不能用固定个数——4 个折点摊在 1180px 的
	# 对话条上，相邻间隔 295px、斜率才 4°，肉眼就是一条直线，出来还是圆角矩形。
	var steps := maxi(2, int(round(w / 60.0)))
	var pts := PackedVector2Array()

	# 上边：x 单调递增，y 怎么抖都不会自交
	pts.append(Vector2(j, 0.0))
	for i in range(1, steps):
		pts.append(Vector2(w * (float(i) / float(steps)), rng.randf_range(-j, j)))
	pts.append(Vector2(w - j * 1.5, 0.0))
	# 右上角
	pts.append(Vector2(w, j))
	# 右边（右尖角就插在这一段）
	if tail_side == "right":
		pts.append(Vector2(w, at - j * 1.4))
		pts.append(Vector2(w + tail_length, at))
		pts.append(Vector2(w, at + j * 1.4))
	else:
		pts.append(Vector2(w, h * 0.44))
	# 右下角
	pts.append(Vector2(w - j * 0.5, h - j * 1.3))
	# 下边：x 单调递减
	pts.append(Vector2(w - j * 1.2, h))
	for i in range(1, steps):
		pts.append(Vector2(w * (1.0 - float(i) / float(steps)), h + rng.randf_range(-j, j)))
	pts.append(Vector2(j * 1.3, h))
	# 左下角
	pts.append(Vector2(0.0, h - j * 1.1))
	# 左边（左尖角就插在这一段；从下往上走）
	if tail_side == "left":
		pts.append(Vector2(0.0, at + j * 1.4))
		pts.append(Vector2(-tail_length, at))
		pts.append(Vector2(0.0, at - j * 1.4))
	# 左上角，回到起点
	pts.append(Vector2(0.0, j))
	return pts
