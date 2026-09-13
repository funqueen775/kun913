class_name OfficeNpcWalker
extends Node2D


const PAPER_DOLL := preload("res://scripts/PaperDoll64Sprite.gd")

var _loadout_id := "neutral_hoodie"
var _route := PackedVector2Array()
var _speed := 34.0
var _route_index := 1
var _pause_remaining := 0.0
var _rng := RandomNumberGenerator.new()
var _sprite: PaperDoll64Sprite


func configure(loadout_id: String, route: PackedVector2Array, speed: float, seed: int) -> void:
	_loadout_id = loadout_id
	_route = route
	_speed = speed
	_rng.seed = seed


func _ready() -> void:
	if _route.size() < 2:
		return
	position = _route[0]
	_build_shadow()
	_sprite = PAPER_DOLL.new()
	_sprite.position = Vector2(-32, -72)
	_sprite.catalog_loaded.connect(_apply_loadout)
	add_child(_sprite)
	_route_index = 1
	_update_depth()


func _physics_process(delta: float) -> void:
	if _sprite == null or _route.size() < 2:
		return
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(0.0, _pause_remaining - delta)
		_sprite.set_motion(Vector2.ZERO, 0.0)
		return
	var target := _route[_route_index]
	var offset := target - position
	var distance := offset.length()
	if distance <= 1.0:
		position = target
		_route_index = posmod(_route_index + 1, _route.size())
		_pause_remaining = _rng.randf_range(0.5, 1.6)
		_sprite.set_motion(Vector2.ZERO, 0.0)
		return
	var moved := minf(distance, _speed * delta)
	var direction := offset / distance
	position += direction * moved
	_sprite.set_motion(direction, moved)
	_update_depth()


func _apply_loadout(_catalog_path: String) -> void:
	_sprite.set_loadout(_loadout_id)
	_sprite.configure_motion_speed(_speed)


func _build_shadow() -> void:
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-23, -5), Vector2(23, -5), Vector2(30, 1), Vector2(17, 7), Vector2(-17, 7), Vector2(-30, 1)])
	shadow.color = Color(0.03, 0.04, 0.05, 0.30)
	shadow.position = Vector2(0, -1)
	shadow.z_index = -1
	add_child(shadow)


func _update_depth() -> void:
	z_index = int(position.y)
