extends SceneTree

# 一次性探针：验证 InteriorPreview.gd（含其 preload 链）能否正常解析加载。
# 用法：Godot_v4.3-stable_win64_console.exe --headless --path <PROJ> --script res://tools/check_interior.gd

func _init() -> void:
	var ok := true
	for path in [
		"res://scripts/InteriorPreview.gd",
		"res://scripts/PaperDoll64Sprite.gd",
		"res://scripts/OfficeNpcWalker.gd",
		# 注：WorkplaceTown.gd 引用 autoload（WorldClock 等），--script 模式不注册 autoload，
		# 编译必失败 —— 它的验证只能靠跑 Main.tscn 本体。
	]:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			printerr("FAIL load ", path)
			ok = false
		else:
			print("PASS load ", path)
	print("INTERIOR_CHECK_RESULT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
