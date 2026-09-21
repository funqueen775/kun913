extends Node


const PROFILE_PATH := "user://workplace_town_profile.json"
const DEFAULT_AVATAR_ID := "avatar_player"
const AVATARS := [
	{"id": "avatar_player", "name": "玩家"},
	{"id": "avatar_xiaoye", "name": "小叶"},
	{"id": "avatar_yueya", "name": "月牙"},
	{"id": "avatar_mili", "name": "米粒"},
	{"id": "avatar_amai", "name": "阿麦"},
]

var _selected_avatar_id := DEFAULT_AVATAR_ID


func _ready() -> void:
	_load_saved_avatar()


func get_selected_avatar_id() -> String:
	return _selected_avatar_id


func set_selected_avatar_id(avatar_id: String) -> bool:
	if not is_avatar_id(avatar_id):
		return false
	_selected_avatar_id = avatar_id
	return true


func is_avatar_id(avatar_id: String) -> bool:
	for avatar in AVATARS:
		if String((avatar as Dictionary).get("id", "")) == avatar_id:
			return true
	return false


func _load_saved_avatar() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		set_selected_avatar_id(String((parsed as Dictionary).get("avatarId", DEFAULT_AVATAR_ID)))
