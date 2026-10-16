extends Control
## ルール選択画面。ゲームを追加するときは RULES に1行足す。

const RULES := [
	{
		"name": "七ならべ",
		"scene": "res://scenes/sevens.tscn",
		"desc": "7を起点に、同じマークの\n隣の数字を並べていく。\nパスは3回まで。\n（あなた＋CPU3人）",
	},
	{
		"name": "ババ抜き",
		"scene": "res://scenes/old_maid.tscn",
		"desc": "隣の人から1枚引いて、\n同じ数字のペアを捨てる。\n最後にジョーカーを\n持っていた人の負け。",
	},
	{
		"name": "神経衰弱",
		"scene": "res://scenes/memory.tscn",
		"desc": "2枚めくって同じ数字なら\nもらえて、もう1回。\n多く取った方の勝ち。\n（あなた vs CPU）",
	},
	{
		"name": "ブラックジャック",
		"scene": "res://scenes/blackjack.tscn",
		"desc": "合計を21に近づける。\nヒットで1枚引き、\nスタンドで勝負。\n（全5ラウンド）",
	},
	{
		"name": "ダウト",
		"scene": "res://scenes/doubt.tscn",
		"desc": "A,2,3…の順に裏向きで\n出す。うそもOK。\nあやしいと思ったら\n「ダウト！」",
	},
	{
		"name": "ポーカー",
		"scene": "res://scenes/poker.tscn",
		"desc": "5枚で役を作る。\n交換は1回だけ。\n全5ラウンドの合計点で\n勝負。",
	},
]

## パネルの並べ方とパネル内の配置。よこ画面は3列x2段、たて画面は2列x3段に並べる。
## よこ画面はパネルが低いので、「あそぶ」は右下、CPUのつよさは左下に置く。
const LAYOUT_LANDSCAPE := {
	"columns": 3, "panel": Vector2(390, 222), "gap": 16.0, "top": 140.0,
	"name_y": 8.0, "name_h": 46.0, "name_font": 30,
	"desc_x": 14.0, "desc_y": 54.0, "desc_w": 250.0, "desc_h": 100.0, "desc_font": 16, "desc_align": "left",
	"option_x": 14.0, "option_y": 178.0, "option_w": 230.0, "option_font": 16, "option_title_font": 14,
	"play": Rect2(258, 158, 118, 52), "play_font": 24,
}
const LAYOUT_PORTRAIT := {
	"columns": 2, "panel": Vector2(340, 330), "gap": 14.0, "top": 120.0,
	"name_y": 14.0, "name_h": 50.0, "name_font": 32,
	"desc_x": 12.0, "desc_y": 66.0, "desc_w": 316.0, "desc_h": 120.0, "desc_font": 19, "desc_align": "center",
	"option_x": 12.0, "option_y": 214.0, "option_w": 316.0, "option_font": 18, "option_title_font": 16,
	"play": Rect2(70, 264, 200, 54), "play_font": 26,
}

var layout: Dictionary


func _ready() -> void:
	UI.apply_orientation(get_tree())
	var p := Settings.portrait
	var screen := UI.screen()
	layout = LAYOUT_PORTRAIT if p else LAYOUT_LANDSCAPE
	var panel_size: Vector2 = layout["panel"]
	UI.background(self)
	UI.card_backdrop(self, 0.55)
	UI.outline(UI.label(self, "ルールをえらぶ", Vector2(0, 30 if p else 36), Vector2(screen.x, 80), 52), 12)

	var columns: int = layout["columns"]
	var gap: float = layout["gap"]
	var top: float = layout["top"]
	var start_x := (screen.x - (columns * panel_size.x + (columns - 1) * gap)) / 2.0
	for i in RULES.size():
		var rule: Dictionary = RULES[i]
		@warning_ignore("integer_division")
		var pos := Vector2(start_x + (i % columns) * (panel_size.x + gap), top + (i / columns) * (panel_size.y + gap))
		var panel := UI.panel(self, pos, panel_size)
		UI.label(panel, rule["name"], Vector2(0, layout["name_y"]), Vector2(panel_size.x, layout["name_h"]),
				layout["name_font"])
		var desc := UI.label(panel, rule["desc"], Vector2(layout["desc_x"], layout["desc_y"]),
				Vector2(layout["desc_w"], layout["desc_h"]), layout["desc_font"],
				HORIZONTAL_ALIGNMENT_LEFT if layout["desc_align"] == "left" else HORIZONTAL_ALIGNMENT_CENTER)
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		match rule["scene"]:
			"res://scenes/memory.tscn":
				_build_selector(panel, "CPUのつよさ", Settings.MEMORY_CPU_LEVELS, Settings.memory_cpu_level,
						_set_memory_cpu)
			"res://scenes/poker.tscn":
				_build_selector(panel, "ジョーカー", Settings.POKER_JOKER_OPTIONS, Settings.poker_joker_option,
						_set_poker_jokers)
		var play: Rect2 = layout["play"]
		UI.button(panel, "あそぶ", play.position, play.size, layout["play_font"], _start.bind(rule["scene"]))

	UI.button(self, "タイトルへ", Vector2(screen.x / 2.0 - 100, 1170 if p else 626), Vector2(200, 50), 22,
			_back_to_title)


## パネルの下に、いくつかの中から1つを選ぶボタンを並べる。
func _build_selector(panel: Panel, title: String, options: Array, current: int, on_select: Callable) -> void:
	var option_x: float = layout["option_x"]
	var option_y: float = layout["option_y"]
	var option_w: float = layout["option_w"]
	var title_label := UI.label(panel, title, Vector2(option_x, option_y - 22), Vector2(option_w, 20),
			layout["option_title_font"])
	title_label.modulate = Color(0.85, 0.85, 0.85)
	var spacing := 4.0
	var button_size := Vector2(minf(100, (option_w - spacing * (options.size() - 1)) / options.size()), 38)
	var start_x := option_x + (option_w - (options.size() * (button_size.x + spacing) - spacing)) / 2.0
	var buttons: Array[Button] = []
	for i in options.size():
		buttons.append(UI.button(panel, options[i]["name"], Vector2(start_x + i * (button_size.x + spacing), option_y),
				button_size, layout["option_font"], _on_selector.bind(i, buttons, options, on_select)))
	_on_selector(current, buttons, options, on_select)


func _on_selector(index: int, buttons: Array[Button], options: Array, on_select: Callable) -> void:
	on_select.call(index)
	for i in buttons.size():
		buttons[i].modulate = Color.YELLOW if i == index else Color(0.7, 0.7, 0.7)
		buttons[i].text = ("● " if i == index else "") + options[i]["name"]


func _set_memory_cpu(index: int) -> void:
	Settings.memory_cpu_level = index


func _set_poker_jokers(index: int) -> void:
	Settings.poker_joker_option = index


func _start(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _back_to_title() -> void:
	get_tree().change_scene_to_file(UI.SCENE_TITLE)
