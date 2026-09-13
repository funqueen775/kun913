extends Node2D

var walkable_areas: Array = []
var zones: Array = []
var collision_polygons: Array = []
var visible_overlay := false

func configure(areas: Array, configured_zones: Array, polygons: Array) -> void:
	walkable_areas = areas
	zones = configured_zones
	collision_polygons = polygons
	queue_redraw()

func set_overlay_visible(value: bool) -> void:
	visible_overlay = value
	queue_redraw()

func _draw() -> void:
	if not visible_overlay:
		return
	for polygon in collision_polygons:
		if polygon.size() >= 3:
			var points := PackedVector2Array(polygon)
			draw_colored_polygon(points, Color(0.95, 0.15, 0.15, 0.22))
			draw_polyline(points, Color(1.0, 0.25, 0.2, 0.95), 3.0)
	for zone in zones:
		var rect: Rect2 = zone["rect"]
		draw_rect(rect, Color(0.15, 0.55, 1.0, 0.12), true)
		draw_rect(rect, Color(0.4, 0.8, 1.0, 0.95), false, 4.0)
