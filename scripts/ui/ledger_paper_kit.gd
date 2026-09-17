extends Object
## 纸质感 UI 小工具包：ImageGen 生成 + PIL 后处理的资产，各面板复用。
## 资产：assets/ui/ledger/{paper_tex, seal_tex, tape_tex}.png
## 生成→处理→导入管线见 TECH_NOTES「ImageGen 资产管线」一节。

const PAPER_TEX := preload("res://assets/ui/ledger/paper_tex.png")
const SEAL_TEX := preload("res://assets/ui/ledger/seal_tex.png")
const TAPE_TEX := preload("res://assets/ui/ledger/tape_tex.png")


## 纸纹颗粒叠层：铺满 parent，不挡鼠标。Panel 与 PanelContainer 都适用
## （PanelContainer 会自动把子节点铺满内容矩形，无需 anchors）。
static func grain(parent: Control, alpha := 0.5) -> TextureRect:
	var t := TextureRect.new()
	t.texture = PAPER_TEX
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.self_modulate = Color(1, 1, 1, alpha)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not (parent is PanelContainer):
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(t)
	return t


## 和纸胶带：贴 parent 顶部居中（锚定水平中点，窗口缩放不跑偏），微微歪斜。
static func tape_center(parent: Control, width := 128.0, rot_deg := 2.0) -> TextureRect:
	var overlay := _overlay(parent)
	var t := _tape_tex(width)
	t.anchor_left = 0.5
	t.anchor_right = 0.5
	t.offset_left = -width / 2.0
	t.offset_right = width / 2.0
	t.offset_top = -8.0
	t.offset_bottom = -8.0 + width * 0.29
	t.rotation_degrees = rot_deg
	overlay.add_child(t)
	return t


## 和纸胶带：贴 parent 右上角（锚定），卡片用。
static func tape_tr(parent: Control, width := 92.0, rot_deg := 5.0) -> TextureRect:
	var overlay := _overlay(parent)
	var t := _tape_tex(width)
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	t.offset_left = -width - 12.0
	t.offset_right = -12.0
	t.offset_top = -8.0
	t.offset_bottom = -8.0 + width * 0.29
	t.rotation_degrees = rot_deg
	overlay.add_child(t)
	return t


static func _overlay(parent: Control) -> Control:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not (parent is PanelContainer):
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(overlay)
	return overlay


static func _tape_tex(width: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = TAPE_TEX
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size = Vector2(width, width * 0.29)
	t.self_modulate = Color(1, 1, 1, 0.92)
	return t
