extends Node2D

## NPC 形象开窗验收：先拍全镇分布，再逐个 NPC 特写，最后单独验 4 个朝向。
## 用法：<godot> --path <proj> --resolution 1920x1080 res://tools/bear_shot.tscn
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"
const NPC_ZOOM := 5.0
## 特写时相机抬高一点，让角色落在画面中心（sprite 锚点在脚底）。
const LIFT := Vector2(0, -46)

var _town: Node2D
var _camera: Camera2D


func _ready() -> void:
	_town = load("res://Main.tscn").instantiate()
	add_child(_town)
	await _wait(1.3)

	# 开场先落在「宿舍」遮罩里（layer 110），不关掉的话什么都拍不到
	if _town._dorm != null:
		_town._dorm.dismiss()
	await _wait(0.3)

	# 冻结小镇逻辑：NPC 停住、相机不再跟着玩家，方便逐格取景
	_town.set_physics_process(false)
	_camera = _town._camera
	if _camera == null:
		push_error("拿不到小镇相机")
		get_tree().quit()
		return
	_camera.position_smoothing_enabled = false

	# 1) 全景：看 5 个 NPC 在地图里的分布
	_camera.zoom = Vector2.ONE
	_camera.position = Vector2(960, 540)
	await _shot("town_overview")

	# 2) 逐个 NPC 特写（_npc_instances 的条目没有 id，用 name+序号标识）
	_camera.zoom = Vector2.ONE * NPC_ZOOM
	var index := 0
	for entry in _town._npc_instances:
		index += 1
		var ch: Node2D = entry["character"]
		_camera.position = ch.position + LIFT
		await _shot("npc_%02d_%s" % [index, String(entry["name"])])

	# 3) 朝向验证：拿第一个 NPC 依次摆出 down / right / up / left
	#    必须把 NPC 自己的 _physics_process 也停掉——走路会按移动方向覆盖预览朝向
	var first: Node2D = _town._npc_instances[0]["character"]
	first.set_physics_process(false)
	var sprite = first._sprite
	for row in range(4):
		sprite.set_preview_direction(row)
		sprite.set_motion(Vector2.ZERO, 0.0)
		_camera.position = first.position + LIFT
		await _shot("dir_%d" % row)

	print("bear_shot done")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/bear_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
