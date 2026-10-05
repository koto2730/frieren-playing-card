extends GameBase
## 神経衰弱。あなた vs CPU。同じ数字の2枚をめくれば取れて、もう一度めくれる。

signal human_picked(index: int)

const NAMES := ["あなた", "CPU"]

# 配置。よこ画面は13列x4段、たて画面は7列x8段。
var columns := 13
var card_size := Vector2(80, 112)
var cell := Vector2(88, 120)
var origin := Vector2(72, 66)

var cpu_remember_rate := 0.5  # CPUがめくられたカードを覚えている確率
var cards: Array[Card] = []
var views: Array[CardView] = []
var removed: Array[bool] = []
var cpu_memory := {}  # 位置 -> 数字
var scores := [0, 0]
var turn := 0
var input_enabled := false
var first_pick := -1
var score_labels: Array[Label] = []


func _ready() -> void:
	setup_base("神経衰弱")
	var level: Dictionary = Settings.MEMORY_CPU_LEVELS[Settings.memory_cpu_level]
	cpu_remember_rate = level["rate"]
	UI.label(self, "CPU: %s" % level["name"], Vector2(screen.x - 380, 6), Vector2(220, 44), 20,
			HORIZONTAL_ALIGNMENT_RIGHT)
	if portrait:
		columns = 7
		card_size = Vector2(92, 128)
		cell = Vector2(100, 136)
		origin = Vector2(14, 58)
		place_message(Vector2(0, 1146), Vector2(screen.x, 44), 22)
		score_labels.append(UI.label(self, "", Vector2(10, 1198), Vector2(340, 60), 30))
		score_labels.append(UI.label(self, "", Vector2(370, 1198), Vector2(340, 60), 30))
	else:
		place_message(Vector2(140, 556), Vector2(1000, 44), 26)
		score_labels.append(UI.label(self, "", Vector2(240, 620), Vector2(360, 60), 34))
		score_labels.append(UI.label(self, "", Vector2(680, 620), Vector2(360, 60), 34))

	cards = Card.make_deck()
	for i in cards.size():
		var view := CardView.new()
		add_child(view)
		view.setup(cards[i], card_size, false)
		@warning_ignore("integer_division")
		view.position = origin + Vector2((i % columns) * cell.x, (i / columns) * cell.y)
		view.set_clickable(true)
		view.pressed.connect(_on_card_pressed.bind(i))
		views.append(view)
		removed.append(false)
	_run()


func _run() -> void:
	var remaining := cards.size()
	while remaining > 0:
		_refresh_scores()
		set_message("あなたの番です。2枚めくってください" if turn == 0 else "CPU の番です")
		first_pick = -1
		var a := await _pick()
		_reveal(a)
		first_pick = a
		var b := await _pick()
		_reveal(b)
		await wait(1.0)

		if cards[a].rank == cards[b].rank:
			scores[turn] += 1
			remaining -= 2
			for i: int in [a, b]:
				removed[i] = true
				views[i].visible = false
				cpu_memory.erase(i)
			set_message("%s が %s のペアを取った！ もう1回" % [NAMES[turn], Card.RANK_NAMES[cards[a].rank - 1]])
			_refresh_scores()
			await wait(0.6)
		else:
			views[a].flip(false)
			views[b].flip(false)
			turn = 1 - turn
			await wait(0.4)
	_finish()


func _pick() -> int:
	if turn == 0:
		input_enabled = true
		var index: int = await human_picked
		input_enabled = false
		return index
	await wait(0.8)
	return _cpu_pick()


func _reveal(index: int) -> void:
	views[index].flip(true)
	if randf() < cpu_remember_rate:
		cpu_memory[index] = cards[index].rank


func _cpu_pick() -> int:
	if first_pick < 0:
		# 覚えている中にペアがあれば、まずその片方をめくる
		var seen := {}
		for index: int in cpu_memory:
			var rank: int = cpu_memory[index]
			if seen.has(rank):
				return index
			seen[rank] = index
		return _random_card(-1)
	for index: int in cpu_memory:
		if index != first_pick and cpu_memory[index] == cards[first_pick].rank:
			return index
	return _random_card(first_pick)


## まだ覚えていないカードを優先してランダムに選ぶ。
func _random_card(exclude: int) -> int:
	var unknown: Array[int] = []
	var available: Array[int] = []
	for i in cards.size():
		if removed[i] or i == exclude:
			continue
		available.append(i)
		if not cpu_memory.has(i):
			unknown.append(i)
	return unknown.pick_random() if not unknown.is_empty() else available.pick_random()


func _on_card_pressed(index: int) -> void:
	if not input_enabled or removed[index] or index == first_pick:
		return
	human_picked.emit(index)


func _refresh_scores() -> void:
	for i in 2:
		score_labels[i].text = "%s%s  %d組" % ["▶ " if i == turn else "", NAMES[i], scores[i]]
		score_labels[i].modulate = Color.YELLOW if i == turn else Color.WHITE


func _finish() -> void:
	var lines := ["あなた  %d組" % scores[0], "CPU  %d組" % scores[1]]
	if scores[0] > scores[1]:
		show_result("あなたの勝ち！", lines)
	elif scores[0] < scores[1]:
		show_result("CPU の勝ち…", lines)
	else:
		show_result("引き分け", lines)
