class_name OfficeFloor
extends Node2D


const SIZE := Vector2(1920, 1080)
const WALL := Color("303b4b")
const WALL_LIGHT := Color("617185")
const FLOOR := Color("d9d9cb")
const GRID := Color("bec5bd")
const INK := Color("1e293b")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("20303b"))
	draw_rect(Rect2(52, 52, 1816, 976), Color("f3ede0"))
	draw_rect(Rect2(76, 76, 1768, 928), FLOOR)
	_draw_floor_grid()
	_draw_window_wall()
	_draw_rooms()
	_draw_corridor_signs()


func _draw_floor_grid() -> void:
	for x in range(80, 1840, 64):
		draw_line(Vector2(x, 76), Vector2(x, 1004), GRID, 1.0)
	for y in range(80, 1004, 64):
		draw_line(Vector2(76, y), Vector2(1844, y), GRID, 1.0)


func _draw_window_wall() -> void:
	draw_rect(Rect2(76, 76, 1768, 50), Color("7da9bb"))
	for x in range(105, 1820, 126):
		draw_rect(Rect2(x, 86, 86, 28), Color("c9ecf2"))
		draw_line(Vector2(x, 114), Vector2(x + 86, 114), Color("4d7788"), 3)


func _draw_rooms() -> void:
	_room(Rect2(112, 168, 350, 285), Color("c9e2d0"), "前台 / 接待")
	_draw_reception()
	_room(Rect2(510, 168, 680, 285), Color("e8e1c7"), "开放办公区")
	_draw_desks()
	_room(Rect2(1240, 168, 550, 285), Color("ead7ba"), "会议室")
	_draw_meeting_room()
	_room(Rect2(112, 610, 350, 310), Color("d8deeb"), "专注工位")
	_draw_focus_desks()
	_room(Rect2(510, 610, 1280, 310), Color("e6e2b5"), "休息与协作区")
	_draw_lounge()
	# Deliberately wide central routes: this is a phone-first office.
	_wall(Vector2(486, 138), Vector2(486, 476))
	_wall(Vector2(1214, 138), Vector2(1214, 476))
	_wall(Vector2(486, 580), Vector2(486, 950))
	_wall(Vector2(76, 548), Vector2(340, 548))
	_wall(Vector2(470, 548), Vector2(800, 548))
	_wall(Vector2(975, 548), Vector2(1390, 548))
	_wall(Vector2(1570, 548), Vector2(1844, 548))


func _room(rect: Rect2, color: Color, title: String) -> void:
	draw_rect(rect, color)
	draw_rect(rect, Color("ffffff"), false, 3.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(18, 38), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK)


func _wall(start: Vector2, finish: Vector2) -> void:
	draw_line(start, finish, WALL, 16)
	draw_line(start, finish, WALL_LIGHT, 4)


func _draw_reception() -> void:
	draw_rect(Rect2(160, 287, 252, 86), Color("276c66"))
	draw_rect(Rect2(182, 310, 208, 20), Color("d9f4e7"))
	_plant(Vector2(140, 391))
	_plant(Vector2(432, 391))
	draw_rect(Rect2(170, 205, 220, 42), Color("eff7ed"))
	draw_string(ThemeDB.fallback_font, Vector2(210, 235), "WORKPLACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("276c66"))


func _draw_desks() -> void:
	for y in [250, 350]:
		for x in [555, 755, 955]:
			desk(Vector2(x, y))


func _draw_focus_desks() -> void:
	for y in [705, 815]:
		desk(Vector2(178, y), Vector2(220, 74))


func desk(position: Vector2, desk_size := Vector2(150, 74)) -> void:
	draw_rect(Rect2(position, desk_size), Color("6c7b8a"))
	draw_rect(Rect2(position + Vector2(18, 12), Vector2(desk_size.x - 36, 34)), Color("d7f2ed"))
	draw_rect(Rect2(position + Vector2(25, 19), Vector2(desk_size.x - 50, 5)), Color("7db4bf"))
	draw_circle(position + Vector2(desk_size.x * 0.5, desk_size.y + 20), 19, Color("485666"))


func _draw_meeting_room() -> void:
	draw_rect(Rect2(1333, 260, 360, 110), Color("946642"))
	for x in [1380, 1510, 1640]:
		draw_circle(Vector2(x, 230), 20, Color("465465"))
		draw_circle(Vector2(x, 400), 20, Color("465465"))
	draw_rect(Rect2(1390, 192, 245, 24), Color("eff6f7"))


func _draw_lounge() -> void:
	draw_rect(Rect2(670, 760, 310, 100), Color("cf8150"))
	draw_rect(Rect2(1350, 740, 300, 110), Color("637d66"))
	draw_circle(Vector2(1165, 805), 64, Color("d8ad4f"))
	draw_rect(Rect2(1085, 722, 160, 28), Color("f7f3de"))
	_plant(Vector2(610, 870))
	_plant(Vector2(1710, 870))


func _plant(position: Vector2) -> void:
	draw_rect(Rect2(position.x - 19, position.y, 38, 36), Color("a45e3d"))
	draw_circle(position + Vector2(-16, -10), 25, Color("3f8061"))
	draw_circle(position + Vector2(17, -17), 28, Color("55a16d"))


func _draw_corridor_signs() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(830, 535), "主走廊", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("64748b"))
