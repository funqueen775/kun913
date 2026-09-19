extends Node

## 临时截图探针：ReportPanel.render(report_live_sample.json) 后截一张真图。
## 用法：<godot> --path <proj> --resolution 1920x1080 res://tools/report_panel_shot.tscn

func _ready() -> void:
	await get_tree().process_frame
	var text := FileAccess.get_file_as_string("res://build/report_live_sample.json")
	var report: Dictionary = JSON.parse_string(text)
	var panel: CanvasLayer = (load("res://scripts/ReportPanel.gd") as GDScript).new()
	add_child(panel)
	await get_tree().process_frame
	panel.render(report)
	panel.set("visible", true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "E:/03_Projects/bear/kun913/test_artifacts/report_panel_shot.png"
	var error := image.save_png(path)
	print("REPORT_SHOT -> %s (%s)" % [path, error])
	# 第二张：滚到职业推荐区块
	var scroll: ScrollContainer = panel.get("_scroll")
	if scroll != null:
		scroll.scroll_vertical = 20000
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image2 := get_viewport().get_texture().get_image()
		var path2 := "E:/03_Projects/bear/kun913/test_artifacts/report_panel_career_shot.png"
		var error2 := image2.save_png(path2)
		print("REPORT_CAREER_SHOT -> %s (%s)" % [path2, error2])
	get_tree().quit()
