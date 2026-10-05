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
]

## パネル内の配置。よこ画面は横に3枚、たて画面は縦に積む。
const LAYOUT_LANDSCAPE := {
	"panel": Vector2(360, 400), "gap": 40.0, "top": 160.0,
	"name_y": 20.0, "name_h": 70.0, "name_font": 44,
	"desc_y": 92.0, "desc_font": 20, "option_y": 226.0, "play_y": 320.0, "play_h": 60.0,
}
const LAYOUT_PORTRAIT := {
	"panel": Vector2(640, 330), "gap": 15.0, "top": 120.0,
	"name_y": 8.0, "name_h": 56.0, "name_font": 40,
	"desc_y": 60.0, "desc_font": 20, "option_y": 190.0, "play_y": 266.0, "play_h": 54.0,
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
	UI.outline(UI.label(self, "ルールをえらぶ", Vector2(0, 30 if p else 40), Vector2(screen.x, 80), 52), 12)

	var gap: float = layout["gap"]
	var top: float = layout["top"]
	var total_width := RULES.size() * panel_size.x + (RULES.size() - 1) * gap
	for i in RULES.size():
		var rule: Dictionary = RULES[i]
		var pos := Vector2((screen.x - total_width) / 2.0 + i * (panel_size.x + gap), top)
		if p:
			pos = Vector2((screen.x - panel_size.x) / 2.0, top + i * (panel_size.y + gap))
		var panel := UI.panel(self, pos, panel_size)
		UI.label(panel, rule["name"], Vector2(0, layout["name_y"]), Vector2(panel_size.x, layout["name_h"]),
				layout["name_font"])
		UI.label(panel, rule["desc"], Vector2(20, layout["desc_y"]), Vector2(panel_size.x - 40, 120), layout["desc_font"])
		if rule["scene"] == "res://scenes/memory.tscn":
			_build_memory_cpu_selector(panel)
		UI.button(panel, "あそぶ", Vector2((panel_size.x - 200) / 2.0, layout["play_y"]),
				Vector2(200, layout["play_h"]), 28, _start.bind(rule["scene"]))

	UI.button(self, "タイトルへ", Vector2(screen.x / 2.0 - 100, 1170 if p else 620), Vector2(200, 50), 22,
			_back_to_title)


func _build_memory_cpu_selector(panel: Panel) -> void:
	var option_y: float = layout["option_y"]
	UI.label(panel, "CPUのつよさ", Vector2(0, option_y), Vector2(panel.size.x, 28), 18)
	var levels := Settings.MEMORY_CPU_LEVELS
	var button_size := Vector2(100, 40)
	var start_x := (panel.size.x - (levels.size() * (button_size.x + 10) - 10)) / 2.0
	var buttons: Array[Button] = []
	for i in levels.size():
		buttons.append(UI.button(panel, levels[i]["name"], Vector2(start_x + i * (button_size.x + 10), option_y + 30),
				button_size, 20, _select_memory_cpu.bind(i, buttons)))
	_select_memory_cpu(Settings.memory_cpu_level, buttons)


func _select_memory_cpu(level: int, buttons: Array[Button]) -> void:
	Settings.memory_cpu_level = level
	for i in buttons.size():
		buttons[i].modulate = Color.YELLOW if i == level else Color(0.7, 0.7, 0.7)
		buttons[i].text = ("● " if i == level else "") + Settings.MEMORY_CPU_LEVELS[i]["name"]


func _start(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _back_to_title() -> void:
	get_tree().change_scene_to_file(UI.SCENE_TITLE)
