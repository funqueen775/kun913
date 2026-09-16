extends Node

const MAIN_SCENE := preload("res://Main.tscn")
const OUTPUT_DIR := "res://test_artifacts"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	WorldClock.world_minute = ((1 - 1) * WorldClock.DAYS_PER_MONTH + (15 - 1)) * WorldClock.MINUTES_PER_DAY + 9 * 60
	WorldClock.running = false
	var town := MAIN_SCENE.instantiate()
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	# PR #3 增加了宿舍开场遮罩；先离开宿舍，后续才是在可见的小镇/室内流程上验收。
	if bool(town.get("_in_dorm")):
		town.call("_on_dorm_leave")
		await get_tree().process_frame
	var zone_b: Dictionary = {}
	for zone in town.ZONES:
		if String(zone.get("code", "")) == "B":
			zone_b = zone
			break
	if zone_b.is_empty():
		_fail("B 区不存在")
		return
	town.set("_nearby_zone", zone_b)
	town.call("_enter_nearby_zone")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var panel = town.get("_story_event_panel")
	if panel == null or not panel.is_open() or panel.current_stage() != "intro":
		_fail("进入 B 区后没有显示介绍面板")
		return
	_save_screenshot("event_intro.png")
	var continue_button := panel.get_node_or_null("EventOverlay/StoryIntro/ContinueButton") as Button
	if continue_button == null:
		_fail("介绍面板缺少继续按钮")
		return
	continue_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if panel.current_stage() != "choices":
		_fail("点击介绍面板后没有进入选项页")
		return
	var choices: Node = panel.get_node("EventOverlay/StoryChoices")
	var choice_count := 0
	for child in choices.get_children():
		if child is Button and child.name.begins_with("Choice_"):
			choice_count += 1
	if choice_count != 3:
		_fail("选项数量错误：%d" % choice_count)
		return
	_save_screenshot("event_choices.png")
	var choice_button := panel.get_node("EventOverlay/StoryChoices/Choice_option_b") as Button
	choice_button.pressed.emit()
	await get_tree().process_frame
	var interior = town.get("_interior_preview")
	if panel.is_open() or not interior.is_exploration_enabled():
		_fail("完成选择后没有进入室内探索")
		return
	var interior_player := interior.get("_player") as Node2D
	var npc := interior.get("_npc") as Node2D
	var player_sprite := interior.get("_player_sprite") as Node2D
	if player_sprite.scale != Vector2.ONE * (5.0 / 3.0) or npc.scale != Vector2.ONE * (5.0 / 3.0):
		_fail("室内人物没有使用三分之一的显示比例")
		return
	var player_start := interior_player.position
	var npc_start := npc.position
	Input.action_press("move_right")
	for frame in 12:
		await get_tree().process_frame
	Input.action_release("move_right")
	if interior_player.position.x <= player_start.x:
		_fail("室内玩家没有响应移动输入")
		return
	if npc.position.distance_to(npc_start) < 1.0:
		_fail("室内 NPC 没有行走")
		return
	interior_player.position = npc.position + Vector2(70, 0)
	await get_tree().process_frame
	var talk_button := interior.get("_talk_button") as Button
	if not talk_button.visible:
		_fail("靠近陈工后没有显示交流按钮")
		return
	_save_screenshot("interior_exploration.png")
	talk_button.pressed.emit()
	await get_tree().process_frame
	var dialog := interior.get("_dialog") as Panel
	if not dialog.visible:
		_fail("点击交流后没有显示对话")
		return
	var message_input := interior.get("_message_input") as LineEdit
	var send_button := interior.get("_send_button") as Button
	message_input.text = "你好，我今天应该先做什么任务？"
	send_button.pressed.emit()
	await get_tree().process_frame
	var dialog_text := interior.get("_dialog_text") as Label
	if not dialog_text.text.contains("你：") or not dialog_text.text.contains("陈工："):
		_fail("玩家消息或陈工本地回复没有显示")
		return
	await RenderingServer.frame_post_draw
	_save_screenshot("interior_dialog.png")
	print("EVENT_FLOW_TEST_PASS intro=true choices=3 exploration=true scale=5 player_moved=true npc_moved=true local_chat=true")
	get_tree().quit(0)


func _save_screenshot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name]))
	if error != OK:
		_fail("截图保存失败：%s" % error_string(error))


func _fail(message: String) -> void:
	push_error("EVENT_FLOW_TEST_FAIL " + message)
	get_tree().quit(1)
