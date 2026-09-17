extends Node2D

## 自由周末（周六两格 + 手账页）的开窗验收：五张状态图。
## 用法：<godot> --path <proj> --resolution 1920x1080 res://tools/weekend_shot.tscn
##
## 拍完要看的是五件事：
##   1) 首屏是不是一张"两格空表"（而不是旧版的"出门逛逛"按钮）；
##   2) 填满一格之后，公开数值**一点没动**（面板上没有即时结算的行）；
##   3) 已排进另一格的活动是不是**置灰不可选**（同一活动一个周末只出现一次）；
##   4) 「就这样过」之后出的是**手账页**（周几/活动/谁 + 手写一行 + 人话），
##      而且**一行数字流水都没有**（"好感 +5" 这类）；
##   5) 全留白也能正常收尾，不出现空页或"没安排就不能走"。
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"

var _town: Node2D


func _ready() -> void:
	_town = load("res://Main.tscn").instantiate()
	add_child(_town)
	await _wait(1.3)

	# 开局在黑屏宿舍里，先按真实流程出门，否则拍到的是遮罩。
	_town._on_dorm_leave()
	await _wait(0.5)

	# 冻结小镇逻辑，免得 NPC 走动抢镜；面板是 CanvasLayer，不受物理帧影响。
	_town.set_physics_process(false)
	WorldClock.set_running(false)

	var panel = _town._free_time_panel
	if panel == null:
		push_error("拿不到自由周末面板")
		get_tree().quit()
		return

	# 1) 首屏：周六两格空表
	panel.open_for_month(9)
	await _wait(0.6)
	await _shot("weekend_01_slots_empty")

	# 2) 第 1 格填上：注意没有任何"结算行"冒出来（填格不结算）
	panel.begin_slot(0)
	await _wait(0.3)
	panel.choose_zone("B_科技丘")
	await _wait(0.3)
	panel.choose_activity("W4_team_tool")
	await _wait(0.4)
	await _shot("weekend_02_slot_one_filled")

	# 3) 第 2 格进活动列表：已排进第 1 格的 W4 应当**置灰不可选**
	panel.begin_slot(1)
	await _wait(0.3)
	panel.choose_zone("B_科技丘")
	await _wait(0.4)
	await _shot("weekend_03_duplicate_greyed")

	# 4) 两格填满 → 总表（右侧应出现「清空」）
	panel.choose_activity("W5_postmortem_notes")
	await _wait(0.4)
	await _shot("weekend_04_slots_filled")

	# 5) 「就这样过」→ 手账页
	panel.commit_weekend()
	await _wait(0.7)
	await _shot("weekend_05_ledger")

	# 6) 全留白收尾
	panel._finish_weekend()
	await _wait(0.3)
	panel.open_for_month(12)
	await _wait(0.5)
	panel.commit_weekend()
	await _wait(0.6)
	await _shot("weekend_06_ledger_blank")

	# 7) B 件·在场一幕：两格都选「有人同行、没有 decision」的活动 → 结算后先出一幕。
	panel._finish_weekend()
	await _wait(0.3)
	panel.open_for_month(15)
	await _wait(0.4)
	panel.begin_slot(0)
	await _wait(0.2)
	panel.choose_zone("C_水巷")
	await _wait(0.2)
	panel.choose_activity("D1_coffee_chat")
	await _wait(0.3)
	panel.begin_slot(1)
	await _wait(0.2)
	panel.choose_zone("C_水巷")
	await _wait(0.2)
	panel.choose_activity("D3_lawn_sports")
	await _wait(0.3)
	panel.commit_weekend()
	await _wait(0.7)
	await _shot("weekend_07_encounter")

	# 8) 应答选完 → 手账页中间多出「在场一幕」一块（画面一句 + 记住了你：XXX）。
	panel.choose_encounter_option("A")
	await _wait(0.7)
	await _shot("weekend_08_ledger_with_encounter")
	panel._finish_weekend()

	print("weekend_shot done")
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
