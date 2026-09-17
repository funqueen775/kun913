extends Control

## 右上角 HUD 打磨批次（2026-09-17 第三批）的画面验收：
## 起的是 Main.tscn 本体，依次截：小镇 HUD（4 颗圆钮排：设/账/忆/力 + 只显示「第 N 月」）
## → 设置弹窗 → 精力弹窗（大圆点 + 4 动作卡）→ 点卡消费后的反馈 → 精力耗尽 22:00 横幅。
## 用法：Godot --path <PROJ> --resolution 1920x1080 res://tools/hud_polish_shot.tscn
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots_b3"

var _town: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_town = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(_town)
	await _settle()
	# 开局人在宿舍（黑屏盖住地图）：走「离开宿舍」这条真链路，让小镇 HUD 露出来。
	_town._confirm_dorm_action()
	await _settle()
	await _shot("1_town_hud")

	# 设置弹窗：开 → 等动画走完 → 截。
	_town._open_settings()
	await _wait(0.5)
	await _shot("2_settings_modal")
	_town._settings_panel.close()
	await _wait(0.4)

	# 精力弹窗：点「力」圆钮打开 → 截（大圆点 3/3 + 4 张动作卡）。
	_town._open_energy_modal()
	await _wait(0.5)
	await _shot("3_energy_modal")
	# 点「专业成长」卡花 1 点：计数 2/3 + 便签反馈。
	_town._energy_panel._on_action_pressed("grow")
	print("[hud] after card: energy=", _town._monthly_life.energy,
		" count=", _town._energy_panel._count_label.text)
	await _wait(0.5)
	await _shot("4_energy_modal_spent")
	_town._energy_panel.close()
	await _wait(0.4)

	# 精力耗尽联动：先放行开局压着的主线 E01（否则主线守卫会按设计拦停跳跃），
	# 再花掉剩下 2 点 → 时间应直接跳到 22:00 + 顶部横幅。
	WorldClock.complete_main_event("M1-E01")
	for i in 2:
		_town._monthly_life.spend_energy("produce")
	var snap: Dictionary = WorldClock.snapshot()
	print("[hud] after exhaust: clock=", snap["clock"], " phase=", snap["phaseId"],
		" energy=", _town._monthly_life.energy)
	await _wait(0.6)
	await _shot("5_energy_toast")

	get_tree().quit()


func _settle() -> void:
	for _index in 4:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/hudpolish_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("[shot] %s -> err=%d" % [path, error])
