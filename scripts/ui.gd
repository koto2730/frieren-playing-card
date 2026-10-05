class_name UI
extends RefCounted
## コードからUIを組み立てるための小さなヘルパー。
## 画面は よこ1280x720 / たて720x1280 のどちらかを基準に配置する。

const LANDSCAPE := Vector2(1280, 720)
const PORTRAIT := Vector2(720, 1280)
const PORTRAIT_WINDOW := Vector2i(540, 960)  # PCでたて画面にしたときのウィンドウサイズ
const TABLE_COLOR := Color(0.07, 0.36, 0.22)

const BACKDROP_FRIEREN: Texture2D = preload("res://assets/images/card_frieren.jpg")
const BACKDROP_FERN: Texture2D = preload("res://assets/images/card_fern.jpg")

const SCENE_TITLE := "res://scenes/title.tscn"
const SCENE_RULE_SELECT := "res://scenes/rule_select.tscn"


static func screen() -> Vector2:
	return PORTRAIT if Settings.portrait else LANDSCAPE


## 選ばれた向きに合わせて画面の基準サイズを切り替える。
static func apply_orientation(tree: SceneTree) -> void:
	var window := tree.root
	var target := Vector2i(screen())
	if window.content_scale_size == target:
		return
	window.content_scale_size = target
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return
	# PCではウィンドウの形も合わせる
	window.size = PORTRAIT_WINDOW if Settings.portrait else target
	window.move_to_center()


static func background(parent: Control, color: Color = TABLE_COLOR) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = Vector2.ZERO
	rect.size = screen()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


## タイトルやルール選択の背景に、大きなカードの絵を2枚かざる。
## brightness を下げるほど暗くなり、手前の文字が読みやすくなる。
static func card_backdrop(parent: Control, brightness: float) -> void:
	var portrait := Settings.portrait
	var height := 640.0
	# [画像, 中心位置, 角度]
	var cards := [
		[BACKDROP_FRIEREN, Vector2(200, 540) if portrait else Vector2(250, 365), -7.0],
		[BACKDROP_FERN, Vector2(520, 800) if portrait else Vector2(1030, 365), 7.0],
	]
	for entry: Array in cards:
		var texture: Texture2D = entry[0]
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.size = Vector2(height * texture.get_width() / texture.get_height(), height)
		rect.pivot_offset = rect.size / 2.0
		rect.position = entry[1] - rect.size / 2.0
		rect.rotation_degrees = entry[2]
		rect.modulate = Color(brightness, brightness, brightness)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(rect)


static func label(parent: Control, text: String, pos: Vector2, label_size: Vector2,
		font_size: int = 24, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.size = label_size
	lbl.horizontal_alignment = align
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	return lbl


## 絵の上に重なる文字が読めるよう、暗いふちどりを付ける。
static func outline(lbl: Label, outline_size: int) -> Label:
	lbl.add_theme_constant_override("outline_size", outline_size)
	lbl.add_theme_color_override("font_outline_color", Color(0.03, 0.15, 0.09))
	return lbl


static func flat_box(color: Color, radius: int = 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box


static func panel(parent: Control, pos: Vector2, panel_size: Vector2) -> Panel:
	var pnl := Panel.new()
	pnl.position = pos
	pnl.size = panel_size
	pnl.add_theme_stylebox_override("panel", flat_box(Color(0.04, 0.2, 0.13, 0.9), 10))
	parent.add_child(pnl)
	return pnl


static func button(parent: Control, text: String, pos: Vector2, button_size: Vector2,
		font_size: int, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = button_size
	btn.add_theme_font_size_override("font_size", font_size)
	# 背景の絵に埋もれないよう、ほぼ不透明の地にする
	btn.add_theme_stylebox_override("normal", flat_box(Color(0.05, 0.17, 0.12, 0.94)))
	btn.add_theme_stylebox_override("hover", flat_box(Color(0.09, 0.27, 0.19, 0.96)))
	btn.add_theme_stylebox_override("pressed", flat_box(Color(0.03, 0.11, 0.08, 0.98)))
	btn.add_theme_stylebox_override("disabled", flat_box(Color(0.05, 0.17, 0.12, 0.6)))
	btn.pressed.connect(on_pressed)
	parent.add_child(btn)
	return btn


## 手札などを画面中央ぞろえで並べるときの各カードの位置。per_row 枚ごとに折り返す。
static func row_positions(count: int, per_row: int, card_size: Vector2, top_y: float,
		gap: float = 4.0, row_gap: float = 8.0) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var step := card_size.x + gap
	for i in count:
		@warning_ignore("integer_division")
		var row := i / per_row
		var in_row := mini(per_row, count - row * per_row)
		var start_x := (screen().x - (in_row * step - gap)) / 2.0
		positions.append(Vector2(start_x + (i % per_row) * step, top_y + row * (card_size.y + row_gap)))
	return positions


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
