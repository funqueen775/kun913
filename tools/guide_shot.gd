extends Node2D

## 地面引导线 + 左上角任务卡的开窗验收：四张状态图 + 一张特写。
## 用法：<godot> --path <proj> --resolution 1920x1080 res://tools/guide_shot.tscn
##
## 拍完要看的是三件事：
##   1) 引导线是不是真的沿着道路绕，而不是从池塘上直穿过去；
##   2) 线是不是"贴在地上"（在角色脚下），终点落在区域入口的黄色菱形上；
##   3) 左上角任务卡在花花绿绿的地图上够不够显眼、有没有和别的东西叠字。
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"

var _town: Node2D
var _camera: Camera2D


func _ready() -> void:
	_town = load("res://Main.tscn").instantiate()
	add_child(_town)
	await _wait(1.3)

	# 开局在黑屏宿舍里，先按真实流程出门，否则拍到的是一块遮罩。
	_town._on_dorm_leave()
	await _wait(0.4)

	# 冻结小镇逻辑：NPC 停住、相机不再跟着玩家，方便逐格取景。
	# 只停物理帧；GroundGuideLine 的虚线流动在它自己的 _process 上，照常跑。
	_town.set_physics_process(false)
	_camera = _town._camera
	if _camera == null:
		push_error("拿不到小镇相机")
		get_tree().quit()
		return
	_camera.position_smoothing_enabled = false

	# 1) 未到点：卡片报出下一件事和时间，但**地面上一条线都不画**。
	#    开局"出门"这个动作会点火触发 E01（见 _on_dorm_leave），时钟随即停在事件上，
	#    所以默认是救火态。这里先把时钟放回去，专门拍"还没到点"的样子 ——
	#    这张图是拿来对照的：两个月后的安排不该在地上拖一条线。
	WorldClock.set_running(true)
	_town._refresh_objective_hint()
	_town._refresh_guide_line(true)
	await _wait(0.3)
	_place_camera_between(_town._player.position, _town._zone_by_code("B")["entrance"], 1.15)
	await _shot("guide_01_upcoming")

	# 2) 拉远看全貌：确认整条线是沿路绕的，没有斜穿心湖。
	#    zoom 只能取 1.0：再小视野就超过 1920x1080，画面四周会露出灰底
	#    （游戏里由相机的覆盖系数兜住，截图脚本直接把 zoom 塞给相机会绕过那层）。
	_camera.zoom = Vector2.ONE
	_camera.position = Vector2(960, 540)
	await _shot("guide_02_wide")

	# 3) 到点态：主线事件已经等在 B 区，卡片和线一起换成橙金。
	WorldClock.running = false
	WorldClock.world_minute = 9 * 60
	_town._refresh_objective_hint()
	_town._refresh_guide_line(true)
	await _wait(0.5)
	_place_camera_between(_town._player.position, _town._zone_by_code("B")["entrance"], 1.15)
	await _shot("guide_03_urgent")

	# 4) 自由活动：选了 D 树影书院，线改指 D 区。
	WorldClock.running = true
	WorldClock.world_minute = 3 * 30 * 24 * 60 + 9 * 60
	_town._on_free_zone_focused("D_树影书院")
	await _wait(0.4)
	_place_camera_between(_town._player.position, _town._zone_by_code("D")["entrance"], 1.4)
	await _shot("guide_04_free_time")

	# 5) 特写：贴着玩家看线的质感——起点在脚下、虚线、流向箭头、贴地的投影带。
	#    取景要同时罩住玩家和线拐向南路的那一段，否则只能拍到一条边。
	_camera.zoom = Vector2.ONE * 2.0
	_camera.position = Vector2(470, 660)
	await _shot("guide_05_detail")

	print("guide_shot done")
	get_tree().quit()


## 把相机摆在两点之间，让整条引导线进画面。
func _place_camera_between(from: Vector2, to: Vector2, zoom: float) -> void:
	_camera.zoom = Vector2.ONE * zoom
	_camera.position = (from + to) * 0.5 + Vector2(0, 40)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
