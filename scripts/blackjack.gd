extends GameBase
## ブラックジャック。あなた vs ディーラー。全5ラウンドでチップを増やす。
## ディーラーは合計17以上になるまで引く。最初の2枚で21ならブラックジャック（1.5倍）。

signal player_acted(action: String)

const ROUNDS := 5
const START_CHIPS := 100
const BET := 10
const BLACKJACK_PAY := 15
const DEALER_STAND := 17
const RESHUFFLE_BELOW := 15

# 配置。よこ画面は山札を右に、たて画面は中央に置く。
var card_size := Vector2(110, 154)
var pile_card := Vector2(90, 126)
var pile_center := Vector2(1120, 330)
var dealer_y := 96.0
var player_y := 368.0
var hand_max_width := 900.0

var deck: Array[Card] = []
var player: Array = []
var dealer: Array = []
var hole_hidden := true
var chips := START_CHIPS
var round_no := 0
var record := {"win": 0, "lose": 0, "push": 0}
var input_enabled := false
var waiting_next := false

var dealer_layer: Control
var player_layer: Control
var dealer_label: Label
var player_label: Label
var status_label: Label
var hit_button: Button
var stand_button: Button
var next_button: Button


func _ready() -> void:
	setup_base("ブラックジャック")
	var cx := screen.x / 2.0
	var button_y := 570.0
	var button_size := Vector2(220, 64)
	if portrait:
		card_size = Vector2(130, 182)
		pile_center = Vector2(cx, 450)
		dealer_y = 134.0
		player_y = 654.0
		hand_max_width = 660.0
		button_y = 900.0
		button_size = Vector2(300, 80)
		place_message(Vector2(0, 540), Vector2(screen.x, 44), 22)
	else:
		place_message(Vector2(140, 268), Vector2(840, 44), 26)

	status_label = UI.label(self, "", Vector2(screen.x - 450, 6), Vector2(300, 44), 18 if portrait else 20,
			HORIZONTAL_ALIGNMENT_RIGHT)
	dealer_label = UI.label(self, "", Vector2(0, dealer_y - 40), Vector2(screen.x, 36), 24)
	player_label = UI.label(self, "", Vector2(0, player_y - 40), Vector2(screen.x, 36), 24)
	dealer_layer = Control.new()
	add_child(dealer_layer)
	player_layer = Control.new()
	add_child(player_layer)

	hit_button = UI.button(self, "ヒット", Vector2(cx - button_size.x - 20, button_y), button_size, 30,
			_on_action.bind("hit"))
	stand_button = UI.button(self, "スタンド", Vector2(cx + 20, button_y), button_size, 30,
			_on_action.bind("stand"))
	next_button = UI.button(self, "", Vector2(cx - 170, button_y), Vector2(340, button_size.y), 28,
			_on_action.bind("next"))
	_run()


func _run() -> void:
	show_deck(pile_center, pile_card)
	for r in ROUNDS:
		round_no = r + 1
		await _play_round()
	_finish()


func _play_round() -> void:
	player.clear()
	dealer.clear()
	hole_hidden = true
	_show_buttons(false, false)
	_refresh()
	if deck.size() < RESHUFFLE_BELOW:
		deck = Card.make_deck()
	set_message("ラウンド %d　カードを配ります" % round_no)
	await wait(0.4)
	await _draw_to(player, true)
	await _draw_to(dealer, true)
	await _draw_to(player, true)
	await _draw_to(dealer, false)

	var outcome := ""
	if _value(player) == 21:
		# 最初の2枚で21
		await _reveal_hole()
		outcome = "push" if _value(dealer) == 21 else "blackjack"
	else:
		await _player_turn()
		if _value(player) > 21:
			outcome = "bust"
		else:
			await _dealer_turn()
			outcome = _compare()

	_settle(outcome)
	_refresh()
	if outcome == "blackjack":
		celebrate(null, true)
	next_button.text = "つぎのラウンドへ" if round_no < ROUNDS else "結果を見る"
	_show_buttons(false, true)
	waiting_next = true
	await player_acted
	waiting_next = false


func _player_turn() -> void:
	while _value(player) < 21:
		set_message("ヒット（もう1枚）か スタンド（勝負）を選んでください")
		_show_buttons(true, false)
		input_enabled = true
		var action: String = await player_acted
		input_enabled = false
		_show_buttons(false, false)
		if action == "stand":
			return
		await _draw_to(player, true)


func _dealer_turn() -> void:
	set_message("ディーラーの番です")
	await _reveal_hole()
	while _value(dealer) < DEALER_STAND:
		await wait(0.6)
		await _draw_to(dealer, true)
	await wait(0.4)


func _compare() -> String:
	var mine := _value(player)
	var theirs := _value(dealer)
	if theirs > 21:
		return "dealer_bust"
	# ディーラーだけが最初の2枚で21なら、こちらが3枚以上の21でも負け
	if theirs == 21 and dealer.size() == 2 and mine == 21:
		return "lose"
	if mine > theirs:
		return "win"
	if mine < theirs:
		return "lose"
	return "push"


func _settle(outcome: String) -> void:
	match outcome:
		"blackjack":
			chips += BLACKJACK_PAY
			record["win"] += 1
			set_message("ブラックジャック！　+%d" % BLACKJACK_PAY)
		"win":
			chips += BET
			record["win"] += 1
			set_message("あなたの勝ち！　+%d" % BET)
		"dealer_bust":
			chips += BET
			record["win"] += 1
			set_message("ディーラーがバースト！ あなたの勝ち　+%d" % BET)
		"bust":
			chips -= BET
			record["lose"] += 1
			set_message("バースト…（21をこえた）　-%d" % BET)
		"lose":
			chips -= BET
			record["lose"] += 1
			set_message("ディーラーの勝ち…　-%d" % BET)
		_:
			record["push"] += 1
			set_message("引き分け")


## 山札から1枚、手札の次の場所へ配る。
func _draw_to(hand: Array, face_up: bool) -> void:
	if deck.is_empty():
		deck = Card.make_deck()
	var card: Card = deck.pop_back()
	var is_player := is_same(hand, player)
	var landing := _hand_positions(hand.size() + 1, player_y if is_player else dealer_y)
	await fly_card(card, pile_center - pile_card / 2.0, landing[landing.size() - 1], pile_card, card_size, false, 0.3)
	hand.append(card)
	_refresh()
	if face_up:
		# 着いたところでめくる
		var layer := player_layer if is_player else dealer_layer
		var view: CardView = layer.get_child(layer.get_child_count() - 1)
		view.set_face_up(false)
		view.flip(true)
		await wait(0.25)


func _reveal_hole() -> void:
	if not hole_hidden:
		return
	hole_hidden = false
	_refresh()
	var view: CardView = dealer_layer.get_child(1)
	view.set_face_up(false)
	view.flip(true)
	await wait(0.5)


## 合計。Aは11として数え、21をこえるなら1に数え直す。
func _value(hand: Array) -> int:
	var total := 0
	var aces := 0
	for card: Card in hand:
		if card.rank == 1:
			aces += 1
			total += 11
		else:
			total += mini(card.rank, 10)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


func _hand_positions(count: int, y: float) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var step := minf(card_size.x + 10, (hand_max_width - card_size.x) / maxf(count - 1, 1))
	var start_x := (screen.x - (step * (count - 1) + card_size.x)) / 2.0
	for i in count:
		positions.append(Vector2(start_x + i * step, y))
	return positions


func _on_action(action: String) -> void:
	if action == "next":
		if waiting_next:
			player_acted.emit(action)
	elif input_enabled:
		player_acted.emit(action)


func _show_buttons(playing: bool, next: bool) -> void:
	hit_button.visible = playing
	stand_button.visible = playing
	next_button.visible = next


func _refresh() -> void:
	_fill(dealer_layer, dealer, dealer_y, true)
	_fill(player_layer, player, player_y, false)
	status_label.text = "ラウンド %d/%d　チップ %d" % [round_no, ROUNDS, chips]
	player_label.text = "あなた　%s" % _value_text(player)
	if dealer.is_empty():
		dealer_label.text = "ディーラー"
	elif hole_hidden and dealer.size() >= 2:
		dealer_label.text = "ディーラー　%d + ？" % _value([dealer[0]])
	else:
		dealer_label.text = "ディーラー　%s" % _value_text(dealer)


func _value_text(hand: Array) -> String:
	if hand.is_empty():
		return ""
	var total := _value(hand)
	if total > 21:
		return "%d（バースト）" % total
	if total == 21 and hand.size() == 2:
		return "21（ブラックジャック）"
	return str(total)


func _fill(layer: Control, hand: Array, y: float, is_dealer: bool) -> void:
	UI.clear_children(layer)
	var positions := _hand_positions(hand.size(), y)
	for i in hand.size():
		var view := CardView.new()
		layer.add_child(view)
		view.setup(hand[i], card_size, not (is_dealer and hole_hidden and i == 1))
		view.position = positions[i]


func _finish() -> void:
	var lines := [
		"チップ　%d → %d" % [START_CHIPS, chips],
		"%d勝 %d敗 %d分" % [record["win"], record["lose"], record["push"]],
	]
	if chips > START_CHIPS:
		show_result("あなたの勝ち！", lines, true)
	elif chips < START_CHIPS:
		show_result("負けこし…", lines)
	else:
		show_result("引き分け", lines)
