extends Node2D

const COLLISION_PATH := "res://data/town/collision.json"
const MAP_PATH := "res://assets/town/workplace_town_reference.png"
const MAP_SIZE := Vector2(1920, 1080)
const PANEL_LEFT := 1425.0

var collision_data: Dictionary = {}
var layers: Array = []
var selected_layer_index := 0
var selected_polygon_index := -1
var drawing := false
var draft_points: Array[Vector2] = []
var shape_refs: Array[Dictionary] = []

var shape_list: OptionButton
var layer_choice: OptionButton
var status_label: Label
var coordinate_label: Label
var editor_panel: ColorRect
var dragging_panel := false
var panel_drag_offset := Vector2.ZERO

func _ready() -> void:
	_load_collision_data()
	_build_map()
	_build_panel()
	_refresh_shape_list()
	queue_redraw()

func _build_map() -> void:
	var map_sprite := Sprite2D.new()
	map_sprite.texture = load(MAP_PATH)
	map_sprite.position = Vector2.ZERO
	map_sprite.centered = false
	if map_sprite.texture != null:
		var source_size := map_sprite.texture.get_size()
		map_sprite.scale = Vector2(MAP_SIZE.x / source_size.x, MAP_SIZE.y / source_size.y)
	# The editor's _draw overlays must render above the map sprite.
	map_sprite.z_index = -1
	add_child(map_sprite)

func _build_panel() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	editor_panel = ColorRect.new()
	editor_panel.position = Vector2(PANEL_LEFT, 45)
	editor_panel.size = Vector2(450, 530)
	editor_panel.color = Color("1d2833e8")
	canvas.add_child(editor_panel)

	var title := Label.new()
	title.text = "碰撞轮廓绘制器  (按住这里拖动)"
	title.position = Vector2(24, 18)
	title.add_theme_font_size_override("font_size", 28)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_title_gui_input)
	editor_panel.add_child(title)

	var note := Label.new()
	note.text = "红色 = 已保存碰撞  橙色 = 当前选中\n青色 = 正在绘制的轮廓\n左键加点，右键撤销最后一个点"
	note.position = Vector2(24, 65)
	note.add_theme_font_size_override("font_size", 16)
	editor_panel.add_child(note)

	var layer_label := Label.new()
	layer_label.text = "新增形状类型"
	layer_label.position = Vector2(24, 145)
	layer_label.add_theme_font_size_override("font_size", 17)
	editor_panel.add_child(layer_label)

	layer_choice = OptionButton.new()
	layer_choice.position = Vector2(180, 140)
	layer_choice.size = Vector2(230, 38)
	for layer in layers:
		layer_choice.add_item(str(layer.get("id", "未命名")))
	editor_panel.add_child(layer_choice)

	var list_label := Label.new()
	list_label.text = "当前轮廓"
	list_label.position = Vector2(24, 200)
	list_label.add_theme_font_size_override("font_size", 17)
	editor_panel.add_child(list_label)

	shape_list = OptionButton.new()
	shape_list.position = Vector2(24, 230)
	shape_list.size = Vector2(386, 38)
	shape_list.item_selected.connect(_on_shape_selected)
	editor_panel.add_child(shape_list)

	var redraw_button := Button.new()
	redraw_button.text = "重画当前"
	redraw_button.position = Vector2(24, 290)
	redraw_button.size = Vector2(185, 44)
	redraw_button.pressed.connect(_start_redraw)
	editor_panel.add_child(redraw_button)

	var new_button := Button.new()
	new_button.text = "新增轮廓"
	new_button.position = Vector2(225, 290)
	new_button.size = Vector2(185, 44)
	new_button.pressed.connect(_start_new)
	editor_panel.add_child(new_button)

	var finish_button := Button.new()
	finish_button.text = "完成轮廓"
	finish_button.position = Vector2(24, 350)
	finish_button.size = Vector2(185, 44)
	finish_button.pressed.connect(_finish_drawing)
	editor_panel.add_child(finish_button)

	var delete_button := Button.new()
	delete_button.text = "删除当前"
	delete_button.position = Vector2(225, 350)
	delete_button.size = Vector2(185, 44)
	delete_button.pressed.connect(_delete_selected)
	editor_panel.add_child(delete_button)

	var clear_button := Button.new()
	clear_button.text = "清空全部红色轮廓"
	clear_button.position = Vector2(24, 410)
	clear_button.size = Vector2(386, 44)
	clear_button.add_theme_color_override("font_color", Color("ffdddd"))
	clear_button.pressed.connect(_clear_all_collisions)
	editor_panel.add_child(clear_button)

	var save_button := Button.new()
	save_button.text = "保存到 collision.json"
	save_button.position = Vector2(24, 470)
	save_button.size = Vector2(386, 50)
	save_button.add_theme_font_size_override("font_size", 19)
	save_button.pressed.connect(_save_collision_data)
	editor_panel.add_child(save_button)

	status_label = Label.new()
	status_label.text = "请选择一个形状，或新增轮廓。"
	status_label.position = Vector2(24, 535)
	status_label.size = Vector2(386, 36)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_panel.add_child(status_label)

	coordinate_label = Label.new()
	coordinate_label.text = "地图坐标：x 0，y 0"
	coordinate_label.position = Vector2(24, 575)
	coordinate_label.add_theme_font_size_override("font_size", 16)
	editor_panel.add_child(coordinate_label)
	editor_panel.size.y = 620

func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging_panel = event.pressed
		if dragging_panel:
			panel_drag_offset = get_viewport().get_mouse_position() - editor_panel.position
		return
	if event is InputEventMouseMotion and dragging_panel and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var viewport_size := get_viewport_rect().size
		var desired := get_viewport().get_mouse_position() - panel_drag_offset
		editor_panel.position = desired.clamp(Vector2.ZERO, viewport_size - editor_panel.size)

func _load_collision_data() -> void:
	var file := FileAccess.open(COLLISION_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open collision data: %s" % COLLISION_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		collision_data = parsed
		layers = collision_data.get("layers", [])

func _refresh_shape_list() -> void:
	shape_refs.clear()
	shape_list.clear()
	for layer_index in layers.size():
		var polygons: Array = layers[layer_index].get("polygons", [])
		for polygon_index in polygons.size():
			shape_refs.append({"layer": layer_index, "polygon": polygon_index})
			shape_list.add_item("%s #%d" % [layers[layer_index].get("id", "shape"), polygon_index + 1])
	if shape_refs.is_empty():
		selected_polygon_index = -1
		return
	if selected_polygon_index < 0:
		selected_layer_index = shape_refs[0]["layer"]
		selected_polygon_index = shape_refs[0]["polygon"]
	shape_list.select(_shape_ref_index(selected_layer_index, selected_polygon_index))

func _shape_ref_index(layer_index: int, polygon_index: int) -> int:
	for i in shape_refs.size():
		if shape_refs[i]["layer"] == layer_index and shape_refs[i]["polygon"] == polygon_index:
			return i
	return 0

func _on_shape_selected(index: int) -> void:
	if drawing or index < 0 or index >= shape_refs.size():
		return
	selected_layer_index = shape_refs[index]["layer"]
	selected_polygon_index = shape_refs[index]["polygon"]
	status_label.text = "已选中 %s。可重画、删除，或直接保存。" % shape_list.get_item_text(index)
	queue_redraw()

func _start_redraw() -> void:
	if selected_polygon_index < 0:
		status_label.text = "请先从“当前轮廓”中选择一个形状。"
		return
	drawing = true
	draft_points.clear()
	status_label.text = "正在重画：左键加点，右键撤销，至少 3 个点后点击“完成轮廓”。"
	queue_redraw()

func _start_new() -> void:
	selected_layer_index = layer_choice.selected
	selected_polygon_index = -1
	drawing = true
	draft_points.clear()
	status_label.text = "正在新增 %s：左键加点，右键撤销。" % layer_choice.get_item_text(layer_choice.selected)
	queue_redraw()

func _finish_drawing() -> void:
	if not drawing:
		status_label.text = "当前没有正在绘制的轮廓。"
		return
	if draft_points.size() < 3:
		status_label.text = "轮廓至少需要 3 个点。"
		return
	var stored_points: Array = []
	for point in draft_points:
		stored_points.append([roundi(point.x), roundi(point.y)])
	var polygons: Array = layers[selected_layer_index].get("polygons", [])
	if selected_polygon_index >= 0:
		polygons[selected_polygon_index] = stored_points
	else:
		polygons.append(stored_points)
		selected_polygon_index = polygons.size() - 1
	layers[selected_layer_index]["polygons"] = polygons
	drawing = false
	draft_points.clear()
	_refresh_shape_list()
	status_label.text = "轮廓已完成。点击“保存到 collision.json”才会写入文件。"
	queue_redraw()

func _delete_selected() -> void:
	if drawing or selected_polygon_index < 0:
		status_label.text = "请先选择一个已保存轮廓。"
		return
	var polygons: Array = layers[selected_layer_index].get("polygons", [])
	polygons.remove_at(selected_polygon_index)
	layers[selected_layer_index]["polygons"] = polygons
	selected_polygon_index = -1
	_refresh_shape_list()
	status_label.text = "轮廓已从内存删除。点击保存后才会写入文件。"
	queue_redraw()

func _clear_all_collisions() -> void:
	if drawing:
		status_label.text = "请先完成当前草稿，或右键撤销所有草稿点。"
		return
	for layer_index in layers.size():
		layers[layer_index]["polygons"] = []
	selected_polygon_index = -1
	shape_refs.clear()
	shape_list.clear()
	_save_collision_data()
	status_label.text = "所有红色轮廓已清空并保存。现在点击“新增轮廓”开始画。"
	queue_redraw()

func _save_collision_data() -> void:
	if drawing:
		status_label.text = "请先完成或撤销正在绘制的轮廓。"
		return
	collision_data["layers"] = layers
	var file := FileAccess.open(COLLISION_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "保存失败：请从 Godot 编辑器运行本工具。"
		return
	file.store_string(JSON.stringify(collision_data, "\t") + "\n")
	status_label.text = "已保存。关闭本工具后运行主场景，按 F3 检查红色轮廓。"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
		_save_collision_data()
	if not drawing:
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = event.position
		if point.x < 0 or point.y < 0 or point.x > MAP_SIZE.x or point.y > MAP_SIZE.y:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			draft_points.append(point)
			status_label.text = "已添加 %d 个点。" % draft_points.size()
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not draft_points.is_empty():
			draft_points.pop_back()
			status_label.text = "已撤销最后一个点，还剩 %d 个点。" % draft_points.size()
			queue_redraw()

func _process(_delta: float) -> void:
	if coordinate_label == null:
		return
	var mouse := get_viewport().get_mouse_position()
	coordinate_label.text = "地图坐标：x %d，y %d" % [roundi(mouse.x), roundi(mouse.y)]

func _draw() -> void:
	for layer_index in layers.size():
		var polygons: Array = layers[layer_index].get("polygons", [])
		for polygon_index in polygons.size():
			var points := _to_vectors(polygons[polygon_index])
			if points.size() < 3:
				continue
			var selected := layer_index == selected_layer_index and polygon_index == selected_polygon_index
			var color := Color(1.0, 0.55, 0.08, 0.95) if selected else Color(1.0, 0.16, 0.12, 0.95)
			var fill := Color(color, 0.24 if selected else 0.16)
			draw_colored_polygon(PackedVector2Array(points), fill)
			var closed := PackedVector2Array(points)
			closed.append(points[0])
			draw_polyline(closed, color, 3.0, true)
	if not draft_points.is_empty():
		draw_polyline(PackedVector2Array(draft_points), Color(0.1, 0.95, 1.0, 1.0), 4.0, true)
		for point in draft_points:
			draw_circle(point, 6.0, Color(0.1, 0.95, 1.0, 1.0))

func _to_vectors(raw_points: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for raw_point in raw_points:
		if raw_point is Array and raw_point.size() >= 2:
			result.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	return result
