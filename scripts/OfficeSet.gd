class_name OfficeSet
extends Node2D


const SHELL := "res://assets/office/office_shell.png"
const COUNTER := "res://assets/office/counter.png"
const CABINET := "res://assets/office/cabinet.png"
const LAMP := "res://assets/office/lamp.png"
const PLANT := "res://assets/office/plant.png"
const CHAIR := "res://assets/office/chair.png"
const BENCH := "res://assets/office/bench.png"
const DESK := "res://assets/office/desk.png"
const STORAGE := "res://assets/office/storage.png"
const MODERN_WORKSTATION := "res://assets/generated/modern-workstation.png"
const MODERN_MEETING_SET := "res://assets/generated/modern-meeting-set.png"
const CHINESE_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")

const ORIGIN := Vector2(330, 0)
const SCALE := 0.85
const ZONES := [
	{"id": "reception", "title": "01  客户接待", "rect": Rect2(22, 280, 255, 360), "door": "bottom"},
	{"id": "product", "title": "02  产品研发", "rect": Rect2(300, 250, 525, 355), "door": "bottom"},
	{"id": "meeting", "title": "03  项目会议", "rect": Rect2(900, 300, 315, 420), "door": "left"},
	{"id": "focus", "title": "04  深度专注", "rect": Rect2(22, 755, 360, 230), "door": "top"},
	{"id": "collaboration", "title": "05  创意协作", "rect": Rect2(425, 755, 400, 230), "door": "top"},
]

func _ready() -> void:
	_add_sprite("OfficeShell", SHELL, Vector2.ZERO, -10, SCALE)
	_add_sprite("ReceptionCounter", COUNTER, Vector2(55, 350), 12, 0.38)
	_add_sprite("ReceptionBench", BENCH, Vector2(62, 530), 11, 0.31)
	_add_sprite("ReceptionPlant", PLANT, Vector2(214, 525), 13, 0.34)
	_add_sprite("WorkstationOne", MODERN_WORKSTATION, Vector2(310, 230), 12, 0.20)
	_add_sprite("WorkstationTwo", MODERN_WORKSTATION, Vector2(560, 230), 12, 0.20)
	_add_sprite("MeetingSet", MODERN_MEETING_SET, Vector2(880, 310), 13, 0.205)
	_add_sprite("MeetingCabinet", CABINET, Vector2(1145, 350), 11, 0.32)
	_add_sprite("FocusDesk", DESK, Vector2(72, 765), 12, 0.36)
	_add_sprite("FocusChair", CHAIR, Vector2(160, 900), 13, 0.23)
	_add_sprite("FocusLamp", LAMP, Vector2(278, 800), 12, 0.36)
	_add_sprite("CollaborativeBench", BENCH, Vector2(455, 795), 12, 0.37)
	_add_sprite("CollaborativeStorage", STORAGE, Vector2(665, 770), 12, 0.35)
	_add_sprite("CollaborativePlant", PLANT, Vector2(755, 835), 13, 0.40)
	_add_headers()
	queue_redraw()


func _draw() -> void:
	for zone in ZONES:
		var local_rect: Rect2 = zone["rect"]
		var rect := Rect2(ORIGIN + local_rect.position * SCALE, local_rect.size * SCALE)
		_draw_room_walls(rect, String(zone["door"]))


func _draw_room_walls(rect: Rect2, door_side: String) -> void:
	var thickness := 18.0
	var door_width := 76.0
	var top := Rect2(rect.position.x, rect.position.y - thickness * 0.5, rect.size.x, thickness)
	var bottom := Rect2(rect.position.x, rect.end.y - thickness * 0.5, rect.size.x, thickness)
	var left := Rect2(rect.position.x - thickness * 0.5, rect.position.y, thickness, rect.size.y)
	var right := Rect2(rect.end.x - thickness * 0.5, rect.position.y, thickness, rect.size.y)
	if door_side == "top" or door_side == "bottom":
		var wall := top if door_side == "top" else bottom
		var gap_start := wall.position.x + (wall.size.x - door_width) * 0.5
		_draw_wood_segment(Rect2(wall.position.x, wall.position.y, gap_start - wall.position.x, wall.size.y))
		_draw_wood_segment(Rect2(gap_start + door_width, wall.position.y, wall.end.x - gap_start - door_width, wall.size.y))
		_draw_wood_segment(left)
		_draw_wood_segment(right)
		_draw_wood_segment(bottom if door_side == "top" else top)
		_draw_door(Rect2(gap_start, wall.position.y, door_width, wall.size.y), true)
	else:
		var wall := left if door_side == "left" else right
		var gap_start := wall.position.y + (wall.size.y - door_width) * 0.5
		_draw_wood_segment(Rect2(wall.position.x, wall.position.y, wall.size.x, gap_start - wall.position.y))
		_draw_wood_segment(Rect2(wall.position.x, gap_start + door_width, wall.size.x, wall.end.y - gap_start - door_width))
		_draw_wood_segment(top)
		_draw_wood_segment(bottom)
		_draw_wood_segment(right if door_side == "left" else left)
		_draw_door(Rect2(wall.position.x, gap_start, wall.size.x, door_width), false)


func _draw_wood_segment(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_rect(rect, Color("26150c"), true)
	draw_rect(rect.grow(-3.0), Color("8c4c1e"), true)
	draw_rect(rect, Color("d08a35"), false, 2.0)


func _draw_door(rect: Rect2, horizontal: bool) -> void:
	draw_rect(rect, Color("382012"), true)
	draw_rect(rect.grow(-3.0), Color("c27a2b"), true)
	if horizontal:
		draw_line(Vector2(rect.position.x + 9, rect.get_center().y), Vector2(rect.end.x - 9, rect.get_center().y), Color("f5c56a"), 2.0)
	else:
		draw_line(Vector2(rect.get_center().x, rect.position.y + 9), Vector2(rect.get_center().x, rect.end.y - 9), Color("f5c56a"), 2.0)


func _add_sprite(name_value: String, texture_path: String, local_position: Vector2, depth: int, scale_factor: float) -> void:
	var texture := _load_texture(texture_path)
	if texture == null:
		push_error("办公室贴图加载失败: %s" % texture_path)
		return
	var sprite := Sprite2D.new()
	sprite.name = name_value
	sprite.texture = texture
	sprite.centered = false
	sprite.position = ORIGIN + local_position * SCALE
	sprite.scale = Vector2.ONE * scale_factor
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = depth
	add_child(sprite)


func _load_texture(path: String) -> Texture2D:
	var imported := load(path) as Texture2D
	if imported != null:
		return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _add_headers() -> void:
	for zone in ZONES:
		var rect: Rect2 = zone["rect"]
		var label := Label.new()
		label.text = zone["title"]
		label.position = ORIGIN + rect.position * SCALE + Vector2(14, 13)
		label.add_theme_font_override("font", CHINESE_FONT)
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color("fff3ce"))
		label.add_theme_color_override("font_outline_color", Color("231b16"))
		label.add_theme_constant_override("outline_size", 5)
		label.z_index = 50
		add_child(label)
