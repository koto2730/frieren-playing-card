extends GameBase
## 七ならべ。あなた＋CPU3人。パスは3回まで、4回目が必要になったら脱落。

signal human_acted

enum { PLAYING, FINISHED, ELIMINATED }

const NAMES := ["あなた", "CPU 1", "CPU 2", "CPU 3"]
const MAX_PASS := 3

# 配置。よこ画面は 13列x4段、たて画面はマークごとの縦列にカードを重ねて並べる。
var board_origin := Vector2(40, 64)
var board_cell := Vector2(66, 92)
var board_card := Vector2(62, 87)
var hand_card := Vector2(84, 118)
var hand_per_row := 13
var hand_y := 586.0

var hands: Array = [[], [], [], []]
var placed := {}
var passes := [0, 0, 0, 0]
var state := [PLAYING, PLAYING, PLAYING, PLAYING]
var finished_order: Array[int] = []
var eliminated_order: Array[int] = []
var current := 0
var input_enabled := false

var board_layer: Control
var hand_layer: Control
var info_labels: Array[Label] = []
var pass_button: Button


func _ready() -> void:
	setup_base("七ならべ")
	if portrait:
		board_card = Vector2(150, 210)
		board_cell = Vector2(165, 40)
		board_origin = Vector2((screen.x - (3 * board_cell.x + board_card.x)) / 2.0, 60)
		hand_card = Vector2(96, 134)
		hand_per_row = 7
		hand_y = 968.0
		place_message(Vector2(0, 756), Vector2(screen.x, 44), 24)
	else:
		place_message(Vector2(40, 446), Vector2(860, 44), 26)

	_build_board()
	hand_layer = Control.new()
	add_child(hand_layer)
	for i in NAMES.size():
		if portrait:
			@warning_ignore("integer_division")
			info_labels.append(UI.label(self, "", Vector2(14 + (i % 2) * 350, 804 + (i / 2) * 42),
					Vector2(346, 40), 20, HORIZONTAL_ALIGNMENT_LEFT))
		else:
			info_labels.append(UI.label(self, "", Vector2(930, 70 + i * 56), Vector2(330, 48), 22,
					HORIZONTAL_ALIGNMENT_LEFT))
	if portrait:
		pass_button = UI.button(self, "パス", Vector2(410, 896), Vector2(290, 54), 26, _on_pass)
		UI.label(self, "あなたの手札", Vector2(20, 905), Vector2(300, 36), 20, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		pass_button = UI.button(self, "パス", Vector2(960, 440), Vector2(260, 56), 26, _on_pass)
		UI.label(self, "あなたの手札", Vector2(40, 540), Vector2(300, 36), 20, HORIZONTAL_ALIGNMENT_LEFT)

	_deal()
	_run()


func _build_board() -> void:
	board_layer = Control.new()
	add_child(board_layer)
	for s in 4:
		for r in range(1, 14):
			var slot := ColorRect.new()
			slot.color = Color(0, 0, 0, 0.18)
			slot.position = _cell_position(s, r)
			slot.size = board_card
			if portrait and r < 13:
				slot.size.y = board_cell.y - 3
			board_layer.add_child(slot)


func _cell_position(suit: int, rank: int) -> Vector2:
	if portrait:
		return board_origin + Vector2(suit * board_cell.x, (rank - 1) * board_cell.y)
	return board_origin + Vector2((rank - 1) * board_cell.x, suit * board_cell.y)


func _deal() -> void:
	var deck := Card.make_deck()
	for i in deck.size():
		hands[i % 4].append(deck[i])
	# 7は最初に全部場に出す。ダイヤの7を持っていた人から始める。
	for p in 4:
		for card: Card in hands[p].duplicate():
			if card.rank == 7:
				if card.suit == 2:
					current = p
				hands[p].erase(card)
				_place(card)
		hands[p].sort_custom(func(a: Card, b: Card) -> bool: return a.suit * 100 + a.rank < b.suit * 100 + b.rank)


func _run() -> void:
	set_message("%s から始めます" % NAMES[current])
	_refresh()
	await wait(1.0)
	while _playing_count() > 1:
		if state[current] == PLAYING:
			_refresh()
			if current == 0:
				await _human_turn()
			else:
				await _cpu_turn(current)
		current = (current + 1) % 4
	_finish()


func _human_turn() -> void:
	var playable := _playable(0)
	if playable.is_empty() and passes[0] >= MAX_PASS:
		set_message("出せるカードがなく、パスも使い切りました…")
		await wait(1.6)
		_eliminate(0)
		return
	if playable.is_empty():
		set_message("出せるカードがありません。パスしてください")
	else:
		set_message("あなたの番です。出すカードを選んでください")
	input_enabled = true
	_refresh()
	await human_acted
	input_enabled = false
	_refresh()


func _cpu_turn(p: int) -> void:
	await wait(0.6 if state[0] == PLAYING else 0.15)
	var playable := _playable(p)
	if playable.is_empty():
		if passes[p] >= MAX_PASS:
			set_message("%s は出せず脱落…" % NAMES[p])
			_eliminate(p)
		else:
			passes[p] += 1
			set_message("%s はパス" % NAMES[p])
		return
	var card := _cpu_choose(p, playable)
	_play(p, card)
	set_message("%s が %s を出した" % [NAMES[p], card.label()])


## 自分がその先のカードを多く持っている列を優先して開ける。
func _cpu_choose(p: int, playable: Array) -> Card:
	var best: Array = []
	var best_score := -1
	for card: Card in playable:
		var score := 0
		for other: Card in hands[p]:
			if other.suit != card.suit:
				continue
			if (card.rank < 7 and other.rank < card.rank) or (card.rank > 7 and other.rank > card.rank):
				score += 1
		if score > best_score:
			best_score = score
			best = [card]
		elif score == best_score:
			best.append(card)
	return best.pick_random()


func _key(suit: int, rank: int) -> int:
	return suit * 100 + rank


func _can_place(card: Card) -> bool:
	if card.rank < 7:
		return placed.has(_key(card.suit, card.rank + 1))
	return placed.has(_key(card.suit, card.rank - 1))


func _playable(p: int) -> Array:
	return hands[p].filter(_can_place)


func _place(card: Card) -> void:
	placed[_key(card.suit, card.rank)] = true
	var view := CardView.new()
	board_layer.add_child(view)
	view.setup(card, board_card)
	view.position = _cell_position(card.suit, card.rank)
	view.z_index = card.rank  # たて画面では数字の大きいカードが手前に重なる


func _play(p: int, card: Card) -> void:
	hands[p].erase(card)
	_place(card)
	if hands[p].is_empty():
		state[p] = FINISHED
		finished_order.append(p)


## 脱落した人の手札はすべて場に置かれる。
func _eliminate(p: int) -> void:
	for card: Card in hands[p]:
		_place(card)
	hands[p].clear()
	state[p] = ELIMINATED
	eliminated_order.append(p)


func _playing_count() -> int:
	return state.count(PLAYING)


func _on_card_pressed(card: Card) -> void:
	if not input_enabled or not _can_place(card):
		return
	_play(0, card)
	set_message("あなたが %s を出した" % card.label())
	human_acted.emit()


func _on_pass() -> void:
	if not input_enabled or passes[0] >= MAX_PASS:
		return
	passes[0] += 1
	set_message("あなたはパス")
	human_acted.emit()


func _refresh() -> void:
	UI.clear_children(hand_layer)
	var hand: Array = hands[0]
	var positions := UI.row_positions(hand.size(), hand_per_row, hand_card, hand_y)
	for i in hand.size():
		var card: Card = hand[i]
		var view := CardView.new()
		hand_layer.add_child(view)
		view.setup(card, hand_card)
		view.position = positions[i]
		var can_play := input_enabled and _can_place(card)
		view.set_clickable(can_play)
		view.set_dimmed(input_enabled and not can_play)
		view.pressed.connect(_on_card_pressed.bind(card))

	for p in 4:
		var text := ""
		match state[p]:
			PLAYING:
				text = "%s  残り%d枚  パス %d/%d" % [NAMES[p], hands[p].size(), passes[p], MAX_PASS]
			FINISHED:
				text = "%s  あがり（%d位）" % [NAMES[p], finished_order.find(p) + 1]
			ELIMINATED:
				text = "%s  脱落" % NAMES[p]
		info_labels[p].text = ("▶ " if p == current and state[p] == PLAYING else "　 ") + text
		info_labels[p].modulate = Color.YELLOW if p == current and state[p] == PLAYING else Color.WHITE

	pass_button.text = "パス（残り%d回）" % (MAX_PASS - passes[0])
	pass_button.disabled = not input_enabled or passes[0] >= MAX_PASS


func _finish() -> void:
	# 順位: あがった順 → 最後まで残った人 → 脱落した人（後に脱落した方が上）
	var order: Array[int] = finished_order.duplicate()
	for p in 4:
		if state[p] == PLAYING:
			order.append(p)
	var eliminated := eliminated_order.duplicate()
	eliminated.reverse()
	order.append_array(eliminated)
	current = -1
	_refresh()

	var lines: Array = []
	for i in order.size():
		var p := order[i]
		lines.append("%d位  %s%s" % [i + 1, NAMES[p], "（脱落）" if state[p] == ELIMINATED else ""])
	var my_rank := order.find(0) + 1
	show_result("あなたは %d位！" % my_rank, lines)
