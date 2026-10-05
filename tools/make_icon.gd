extends SceneTree
## アプリアイコンを作る。カードを扇形に並べて描画し、PNGで保存する。
## 実行: godot --path . --script res://tools/make_icon.gd  （描画が必要なので --headless は付けない）

const ICON_SIZE := 512
const OUTPUT := "res://assets/icon/app_icon.png"
const CARD_SIZE := Vector2(200, 280)
## [マーク, 数字, 横ずれ, 縦ずれ, 角度, 重なり順]  マーク: 0=♠ 1=♥ 2=♦ 3=♣
const CARDS := [
	[0, 1, -95.0, 14.0, -18.0, 0],
	[2, 12, 95.0, 14.0, 18.0, 1],
	[1, 13, 0.0, 0.0, 0.0, 2],
]


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var background := ColorRect.new()
	background.color = UI.TABLE_COLOR
	background.size = Vector2(ICON_SIZE, ICON_SIZE)
	viewport.add_child(background)

	var center := Vector2(ICON_SIZE, ICON_SIZE) / 2.0
	for entry: Array in CARDS:
		var view := CardView.new()
		viewport.add_child(view)
		view.setup(Card.new(entry[0], entry[1]), CARD_SIZE)
		view.position = center - CARD_SIZE / 2.0 + Vector2(entry[2], entry[3])
		view.rotation_degrees = entry[4]
		view.z_index = entry[5]

	for i in 4:
		await process_frame
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var error := image.save_png(OUTPUT)
	print("saved " + OUTPUT if error == OK else "FAILED to save icon: %d" % error)
	quit()
