extends Node
## 验收脚本：地图自由放大缩小 + 鼠标拖动平移。
##
## 用法：
##   <godot_gui> --path <PROJ> --resolution 1920x1080 res://tools/verify_map_zoom.tscn
##
## 做的事：加载 Main.tscn，往视口注入滚轮 / 鼠标拖动 / 方向键事件，读回
## _map_zoom_factor、_pan_offset 与 _camera（含 limit 钳制后的实际位置），每个档位存一张 PNG。
## 重点看四件事：
##   1. 滚轮是否真的被收到（倍率是否变化）
##   2. 缩到最小时 zoom 是否 == cover（低于它视野就超出世界，相机 limit 会露出灰底）
##   3. 拖动是否反向平移相机、松手是否保持不回弹、拖到边界是否不越界
##   4. 玩家一有移动输入，视角是否滑回身上
##
## ⚠ 注入坐标会被 stretch 换算：本工程 `window/stretch/mode=canvas_items` + 窗口 1920x1055
## 对应视口 1965x1080（正好差一个 _cover_zoom），所以注入 (400,300) 到脚本里是 (409,307)。
## 不必去对齐这两个坐标系（相对位移是等比的），但对不上时别以为是逻辑错了 ——
## 需要看清时调 `_diagnose_drag_coords()` 打一份对照。

const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/zoomshot"
const WORLD := Vector2(1920, 1080)

var _inst: Node
var _records: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var packed: PackedScene = load("res://Main.tscn")
	if packed == null:
		print("[verify] Main.tscn 加载失败")
		get_tree().quit(1)
		return
	_inst = packed.instantiate()
	add_child(_inst)
	await _settle(20)
	_report("初始")
	await _shot("01_default")

	# ---- 缩放 ----
	await _wheel(MOUSE_BUTTON_WHEEL_UP, 6)
	await _settle(60)
	_report("上滚 6 格")
	await _shot("02_zoom_in")

	await _wheel(MOUSE_BUTTON_WHEEL_DOWN, 30)
	await _settle(60)
	_report("下滚 30 格（撞下限）")
	await _shot("03_zoom_min")

	await _wheel(MOUSE_BUTTON_WHEEL_UP, 40)
	await _settle(60)
	_report("上滚 40 格（撞上限）")
	await _shot("04_zoom_max")

	var reset := InputEventKey.new()
	reset.keycode = KEY_0
	reset.pressed = true
	Input.parse_input_event(reset)
	await _settle(60)
	_report("按 0 复位")
	await _shot("05_reset")

	# ---- 拖动平移 ----
	# 先向右拖：相机左移，画面里的地图跟着手往右走
	await _drag(Vector2(960, 480), Vector2(1160, 480))
	await _settle(30)
	_report("右拖 200px")
	await _shot("06_pan_right")

	await _settle(90)
	_report("松手后静置 90 帧（应保持不动）")

	# 往下猛拖：相机上移，直到「视野下边缘贴住世界下边缘」为止
	await _drag(Vector2(960, 480), Vector2(960, 1060))
	await _drag(Vector2(960, 480), Vector2(960, 1060))
	await _settle(30)
	_report("猛拖到世界下边界")
	await _shot("07_pan_down_edge")

	# 再往上拖回来：这时相机有空间下移了，应当有效（反方向也要能走）
	await _drag(Vector2(960, 900), Vector2(960, 400))
	await _settle(30)
	_report("上拖 500px（往回走）")
	await _shot("08_pan_up")

	# 玩家一动，视角滑回身上
	Input.action_press("move_right")
	await _settle(90)
	Input.action_release("move_right")
	await _settle(60)
	_report("按住方向键 90 帧后（视角应已回中）")
	await _shot("09_pan_recentered")

	# 左下角提示区放大 3 倍，肉眼确认字号 / 对比度（整图缩略后看不清）
	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	var crop := full.get_region(Rect2i(0, maxi(full.get_height() - 280, 0), 900, 130))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	print("[verify] 提示区放大图 err=%d" % crop.save_png("%s/hint_crop.png" % SHOT_DIR))

	_log("---- 全记录结束 ----")
	get_tree().quit()


func _wheel(button: int, times: int) -> void:
	for i in times:
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			ev.pressed = pressed
			ev.position = Vector2(960, 540)
			Input.parse_input_event(ev)
		await get_tree().process_frame


## 诊断：注入的屏幕坐标到了脚本里究竟变成什么（坐标系对不上时唯一能看清的办法）
func _diagnose_drag_coords() -> void:
	_log("诊断：视口=%s 窗口=%s" % [
		get_viewport().get_visible_rect().size, DisplayServer.window_get_size()])
	var dp := InputEventMouseButton.new()
	dp.button_index = MOUSE_BUTTON_LEFT
	dp.pressed = true
	dp.position = Vector2(400, 300)
	Input.parse_input_event(dp)
	await get_tree().process_frame
	_log("诊断 press(400,300) -> origin=%s panning=%s" % [
		_inst.get("_pan_drag_origin"), _inst.get("_is_panning")])
	for step in 2:
		var dm := InputEventMouseMotion.new()
		dm.position = Vector2(400 + (step + 1) * 50, 300)
		dm.relative = Vector2(50, 0)
		Input.parse_input_event(dm)
		await get_tree().process_frame
		var cam: Camera2D = _inst.get("_camera")
		_log("诊断 motion(%d,300) -> offset=%s zoom=%.4f" % [
			400 + (step + 1) * 50, _inst.get("_pan_offset"), cam.zoom.x])
	var dr := InputEventMouseButton.new()
	dr.button_index = MOUSE_BUTTON_LEFT
	dr.pressed = false
	dr.position = Vector2(500, 300)
	Input.parse_input_event(dr)
	await get_tree().process_frame
	_log("诊断 松手 -> panning=%s offset=%s" % [_inst.get("_is_panning"), _inst.get("_pan_offset")])


## 模拟真实拖动：按下 → 分 8 步移动 → 松手
func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	Input.parse_input_event(press)
	await get_tree().process_frame
	for i in 8:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(i + 1) / 8.0)
		motion.relative = (to - from) / 8.0
		Input.parse_input_event(motion)
		await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	Input.parse_input_event(release)
	await get_tree().process_frame


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _report(label: String) -> void:
	if _inst == null:
		return
	var cam: Camera2D = _inst.get("_camera")
	if cam == null:
		_log("%s -> 相机不存在" % label)
		return
	var factor: float = _inst.get("_map_zoom_factor")
	var cover: float = _inst.get("_cover_zoom")
	var offset: Vector2 = _inst.get("_pan_offset")
	var anchor: Vector2 = _inst.call("_camera_anchor")
	# 注意：本脚本根节点是 Node，没有 get_viewport_rect()（那是 CanvasItem 的方法）
	var view: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	# get_screen_center_position() 是「经过 limit 钳制后」真正显示的中心，判越界必须用它
	var center := cam.get_screen_center_position()
	var half := view * 0.5
	var inside := center.x >= half.x - 1.0 and center.x <= WORLD.x - half.x + 1.0 \
		and center.y >= half.y - 1.0 and center.y <= WORLD.y - half.y + 1.0
	_log("%s -> 倍率 %.4f | zoom %.4f | cover %.4f | 视野 %.0fx%.0f | 平移 %s | 锚点 %s | 实际中心 (%.0f,%.0f) | 在界内 %s" % [
		label, factor, cam.zoom.x, cover, view.x, view.y,
		Vector2(snappedf(offset.x, 0.1), snappedf(offset.y, 0.1)),
		Vector2(snappedf(anchor.x, 0.1), snappedf(anchor.y, 0.1)),
		center.x, center.y, "是" if inside else "否（会露灰底）"])


## 崩溃/被强杀时 stdout 会被吞，所以同时落盘
func _log(msg: String) -> void:
	print("[verify] %s" % msg)
	_records.append(msg)
	var f := FileAccess.open("%s/verify_log.txt" % SHOT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_records))
		f.close()


func _shot(key: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, key]
	var err := img.save_png(path)
	print("[verify] 存图 %s err=%d" % [path, err])
