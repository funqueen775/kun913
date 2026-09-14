extends Control
## 开场截图工具：把开场每一屏真实渲染出来存成 PNG，用于肉眼对照参考图。
##
## 用法：
##   <godot> --path <PROJ> --resolution 1920x1080 res://tools/shot_intro.tscn -- --shots title,0,1,2 --shot-dir E:/xxx/shots
##
## 与 tools/verify_intro.gd 的区别：那个是 --script（SceneTree）模式，只查结构不渲染；
## 这个必须真渲染才能截图，所以要开窗口跑，截完自动退出。
## 页码从 0 开始（0/1/2 = 小镇介绍 / 人物名单 / 开始生活），title = 标题主菜单。

var _dir := "user://shots"
var _shots: Array = ["title"]
## 要截的场景：默认开场；截别的场景用 --scene res://Main.tscn（此时 --shots 只决定文件名）
var _scene := "res://Intro.tscn"
var _is_intro := true


## 崩溃时 stdout 会被吞掉，所以进度写进文件（排查用）
func _mark(msg: String) -> void:
	print("[shot] %s" % msg)
	var f := FileAccess.open("%s/step.txt" % _dir, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("%s/step.txt" % _dir, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(msg)
		f.close()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_dir = args[i + 1]
		elif args[i] == "--shots" and i + 1 < args.size():
			_shots = String(args[i + 1]).split(",")
		elif args[i] == "--scene" and i + 1 < args.size():
			_scene = String(args[i + 1])
	_is_intro = _scene.contains("Intro")
	DirAccess.make_dir_recursive_absolute(_dir)
	_mark("ready, dir=%s scene=%s" % [_dir, _scene])
	_run()


func _run() -> void:
	var packed: PackedScene = load(_scene)
	if packed == null:
		_mark("%s 加载失败" % _scene)
		get_tree().quit(1)
		return
	_mark("scene loaded")
	var inst: Node = packed.instantiate()
	add_child(inst)
	# 等两帧让 _ready() 与首屏构建跑完
	await get_tree().process_frame
	await get_tree().process_frame
	_mark("instance ready")

	for s in _shots:
		var key := String(s).strip_edges()
		if key == "":
			continue
		if _is_intro:
			if key == "title":
				inst.call("_show_title")
			else:
				inst.call("_goto_intro", int(key))
		_mark("built %s" % key)
		# 两帧：一帧让容器算完布局，一帧让它真的画出来；
		# 非开场场景（有相机/物理）多等几帧，等相机与寻路稳定
		await get_tree().process_frame
		await get_tree().process_frame
		if not _is_intro:
			for i in 10:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_mark("drawn %s" % key)
		var img := get_viewport().get_texture().get_image()
		_mark("readback %s %s" % [key, img.get_size()])
		var path := "%s/%s.png" % [_dir, key]
		var err := img.save_png(path)
		_mark("saved %s err=%d" % [path, err])
		# 相机仪表：看视野实际覆盖的世界范围（排查露边/灰底用）
		var cam: Camera2D = inst.get("_camera") if inst.get("_camera") != null else null
		if cam != null:
			_mark("cam zoom=%s pos=%s screen_center=%s viewport=%s" % [
				cam.zoom, cam.position, cam.get_screen_center_position(), get_viewport_rect().size])

	_mark("完成，共 %d 张" % _shots.size())
	get_tree().quit()
