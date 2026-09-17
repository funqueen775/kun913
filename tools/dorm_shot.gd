extends Control

## 宿舍屏开窗自检：连拍 日常出生 / 走到门口 / 确认框 / 宵禁 / 走到床边 五张图。
## 只 new DormRoom 面板自己 present，不驱动 WorldClock、不碰玩家存档。
## 用法：godot --path <proj> --resolution 1920x1080 res://tools/dorm_shot.tscn
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"

var _dorm


func _ready() -> void:
	_dorm = load("res://scripts/DormRoom.gd").new()
	add_child(_dorm)
	await _wait(0.6)

	_dorm.present(false)
	await _wait(0.4)
	await _shot("00_day_spawn")

	# 自己走到门口：走完应该亮起「离开宿舍 · E」
	_dorm.set_move_input(Vector2(0, 1))
	await _wait(1.4)
	_dorm.set_move_input(Vector2.ZERO)
	await _wait(0.3)
	print("走到门口后 spot=", _dorm.active_spot_id(), " pos=", _dorm.player_image_position())
	await _shot("01_day_at_door")

	_dorm.open_confirm()
	await _wait(0.3)
	await _shot("02_day_confirm")
	_dorm.confirm_cancel()

	_dorm.present(true)
	await _wait(0.4)
	await _shot("03_curfew_door")

	# 宵禁：从门口走回卧室门口
	_dorm.set_move_input(Vector2(0, -1))
	await _wait(1.4)
	_dorm.set_move_input(Vector2(0, -1))
	await _wait(1.0)
	_dorm.set_move_input(Vector2.ZERO)
	await _wait(0.3)
	print("走回床边后 spot=", _dorm.active_spot_id(), " pos=", _dorm.player_image_position())
	await _shot("04_curfew_at_bed")

	_dorm.open_confirm()
	await _wait(0.3)
	await _shot("05_curfew_confirm")

	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/dorm_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
