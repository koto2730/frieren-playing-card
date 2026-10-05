class_name CardView
extends TextureButton
## カード1枚の見た目。表裏の切り替えとクリックを扱う。

const BACK: Texture2D = preload("res://assets/cards/back_blue.svg")
const DIM_COLOR := Color(0.5, 0.5, 0.5)
const SVG_WIDTH := 250.0
const RED := Color("d40000")
const BLACK := Color("111111")


var card: Card
var face_up := true


func setup(c: Card, card_size: Vector2, up: bool = true) -> void:
	card = c
	face_up = up
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = card_size
	size = card_size
	pivot_offset = card_size / 2.0
	_refresh()
	set_clickable(false)


func set_face_up(up: bool) -> void:
	face_up = up
	_refresh()


## めくるアニメーション付きで表裏を切り替える。
func flip(up: bool) -> void:
	if up == face_up:
		return
	var tween := create_tween()
	tween.tween_property(self, "scale:x", 0.0, 0.1)
	tween.tween_callback(set_face_up.bind(up))
	tween.tween_property(self, "scale:x", 1.0, 0.1)


func set_clickable(clickable: bool) -> void:
	disabled = not clickable
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW


func set_dimmed(dimmed: bool) -> void:
	modulate = DIM_COLOR if dimmed else Color.WHITE


func _refresh() -> void:
	if face_up and card != null:
		texture_normal = load(card.texture_path())
	else:
		texture_normal = BACK
	queue_redraw()


## GodotのSVG読み込みは <text> を描かないので、隅の数字はここで描き足す。
## 座標はSVGと同じ 250x350 基準。
func _draw() -> void:
	if not face_up or card == null:
		return
	var s := size.x / SVG_WIDTH
	_draw_index(s)
	draw_set_transform(size, PI)  # 右下は180度回して同じものを描く
	_draw_index(s)
	draw_set_transform(Vector2.ZERO)


func _draw_index(s: float) -> void:
	if card.is_joker():
		for i in 5:
			_draw_centered("JOKER"[i], Vector2(26, 36 + i * 19) * s, roundi(18 * s), BLACK)
		return
	var text: String = Card.RANK_NAMES[card.rank - 1]
	var color := RED if card.suit == 1 or card.suit == 2 else BLACK
	_draw_centered(text, Vector2(26, 42) * s, roundi((26 if text.length() > 1 else 30) * s), color)


func _draw_centered(text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, baseline_center - Vector2(width / 2.0, 0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
