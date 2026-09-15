extends Node

const MAIN_SCENE := preload("res://Main.tscn")

func _ready() -> void:
	WorldClock.running = true
	var town := MAIN_SCENE.instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	var camera := town.get("_camera") as Camera2D
	if camera == null or absf(camera.zoom.x - 1.55) > 0.01:
		_fail("室外探索镜头未使用近景缩放")
		return
	var camera_start := camera.position
	var player := town.get("_player") as Node2D
	player.position += Vector2(160, 0)
	town.call("_update_camera", 1.0)
	if camera.position.x <= camera_start.x:
		_fail("室外探索镜头没有跟随玩家")
		return
	player.position -= Vector2(160, 0)
	town.call("_update_camera", 1.0)
	for zone: Dictionary in town.ZONES:
		town.set("_nearby_zone", zone)
		town.call("_enter_nearby_zone")
		await get_tree().process_frame
		var interior = town.get("_interior_preview")
		if interior == null or interior.get("_npc") == null:
			_fail("%s 区未创建室内 NPC" % zone.get("code", "?"))
			return
		var status := town.get("_zone_status") as Label
		if status == null or status.visible:
			_fail("%s 区室内仍显示小镇左上角 HUD" % zone.get("code", "?"))
			return
		if String(zone.get("code", "")) == "A":
			await RenderingServer.frame_post_draw
			var interior_image := get_viewport().get_texture().get_image()
			interior_image.save_png(ProjectSettings.globalize_path("res://test_artifacts/interior_a_npc.png"))
		town.call("_exit_zone")
		await get_tree().process_frame
	town.call("_on_main_event_reached", {"title":"新员工手册", "locationId":"B"})
	await get_tree().process_frame
	if String(town.get("_highlighted_zone_id")) != "B":
		_fail("主线目标区域未被记录")
		return
	var b_marker: Polygon2D = null
	for marker: Polygon2D in town.get("_entrance_markers"):
		if marker.name == "EntranceB":
			b_marker = marker
			break
	if b_marker == null or b_marker.scale.x <= 1.0:
		_fail("B 区入口高亮未启用")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://test_artifacts/interior_experience.png"))
	print("INTERIOR_EXPERIENCE_PASS zones=8 npcs=8 hud_hidden=true target_highlight=B")
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error("INTERIOR_EXPERIENCE_FAIL " + message)
	get_tree().quit(1)
