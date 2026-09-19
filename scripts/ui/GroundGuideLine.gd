class_name GroundGuideLine
extends Node2D
## 地面引导线：从玩家脚下沿道路铺到目标地点。
##
## 为什么整条线都用 _draw() 画、不用贴图或 SVG：路径长度和拐点每帧都在变，
## 只能程序化生成；而且 headless 下不处理 SVG（同 TornBubble 的理由）。
##
## 四层叠出"贴在地面上"而不是"浮在空中"的观感：
##   1) 投影带 —— 路径下方一条更宽的半透明暗色，像压在地面的阴影；
##   2) 底光带 —— 低透明度暖黄宽线，给虚线垫底，拐弯处不会露出空隙；
##   3) 流动虚线 + 箭头 —— 沿弧长参数化，随时间向前滚动，指示前进方向；
##   4) 终点光环 —— 呼吸扩散的圆环，落点在目标区域入口。

## 常态：暖黄。跟入口标记（fff500）同色系，玩家一眼能连起来。
const BASE_COLOR := Color("ffd24a")
## 到点态：主线事件已经等在区域里，玩家不去就推进不下去 —— 换成更亮的橙金、流速更快。
const ALERT_COLOR := Color("ffab35")
## 投影带颜色：不用纯黑，带一点冷色，压在暖色地砖上更像阴影。
const SHADOW_COLOR := Color(0.04, 0.07, 0.10, 0.26)

const DASH_LENGTH := 26.0
const DASH_GAP := 20.0
const FLOW_SPEED := 96.0
const ALERT_FLOW_SPEED := 176.0
## 弧长小于这个值就不画了：起点终点几乎重合时画出来是一团污渍。
const MIN_VISIBLE_LENGTH := 26.0

var _points: PackedVector2Array = PackedVector2Array()
## 每个顶点的累计弧长，用来把"距起点 s 米"换算成折线上的坐标。
var _cumulative := PackedFloat32Array()
var _total_length := 0.0
var _flow := 0.0
var _urgent := false
var _has_path := false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _has_path:
		return
	# 虚线相位只往前走：世界坐标里的虚线位置因此稳定，不会随帧率抖动。
	var period := DASH_LENGTH + DASH_GAP
	_flow = fmod(_flow + delta * (ALERT_FLOW_SPEED if _urgent else FLOW_SPEED), period)
	queue_redraw()


## 铺一条新路径。points 至少两个点，世界坐标。
func set_path(points: PackedVector2Array, urgent: bool = false) -> void:
	_points = points
	_urgent = urgent
	_flow = 0.0
	_rebuild_metrics()
	_has_path = _total_length >= MIN_VISIBLE_LENGTH
	queue_redraw()


## 起点每帧跟着玩家挪。只改首点、只重算弧长，不重跑寻路 —— 便宜且没有相位跳变。
func set_origin(position: Vector2) -> void:
	if _points.size() < 2:
		return
	if _points[0].distance_to(position) < 0.5:
		return
	_points[0] = position
	_rebuild_metrics()
	_has_path = _total_length >= MIN_VISIBLE_LENGTH
	queue_redraw()


func clear() -> void:
	if _points.is_empty() and not _has_path:
		return
	_points = PackedVector2Array()
	_cumulative = PackedFloat32Array()
	_total_length = 0.0
	_flow = 0.0
	_has_path = false
	queue_redraw()


func is_guiding() -> bool:
	return _has_path


func _rebuild_metrics() -> void:
	_cumulative = PackedFloat32Array()
	_total_length = 0.0
	if _points.size() < 2:
		return
	_cumulative.append(0.0)
	for index in _points.size() - 1:
		_total_length += _points[index].distance_to(_points[index + 1])
		_cumulative.append(_total_length)


func _draw() -> void:
	if not _has_path or _points.size() < 2:
		return
	var tint := ALERT_COLOR if _urgent else BASE_COLOR
	# 1) 投影带。宽度比其他层都大，让整条线看起来躺在地上。
	draw_polyline(_points, SHADOW_COLOR, 31.0, true)
	# 2) 底光带。拐弯处它负责把虚线的空隙填上，所以必须够宽。
	draw_polyline(_points, Color(tint.r, tint.g, tint.b, 0.30 if _urgent else 0.22), 22.0, true)
	# 3) 流动虚线 + 高亮芯。单色实线压在小镇底图上会糊成一团，
	#    彩色外圈 + 近白内芯才有"发光的路标"感。
	var period := DASH_LENGTH + DASH_GAP
	var highlight := Color(minf(tint.r + 0.22, 1.0), minf(tint.g + 0.22, 1.0), minf(tint.b + 0.40, 1.0), 1.0)
	var cursor := -_flow
	while cursor < _total_length:
		var finish := minf(cursor + DASH_LENGTH, _total_length)
		if finish > 0.0:
			var head := _point_at(maxf(cursor, 0.0))
			var tail := _point_at(finish)
			draw_line(head, tail, Color(tint.r, tint.g, tint.b, 0.96), 11.0, true)
			draw_line(head, tail, highlight, 4.0, true)
		cursor += period
	# 4) 方向箭头：每两个虚线周期插一个，落在虚线中点上才不显挤。
	cursor = -_flow + period * 0.5
	while cursor < _total_length:
		if cursor > DASH_LENGTH * 0.5:
			_draw_arrow(cursor, tint)
		cursor += period * 2.0
	# 5) 终点光环。
	_draw_target(_points[_points.size() - 1], tint)


func _draw_arrow(arc_length: float, tint: Color) -> void:
	var head := _point_at(arc_length)
	var direction := _tangent_at(arc_length)
	if direction == Vector2.ZERO:
		return
	var side := Vector2(-direction.y, direction.x)
	var tip := head + direction * 13.0
	var left := head - direction * 10.0 + side * 11.0
	var right := head - direction * 10.0 - side * 11.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1.0, 1.0, 0.94, 1.0))
	draw_polyline(PackedVector2Array([left, tip, right]), Color(tint.r, tint.g, tint.b, 0.98), 3.0, true)


func _draw_target(position: Vector2, tint: Color) -> void:
	# 光环跟着 _process 的节奏呼吸；周期与入口菱形标记尽量错开，看着不呆。
	var pulse := (sin(Time.get_ticks_msec() * 0.0055) + 1.0) * 0.5
	var ring_radius := 30.0 + pulse * 9.0
	draw_circle(position, ring_radius, Color(tint.r, tint.g, tint.b, 0.18))
	draw_arc(position, ring_radius, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, 0.68), 4.0, true)
	draw_circle(position, 14.0, Color(tint.r, tint.g, tint.b, 0.94))
	draw_circle(position, 6.0, Color(1.0, 0.98, 0.90, 1.0))


## 折线上距起点 arc_length 处的坐标。
func _point_at(arc_length: float) -> Vector2:
	var clamped := clampf(arc_length, 0.0, _total_length)
	for index in _points.size() - 1:
		var start := _cumulative[index]
		var finish := _cumulative[index + 1]
		if clamped <= finish or index == _points.size() - 2:
			var span := finish - start
			if span <= 0.0001:
				return _points[index]
			return _points[index].lerp(_points[index + 1], (clamped - start) / span)
	return _points[_points.size() - 1]


## 折线上该处的单位切向。落在顶点上时取相邻较长的一段，避免方向突变。
func _tangent_at(arc_length: float) -> Vector2:
	var clamped := clampf(arc_length, 0.0, _total_length)
	for index in _points.size() - 1:
		var start := _cumulative[index]
		var finish := _cumulative[index + 1]
		if clamped > finish and index != _points.size() - 2:
			continue
		var direction := _points[index + 1] - _points[index]
		if direction.length() > 0.001:
			return direction.normalized()
		return Vector2.ZERO
	return Vector2.ZERO
