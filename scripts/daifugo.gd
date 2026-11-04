extends GameBase
## 大富豪（大貧民）。あなた＋CPU3人。
## 場に出ている手より強いカードを、同じ枚数・同じ形で出していく。出せない・出したくないときはパス。
## ほかの全員がパスすると場が流れ、最後に出した人から再開。先に手札をなくした人から上がり。
## 強さは 3 < 4 < … < K < A < 2 < ジョーカー。地方ルールはゲームの前に選ぶ（Settings.GAME_OPTIONS）。

signal human_acted(cards: Array)  # 空の配列ならパス
signal next_pressed

const NAMES := ["あなた", "CPU 1", "CPU 2", "CPU 3"]
const TITLES := ["大富豪", "富豪", "貧民", "大貧民"]
const PLACE_POINTS := [3, 2, 1, 0]
const JOKER_STRENGTH := 13

# 地方ルール
var rounds := 3
var joker_count := 1
var rule_revolution := true
var rule_eight := true
var rule_stairs := true
var rule_eleven := false
var rule_shibari := false
var rule_spade3 := false
var rule_miyako := false
var rule_exchange := true

# 配置。よこ画面はCPUを横に3人、たて画面は縦に3段並べる。
var cpu_card := Vector2(64, 90)
var cpu_panel_width := 400.0
var hand_card := Vector2(84, 118)
var hand_y := 586.0
var field_center := Vector2(640, 300)
var field_card := Vector2(84, 118)

var hands: Array = [[], [], [], []]
var done := [false, false, false, false]
var finish_order: Array[int] = []
var fallen := -1  # 都落ちした人
var titles := [-1, -1, -1, -1]  # 前のラウンドの階級（0 が大富豪）
var points := [0, 0, 0, 0]
var round_no := 0

var field := {}  # 場に出ている手（_analyze の結果）
var field_owner := -1
var passed := [false, false, false, false]
var revolution := false
var eleven_back := false
var bound_suits: Array = []
var current := 0

var selected: Array = []
var input_mode := ""  # "play"（出す）/ "give"（交換でわたす）/ ""
var give_count := 0

var cpu_layers: Array[Control] = []
var cpu_labels: Array[Label] = []
var hand_layer: Control
var hand_label: Label
var field_layer: Control
var field_label: Label
var badge_label: Label
var status_label: Label
var play_button: Button
var pass_button: Button
var hand_views := {}  # Card -> CardView


func _ready() -> void:
	setup_base("大富豪")
	rounds = Settings.get_value("daifugo_rounds")
	joker_count = Settings.get_value("daifugo_jokers")
	rule_revolution = Settings.get_value("daifugo_revolution")
	rule_eight = Settings.get_value("daifugo_eight")
	rule_stairs = Settings.get_value("daifugo_stairs")
	rule_eleven = Settings.get_value("daifugo_eleven")
	rule_shibari = Settings.get_value("daifugo_shibari")
	rule_spade3 = Settings.get_value("daifugo_spade3")
	rule_miyako = Settings.get_value("daifugo_miyako")
	rule_exchange = Settings.get_value("daifugo_exchange")

	var badge_pos := Vector2(40, 236)
	if portrait:
		cpu_card = Vector2(80, 112)
		cpu_panel_width = 680.0
		hand_card = Vector2(96, 134)
		hand_y = 876.0
		field_center = Vector2(360, 610)
		badge_pos = Vector2(20, 528)
		place_message(Vector2(0, 706), Vector2(screen.x, 40), 22)
	else:
		place_message(Vector2(40, 420), Vector2(900, 40), 24)

	status_label = UI.label(self, "", Vector2(screen.x - 450, 6), Vector2(300, 44), 18 if portrait else 20,
			HORIZONTAL_ALIGNMENT_RIGHT)
	for p in range(1, 4):
		var pos := Vector2(20, 60 + (p - 1) * 152.0) if portrait else Vector2(20 + (p - 1) * 420.0, 64)
		cpu_labels.append(UI.label(self, "", pos, Vector2(cpu_panel_width, 36), 20))
		var layer := Control.new()
		layer.position = pos + Vector2(0, 38 if portrait else 46)
		add_child(layer)
		cpu_layers.append(layer)

	field_layer = Control.new()
	add_child(field_layer)
	field_label = UI.label(self, "", Vector2(field_center.x - 200, field_center.y + field_card.y / 2.0 + 2),
			Vector2(400, 28), 18)
	badge_label = UI.outline(UI.label(self, "", badge_pos, Vector2(300, 80), 22, HORIZONTAL_ALIGNMENT_LEFT), 8)
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	badge_label.modulate = Color("ffd84a")

	hand_label = UI.label(self, "", Vector2(20, 836) if portrait else Vector2(40, 516), Vector2(500, 36), 20,
			HORIZONTAL_ALIGNMENT_LEFT)
	hand_layer = Control.new()
	add_child(hand_layer)
	if portrait:
		play_button = UI.button(self, "出す", Vector2(60, 754), Vector2(290, 60), 26, _on_play)
		pass_button = UI.button(self, "パス", Vector2(370, 754), Vector2(290, 60), 26, _on_pass)
	else:
		play_button = UI.button(self, "出す", Vector2(960, 410), Vector2(150, 56), 26, _on_play)
		pass_button = UI.button(self, "パス", Vector2(1120, 410), Vector2(140, 56), 24, _on_pass)
	_update_buttons()
	_run()


func _run() -> void:
	for r in rounds:
		round_no = r + 1
		await _play_round()
		if round_no < rounds:
			await _show_round_summary()
	_finish()


# ---------------------------------------------------------------- ラウンドの流れ

func _play_round() -> void:
	hands = [[], [], [], []]
	done = [false, false, false, false]
	finish_order.clear()
	fallen = -1
	revolution = false
	_reset_field()
	await _deal()
	if round_no > 1 and rule_exchange:
		await _exchange()
	current = _first_player()
	set_message("%s から始めます" % NAMES[current])
	_refresh()
	await wait(0.8)
	await _play_tricks()
	_record_round()


func _deal() -> void:
	var deck := Card.make_deck(joker_count)
	var dealt: Array = [[], [], [], []]
	for i in deck.size():
		dealt[i % 4].append(deck[i])
	_sort_hand(dealt[0])
	set_message("ラウンド %d　カードを配ります" % round_no)
	_refresh()
	show_deck(field_center, field_card)
	var items: Array = []
	var positions: Array = []
	for p in 4:
		positions.append(_card_positions(p, dealt[p].size()))
	for i in dealt[0].size() + 1:
		for p in 4:
			if i < dealt[p].size():
				items.append({"card": dealt[p][i], "to": positions[p][i], "size": _card_size(p), "face_up": p == 0})
	await deal_cards(items, 0.025)
	hide_deck()
	hands = dealt
	_refresh()
	await wait(0.3)


## 1回戦はダイヤの3を持っている人から。2回戦からは前の大貧民から。
func _first_player() -> int:
	if round_no > 1:
		return titles.find(3)
	for p in 4:
		for card: Card in hands[p]:
			if card.suit == 2 and card.rank == 3:
				return p
	return 0


func _play_tricks() -> void:
	while _active_count() > 1:
		if done[current] or (not field.is_empty() and passed[current]):
			current = _next_active(current)
			continue
		_refresh()
		var play: Dictionary
		if current == 0:
			play = await _human_turn()
		else:
			play = await _cpu_turn(current)
		if play.is_empty():
			passed[current] = true
			set_message("%s はパス" % NAMES[current])
			_refresh()
			await wait(0.35)
		else:
			var cut := await _apply_play(current, play)
			if hands[current].is_empty():
				await _finish_player(current)
			if _active_count() <= 1:
				break
			if cut:
				# 8切りで流れたら、出した人からもう一度
				if done[current]:
					current = _next_active(current)
				continue
		if not field.is_empty() and _trick_over():
			var leader := field_owner
			set_message("場が流れた")
			await _clear_field()
			current = leader if not done[leader] else _next_active(leader)
			continue
		current = _next_active(current)
	for p in 4:
		if not done[p]:
			await _finish_player(p)


func _trick_over() -> bool:
	for p in 4:
		if not done[p] and p != field_owner and not passed[p]:
			return false
	return true


func _finish_player(p: int) -> void:
	var last := _active_count() == 1
	done[p] = true
	finish_order.append(p)
	# 都落ちした人は最下位なので、上がった人の階級はその分ずれない
	var title: String = TITLES[finish_order.size() - 1]
	set_message("%s が最後まで残った（%s）" % [NAMES[p], title] if last else "%s があがり！（%s）" % [NAMES[p], title])
	# 都落ち: 前の大富豪より先にだれかが上がったら、前の大富豪は最下位
	if rule_miyako and round_no > 1 and finish_order.size() == 1 and titles[p] != 0:
		var previous := titles.find(0)
		if previous >= 0 and not done[previous]:
			done[previous] = true
			fallen = previous
			_refresh()
			await pop_text("都落ち！", field_center - Vector2(0, 110), Color("ff7a7a"))
			set_message("%s が先に上がったので、%s は都落ち（大貧民）" % [NAMES[p], NAMES[previous]])
	_refresh()
	await wait(0.8)


func _record_round() -> void:
	var order := _round_order()
	for i in order.size():
		titles[order[i]] = i
		points[order[i]] += PLACE_POINTS[i]


## このラウンドの順位（都落ちした人は最後）。
func _round_order() -> Array:
	var order: Array = []
	for p: int in finish_order:
		if p != fallen:
			order.append(p)
	if fallen >= 0:
		order.append(fallen)
	return order


# ---------------------------------------------------------------- カード交換

## 大貧民は強いカード2枚を大富豪へ、貧民は1枚を富豪へ。上位の人はいらないカードを同じ枚数返す。
func _exchange() -> void:
	var by_title := {}
	for p in 4:
		by_title[titles[p]] = p
	for pair: Array in [[by_title[3], by_title[0], 2], [by_title[2], by_title[1], 1]]:
		var low: int = pair[0]
		var high: int = pair[1]
		var count: int = pair[2]
		set_message("カード交換：%s（%s）→ %s（%s）に強いカードを%d枚" % [NAMES[low], TITLES[titles[low]], NAMES[high],
				TITLES[titles[high]], count])
		await _give(low, high, _strongest(low, count))
		var back: Array
		if high == 0:
			back = await _human_choose_give(low, count)
		else:
			await wait(0.4)
			back = _weakest(high, count)
		set_message("%s → %s に%d枚かえした" % [NAMES[high], NAMES[low], count])
		await _give(high, low, back)
		await wait(0.4)


func _human_choose_give(to: int, count: int) -> Array:
	selected.clear()
	give_count = count
	input_mode = "give"
	set_message("%s（%s）にわたすカードを%d枚選んでください" % [NAMES[to], TITLES[titles[to]], count])
	_update_buttons()
	_refresh()
	var cards: Array = await human_acted
	input_mode = ""
	selected.clear()
	_update_buttons()
	return cards


func _give(from: int, to: int, cards: Array) -> void:
	var froms: Array = []
	for card: Card in cards:
		froms.append(_card_origin(from, card))
	for card: Card in cards:
		hands[from].erase(card)
	_refresh()
	for i in cards.size():
		fly_card(cards[i], froms[i], _seat_goal(to), _card_size(from), _card_size(to), from == 0 or to == 0, 0.4)
		await wait(0.12)
	await wait(0.4)
	hands[to].append_array(cards)
	if to == 0:
		_sort_hand(hands[0])
	_refresh()


func _strongest(p: int, count: int) -> Array:
	var sorted_hand: Array = hands[p].duplicate()
	sorted_hand.sort_custom(func(a: Card, b: Card) -> bool: return strength(a) > strength(b))
	return sorted_hand.slice(0, count)


func _weakest(p: int, count: int) -> Array:
	var sorted_hand: Array = hands[p].duplicate()
	sorted_hand.sort_custom(func(a: Card, b: Card) -> bool: return strength(a) < strength(b))
	return sorted_hand.slice(0, count)


# ---------------------------------------------------------------- 手番

func _human_turn() -> Dictionary:
	selected.clear()
	input_mode = "play"
	set_message("出すカードを選んでください" if field.is_empty() else "場より強いカードを出すか、パス")
	_update_buttons()
	_refresh()
	var cards: Array = await human_acted
	input_mode = ""
	selected.clear()
	_update_buttons()
	return {} if cards.is_empty() else _analyze(cards)


func _cpu_turn(p: int) -> Dictionary:
	await wait(0.6 if not done[0] else 0.2)
	return _cpu_choose(p)


## 場に出して、ルールの効果（しばり・革命・11バック・8切り）をかける。8切りで流れたら true。
func _apply_play(p: int, play: Dictionary) -> bool:
	var cards: Array = play["cards"]
	var froms: Array = []
	for card: Card in cards:
		froms.append(_card_origin(p, card))
	for card: Card in cards:
		hands[p].erase(card)
	_refresh()
	var slots := _field_positions(cards.size())
	for i in cards.size():
		fly_card(cards[i], froms[i], slots[i], _card_size(p), field_card, true, 0.28)
		await wait(0.06)
	await wait(0.3)

	var notes: Array = []
	if rule_shibari and not field.is_empty() and bound_suits.is_empty() and play["jokers"] == 0 \
			and field["jokers"] == 0 and play["suits"] == field["suits"]:
		bound_suits = play["suits"]
		notes.append("しばり")
	field = play
	field_owner = p
	_refresh()
	set_message("%s：%s" % [NAMES[p], " ".join(cards.map(func(c: Card) -> String: return c.label()))])

	var has_rank := func(rank: int) -> bool:
		return cards.any(func(c: Card) -> bool: return not c.is_joker() and c.rank == rank)
	if rule_revolution and play["type"] == "group" and play["count"] >= 4:
		revolution = not revolution
		_refresh()
		await pop_text("革命！" if revolution else "革命返し！", field_center - Vector2(0, 110), Color("ff7a7a"))
	if rule_eight and has_rank.call(8):
		await pop_text("8切り！", field_center - Vector2(0, 110))
		await _clear_field()
		return true
	if rule_eleven and has_rank.call(11):
		eleven_back = true
		_refresh()
		await pop_text("11バック！", field_center - Vector2(0, 110))
	elif not notes.is_empty():
		await pop_text("しばり！", field_center - Vector2(0, 110))
	else:
		await wait(0.35)
	return false


func _reset_field() -> void:
	field = {}
	field_owner = -1
	passed = [false, false, false, false]
	eleven_back = false
	bound_suits = []


func _clear_field() -> void:
	var tween := field_layer.create_tween()
	tween.tween_property(field_layer, "modulate:a", 0.0, 0.25)
	await tween.finished
	_reset_field()
	_refresh()
	field_layer.modulate.a = 1.0
	await wait(0.2)


# ---------------------------------------------------------------- 役の判定

## 強さ。3 が 0、…、A が 11、2 が 12、ジョーカーが 13。
static func strength(card: Card) -> int:
	if card.is_joker():
		return JOKER_STRENGTH
	return (card.rank + 10) % 13


## 出そうとしているカードの組み合わせを調べる。出せない組み合わせなら空の辞書。
## type: "group"（同じ数字）/ "stairs"（階段）, strength: 比べる強さ（階段はいちばん下）
func _analyze(cards: Array) -> Dictionary:
	if cards.is_empty():
		return {}
	var naturals: Array = cards.filter(func(c: Card) -> bool: return not c.is_joker())
	var jokers := cards.size() - naturals.size()
	var suits: Array = naturals.map(func(c: Card) -> int: return c.suit)
	suits.sort()
	var ranks := {}
	for card: Card in naturals:
		ranks[card.rank] = true
	var play := {"cards": cards, "count": cards.size(), "jokers": jokers, "suits": suits}
	if ranks.size() <= 1:
		play["type"] = "group"
		play["strength"] = JOKER_STRENGTH if naturals.is_empty() else strength(naturals[0])
		return play
	if not rule_stairs or cards.size() < 3:
		return {}
	# 階段: 同じマークで数字が全部ちがい、すき間をジョーカーでうめられる
	var suit_set := {}
	for s: int in suits:
		suit_set[s] = true
	if suit_set.size() != 1 or ranks.size() != naturals.size():
		return {}
	var strengths: Array = naturals.map(func(c: Card) -> int: return strength(c))
	strengths.sort()
	var low: int = strengths[0]
	var high: int = strengths[strengths.size() - 1]
	var gaps := (high - low + 1) - strengths.size()
	if gaps > jokers:
		return {}
	var top := high + (jokers - gaps)
	if top > 12:
		low -= top - 12
	if low < 0:
		return {}
	play["type"] = "stairs"
	play["strength"] = low
	return play


func _reversed() -> bool:
	return revolution != eleven_back


func _can_beat(play: Dictionary) -> bool:
	if play.is_empty():
		return false
	if field.is_empty():
		return true
	if play["type"] != field["type"] or play["count"] != field["count"]:
		return false
	var field_all_jokers: bool = field["jokers"] == field["count"]
	var play_all_jokers: bool = play["jokers"] == play["count"]
	# スペ3返し: ジョーカー1枚には♠3で勝てる
	if rule_spade3 and field_all_jokers and field["count"] == 1:
		var card: Card = play["cards"][0]
		return not card.is_joker() and card.suit == 0 and card.rank == 3
	if field_all_jokers:
		return false
	if not bound_suits.is_empty():
		for s: int in play["suits"]:
			if not s in bound_suits:
				return false
	if play_all_jokers:
		return true
	if _reversed():
		return play["strength"] < field["strength"]
	return play["strength"] > field["strength"]


# ---------------------------------------------------------------- CPU

## 出せる手を全部あげる。
func _candidates(p: int) -> Array:
	var hand: Array = hands[p]
	var jokers: Array = hand.filter(func(c: Card) -> bool: return c.is_joker())
	var by_rank := {}
	for card: Card in hand:
		if not card.is_joker():
			by_rank.get_or_add(card.rank, []).append(card)
	var need: int = -1 if field.is_empty() else field["count"]
	var raw: Array = []
	for rank: int in by_rank:
		var naturals: Array = by_rank[rank].duplicate()
		if not bound_suits.is_empty():
			naturals.sort_custom(func(a: Card, b: Card) -> bool: return int(a.suit in bound_suits) > int(b.suit in bound_suits))
		for k in range(1, mini(4, naturals.size() + jokers.size()) + 1):
			if need > 0 and k != need:
				continue
			var use := mini(k, naturals.size())
			raw.append(naturals.slice(0, use) + jokers.slice(0, k - use))
	for k in range(1, jokers.size() + 1):
		if need < 0 or k == need:
			raw.append(jokers.slice(0, k))
	if rule_stairs:
		for suit in 4:
			var by_strength := {}
			for card: Card in hand:
				if not card.is_joker() and card.suit == suit:
					by_strength[strength(card)] = card
			for length in range(3, 7):
				if need > 0 and length != need:
					continue
				for start in range(0, 13 - length + 1):
					var cards: Array = []
					var used := 0
					var naturals := 0
					for s in range(start, start + length):
						if by_strength.has(s):
							cards.append(by_strength[s])
							naturals += 1
						elif used < jokers.size():
							cards.append(jokers[used])
							used += 1
						else:
							break
					if cards.size() == length and naturals >= 2:
						raw.append(cards)
	var result: Array = []
	for cards: Array in raw:
		var play := _analyze(cards)
		if _can_beat(play):
			result.append(play)
	return result


func _cpu_choose(p: int) -> Dictionary:
	var candidates := _candidates(p)
	if candidates.is_empty():
		return {}
	var hand_size: int = hands[p].size()
	for play: Dictionary in candidates:
		if play["count"] == hand_size:
			return play  # 出しきれるなら出す
	var rank_counts := {}
	for card: Card in hands[p]:
		if not card.is_joker():
			rank_counts[card.rank] = rank_counts.get(card.rank, 0) + 1
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _cpu_score(a, rank_counts) < _cpu_score(b, rank_counts))
	var best: Dictionary = candidates[0]
	if not field.is_empty() and (best["jokers"] > 0 or _effective(best) >= 11) and hand_size > 5 and randf() < 0.5:
		return {}  # 強いカードは手札が多いうちは温存する
	return best


## 小さいほど出したい手。弱いカードから、なるべく枚数を多く、ジョーカーや組のばらしは避ける。
func _cpu_score(play: Dictionary, rank_counts: Dictionary) -> float:
	var score := float(_effective(play))
	score += play["jokers"] * 20.0
	if field.is_empty():
		score -= play["count"] * 0.6
	if play["type"] == "group" and play["jokers"] < play["count"]:
		var rank: int = play["cards"].filter(func(c: Card) -> bool: return not c.is_joker())[0].rank
		if rank_counts.get(rank, 0) > play["count"] - play["jokers"]:
			score += 1.5  # 組をばらすのは避けたい
	return score


## 今の向き（革命・11バック）での強さ。数字が大きいほど強い。
func _effective(play: Dictionary) -> int:
	if play["strength"] == JOKER_STRENGTH:
		return JOKER_STRENGTH
	return 12 - play["strength"] if _reversed() else play["strength"]


# ---------------------------------------------------------------- 入力

func _on_hand_card(card: Card) -> void:
	if input_mode == "":
		return
	if card in selected:
		selected.erase(card)
	elif input_mode != "give" or selected.size() < give_count:
		selected.append(card)
	_update_buttons()
	_refresh()


func _on_play() -> void:
	if input_mode == "play" and _can_beat(_analyze(selected)):
		human_acted.emit(selected.duplicate())
	elif input_mode == "give" and selected.size() == give_count:
		human_acted.emit(selected.duplicate())


func _on_pass() -> void:
	if input_mode == "play" and not field.is_empty():
		human_acted.emit([])


func _update_buttons() -> void:
	play_button.visible = input_mode != ""
	pass_button.visible = input_mode == "play" and not field.is_empty()
	if input_mode == "give":
		play_button.text = "わたす（%d/%d）" % [selected.size(), give_count]
		play_button.disabled = selected.size() != give_count
	else:
		play_button.text = "出す"
		play_button.disabled = not _can_beat(_analyze(selected))


# ---------------------------------------------------------------- 表示

func _card_size(p: int) -> Vector2:
	return hand_card if p == 0 else cpu_card


func _card_positions(p: int, count: int = -1) -> Array[Vector2]:
	if count < 0:
		count = hands[p].size()
	var positions: Array[Vector2] = []
	if p == 0:
		var rows := 2 if portrait and count > 7 else 1
		var per_row := ceili(count / float(rows))
		var step := minf(hand_card.x + 4, (screen.x - 40 - hand_card.x) / maxf(per_row - 1, 1))
		for i in count:
			@warning_ignore("integer_division")
			var row := i / per_row
			var in_row := mini(per_row, count - row * per_row)
			var start_x := (screen.x - (step * (in_row - 1) + hand_card.x)) / 2.0
			positions.append(Vector2(start_x + (i % per_row) * step, hand_y + row * (hand_card.y + 8)))
		return positions
	var cpu_step := minf(cpu_card.x + 4, (cpu_panel_width - cpu_card.x) / maxf(count - 1, 1))
	var cpu_start := (cpu_panel_width - (cpu_step * (count - 1) + cpu_card.x)) / 2.0
	for i in count:
		positions.append(cpu_layers[p - 1].position + Vector2(cpu_start + i * cpu_step, 0))
	return positions


func _field_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var step := field_card.x + 6
	for i in count:
		positions.append(field_center - field_card / 2.0 + Vector2((i - (count - 1) / 2.0) * step, 0))
	return positions


func _card_origin(p: int, card: Card) -> Vector2:
	if p == 0 and hand_views.has(card):
		return hand_views[card].position
	var index: int = hands[p].find(card)
	return _card_positions(p)[maxi(index, 0)]


func _seat_goal(p: int) -> Vector2:
	if p == 0:
		return Vector2(screen.x / 2.0 - hand_card.x / 2.0, hand_y)
	return cpu_layers[p - 1].position + Vector2(cpu_panel_width / 2.0 - cpu_card.x / 2.0, 0)


func _sort_hand(hand: Array) -> void:
	hand.sort_custom(func(a: Card, b: Card) -> bool:
		return strength(a) < strength(b) or (strength(a) == strength(b) and a.suit < b.suit))


func _active_count() -> int:
	return done.count(false)


func _next_active(p: int) -> int:
	for i in range(1, 5):
		var q := (p + i) % 4
		if not done[q]:
			return q
	return p


func _refresh() -> void:
	status_label.text = "ラウンド %d/%d" % [round_no, rounds]
	for p in range(1, 4):
		var layer := cpu_layers[p - 1]
		UI.clear_children(layer)
		var positions := _card_positions(p)
		for i in hands[p].size():
			var view := CardView.new()
			layer.add_child(view)
			view.setup(hands[p][i], cpu_card, false)
			view.position = positions[i] - layer.position
		var lbl := cpu_labels[p - 1]
		lbl.text = _seat_text(p)
		lbl.modulate = Color.YELLOW if p == current and not done[p] else (Color(0.65, 0.65, 0.65) if _is_passed(p) else Color.WHITE)

	UI.clear_children(hand_layer)
	hand_views.clear()
	var positions := _card_positions(0)
	for i in hands[0].size():
		var card: Card = hands[0][i]
		var view := CardView.new()
		hand_layer.add_child(view)
		view.setup(card, hand_card)
		view.position = positions[i] - Vector2(0, 22 if card in selected else 0)
		view.set_clickable(input_mode != "")
		view.pressed.connect(_on_hand_card.bind(card))
		hand_views[card] = view
	hand_label.text = _seat_text(0)
	hand_label.modulate = Color.YELLOW if current == 0 and not done[0] else Color.WHITE

	UI.clear_children(field_layer)
	if not field.is_empty():
		var cards: Array = field["cards"]
		var slots := _field_positions(cards.size())
		for i in cards.size():
			var view := CardView.new()
			field_layer.add_child(view)
			view.setup(cards[i], field_card)
			view.position = slots[i]
	field_label.text = "%s の手" % NAMES[field_owner] if not field.is_empty() else ""

	var badges: Array = []
	if revolution:
		badges.append("革命中")
	if eleven_back:
		badges.append("11バック中")
	if not bound_suits.is_empty():
		badges.append("しばり " + "".join(bound_suits.map(func(s: int) -> String: return Card.SUIT_MARKS[s])))
	badge_label.text = "\n".join(badges)


func _is_passed(p: int) -> bool:
	return not field.is_empty() and passed[p] and not done[p]


func _seat_text(p: int) -> String:
	var name: String = NAMES[p] if p != 0 else "あなたの手札"
	var title: String = "（%s）" % TITLES[titles[p]] if titles[p] >= 0 else ""
	var marker := "▶ " if p == current and not done[p] else ""
	if p == fallen:
		return "%s%s  都落ち" % [name, title]
	if done[p]:
		return "%s%s  %d位であがり" % [name, title, finish_order.find(p) + 1]
	return "%s%s%s  %d枚%s" % [marker, name, title, hands[p].size(), "  パス" if _is_passed(p) else ""]


func _show_round_summary() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.size = screen
	shade.z_index = SHADE_Z
	add_child(shade)
	var panel := UI.panel(shade, (screen - RESULT_PANEL_SIZE) / 2.0, RESULT_PANEL_SIZE)
	UI.label(panel, "ラウンド %d の結果" % round_no, Vector2(0, 24), Vector2(600, 60), 36)
	var lines: Array = []
	var order := _round_order()
	for i in order.size():
		var p: int = order[i]
		lines.append("%s  %s  +%d（計%d点）" % [TITLES[i], NAMES[p], PLACE_POINTS[i], points[p]])
	UI.label(panel, "\n".join(lines), Vector2(30, 100), Vector2(540, 220), 24)
	UI.button(panel, "つぎのラウンドへ", Vector2(150, 370), Vector2(300, 60), 26, func() -> void: next_pressed.emit())
	if order[0] == 0:
		celebrate(null, true)
	await next_pressed
	shade.queue_free()


func _finish() -> void:
	var order: Array = [0, 1, 2, 3]
	order.sort_custom(func(a: int, b: int) -> bool: return points[a] > points[b] or (points[a] == points[b] and a < b))
	var lines: Array = []
	var place := 0
	for i in order.size():
		var p: int = order[i]
		if i == 0 or points[p] < points[order[i - 1]]:
			place = i + 1
		lines.append("%d位  %s  %d点（最後は%s）" % [place, NAMES[p], points[p], TITLES[titles[p]]])
	if points[0] == points[order[0]]:
		show_result("あなたの勝ち！", lines, true)
	else:
		show_result("%s の勝ち…" % NAMES[order[0]], lines)
