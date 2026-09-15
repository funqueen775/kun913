extends Node

const STARTUP_SCENE := preload("res://Startup.tscn")

func _ready() -> void:
	var startup := STARTUP_SCENE.instantiate()
	add_child(startup)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _has_text(startup, "职 场 小 镇") or not _has_text(startup, "开始新游戏"):
		_fail("标题主菜单没有正确显示")
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_artifacts/startup_title.png"))
	startup.call("_start_intro")
	await get_tree().process_frame
	if not _has_text(startup, "认识职场小镇") or not _has_text(startup, "小镇介绍"):
		_fail("小镇导览首页没有正确显示")
		return
	startup.call("_go_page", 1)
	await get_tree().process_frame
	if not _has_text(startup, "人物名单") or not _has_text(startup, "陈工"):
		_fail("人物名单页没有正确显示")
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_artifacts/startup_people.png"))
	print("STARTUP_FLOW_PASS title=true intro_pages=3 cast=true")
	get_tree().quit(0)

func _has_text(root: Node, value: String) -> bool:
	if root is Label and (root as Label).text == value:
		return true
	if root is Button and (root as Button).text == value:
		return true
	for child in root.get_children():
		if _has_text(child, value):
			return true
	return false

func _fail(message: String) -> void:
	push_error("STARTUP_FLOW_FAIL " + message)
	get_tree().quit(1)
