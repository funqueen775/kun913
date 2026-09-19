extends Node2D

## 周末到达演出（2026-09-18 深夜 v3「一格一站」）的开窗验收。
## 用法：<godot>_console --path <proj> --resolution 1920x1080 res://tools/weekend_scene_shot.tscn
##
## 拍完要看的六件事：
##   1) 规划页：排了活动后底部按钮变「出发」；
##   2) 出发后街上：地面引导线 + 湖边落点的青色菱形黄标；
##   3) 走到湖边半径内 → 全屏湖边场景图 + 底部黑条逐字（户外站不需要按 E）；
##   4) 湖边那场演完 → 自动回街，引导改指第二站（H 桌游馆）；
##   5) 进 H 演第二场（桌游局四行 + 逐行换图）；
##   6) 演完进「在场一幕」→ 手账页，收尾与旧链路一致。
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"
const LAKE_SPOT := Vector2(1037, 413)

var _town: Node2D


func _ready() -> void:
	_town = load("res://Main.tscn").instantiate()
	add_child(_town)
	await _wait(1.3)

	_town._on_dorm_leave()
	await _wait(0.5)

	_town.set_physics_process(false)
	WorldClock.set_running(false)

	var panel = _town._free_time_panel
	var scene_panel = _town._weekend_scene_panel
	if panel == null or scene_panel == null:
		push_error("拿不到自由周末面板 / 到达演出面板")
		get_tree().quit()
		return

	# 1) 规划页：第一格湖边独走（户外站）、第二格桌游局（H 区）。
	panel.open_for_month(18)
	await _wait(0.4)
	panel.begin_slot(0)
	panel.choose_zone("心湖")
	panel.choose_activity("S2_lakeside_walk")
	await _wait(0.2)
	panel.begin_slot(1)
	panel.choose_zone("H_慢生活园")
	panel.choose_activity("G3_board_game")
	await _wait(0.3)
	await _shot("weekend_v3_01_plan_depart")

	# 2) 出发 → 街上：引导线与湖边落点黄标。
	panel._depart_for_visit()
	# 截图工具里 WorldClock 还在第 1 月：把队列月份对齐到世界月份，免得跨月守卫清计划。
	_town._weekend_visit = {
		"month": int(WorldClock.snapshot()["month"]),
		"queue": panel.visit_stations(),
		"current": {},
	}
	_town._start_next_weekend_station()
	await _wait(0.5)
	await _shot("weekend_v3_02_guide_to_lake")
	print("diag queue=", _town._weekend_visit.get("queue", []))
	print("diag guide_spot=", _town._free_guide_spot, " marker_visible=", _town._weekend_spot_marker.visible)

	# 3) 走到湖边落点 → 户外站自动开演。
	_town._player.position = LAKE_SPOT + Vector2(20, 10)
	_town._player.velocity = Vector2.ZERO
	await _wait(0.2)
	_town._check_weekend_outdoor_arrival()
	await _wait(0.8)
	print("diag lake scene_open=", scene_panel.is_open())
	await _shot("weekend_v3_03_lake_outdoor_scene")

	# 4) 第一场演完 → 自动回街，引导改指第二站（H）。
	while scene_panel.is_open():
		scene_panel._advance()
	await _wait(0.8)
	await _shot("weekend_v3_04_guide_to_zone")
	print("diag after_lake queue=", _town._weekend_visit.get("queue", []),
		" guide_zone=", _town._free_guide_zone, " in_zone=", _town._active_zone.get("code", ""))

	# 5) 进 H 演第二场（桌游局）。H 区入口在 (375, 465)（慢生活园，地图左侧）。
	_town._player.position = Vector2(375, 470)
	_town._player.velocity = Vector2.ZERO
	_town._update_zone_state()
	await _wait(0.2)
	_town._enter_nearby_zone()
	await _wait(0.8)
	print("diag zone scene_open=", scene_panel.is_open(), " active=", _town._active_zone.get("code", ""))
	await _shot("weekend_v3_05_board_game_scene")
	scene_panel._advance()
	await _wait(0.2)
	await _shot("weekend_v3_06_board_game_line2")
	while scene_panel.is_open():
		scene_panel._advance()
	await _wait(0.8)
	await _shot("weekend_v3_07_encounter")
	if panel._step == "encounter":
		panel.choose_encounter_option("A")
	await _wait(0.6)
	await _shot("weekend_v3_08_ledger")
	if panel._step == "ledger":
		panel._finish_weekend()

	print("weekend_scene_shot done")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
