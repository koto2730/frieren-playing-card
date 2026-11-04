extends GameBase
## ソリティア（クロンダイク）。1人用。
## 7列の場札を「色ちがい・1つずつ小さく」重ねて並べかえ、4つの組札にマークごとに A→K を積めばクリア。
## カードをタップで選び、置きたい場所をタップ。選んだカードをもう一度タップすると、置ける場所へ自動で動かす。
## 意味のある手がなくなったら「手詰まり」を知らせ、もどすか、おわるかを選ぶ。

const RED_SUITS := [1, 2]
const SELECT_COLOR := Color(1.0, 0.92, 0.5)
const MAX_HISTORY := 300

var draw_count := 1

# 配置。よこ画面は右に操作ボタン、たて画面は下に置く。
var card_size := Vector2(110, 154)
var column_step := 130.0
var origin_x := 190.0
var top_y := 64.0
var tableau_y := 240.0
var bottom_limit := 712.0
var down_gap := 16.0
var up_gap := 32.0
var waste_fan := 26.0

var stock: Array = []
var waste: Array = []
var foundations: Array = [[], [], [], []]  # マークごと（♠♥♦♣ の順）
var tableau: Array = [[], [], [], [], [], [], []]
var face_up := {}  # Card -> bool
var selection := {}  # {"pile": "waste" / "foundation" / "tableau", "index": 列や組札の番号, "start": 列の何枚目から}
var moving: Array = []  # 飛んでいる最中で、場には描かないカード
var history: Array = []
var moves := 0
var started_ms := 0
var dealing := true
var busy := false
var finished := false
var stuck_dialog: Control
var clock := 0.0

var board_layer: Control
var status_label: Label
var undo_button: Button
var auto_button: Button


func _ready() -> void:
	setup_base("ソリティア")
	draw_count = Settings.get_value("solitaire_draw")
	if portrait:
		card_size = Vector2(92, 129)
		column_step = 98.0
		origin_x = 20.0
		top_y = 70.0
		tableau_y = 226.0
		bottom_limit = 1120.0
		down_gap = 14.0
		up_gap = 30.0
		waste_fan = 20.0
		place_message(Vector2(0, 1126), Vector2(screen.x, 40), 20)
		undo_button = UI.button(self, "もどす", Vector2(40, 1176), Vector2(300, 70), 28, _on_undo)
		auto_button = UI.button(self, "自動で片付ける", Vector2(380, 1176), Vector2(300, 70), 24, _on_auto)
	else:
		place_message(Vector2(260, 6), Vector2(560, 44), 20)
		undo_button = UI.button(self, "もどす", Vector2(1110, 240), Vector2(150, 56), 24, _on_undo)
		auto_button = UI.button(self, "自動で\n片付ける", Vector2(1110, 310), Vector2(150, 86), 22, _on_auto)
	status_label = UI.label(self, "", Vector2(screen.x - 450, 6), Vector2(300, 44), 18 if portrait else 20,
			HORIZONTAL_ALIGNMENT_RIGHT)
	board_layer = Control.new()
	add_child(board_layer)
	move_child(board_layer, fx_layer.get_index())  # 飛んでいるカードより奥
	_run()


func _process(delta: float) -> void:
	if finished or dealing:
		return
	clock += delta
	if clock >= 0.5:
		clock = 0.0
		_update_status()


func _run() -> void:
	busy = true
	var deck := Card.make_deck()
	for column in 7:
		for row in column + 1:
			var card: Card = deck.pop_back()
			tableau[column].append(card)
			face_up[card] = row == column
	stock = deck
	for card: Card in stock:
		face_up[card] = false

	set_message("カードを配ります")
	_refresh()
	show_deck(_slot_position("stock", 0) + card_size / 2.0, card_size)
	var items: Array = []
	for row in 7:
		for column in range(row, 7):
			var card: Card = tableau[column][row]
			items.append({"card": card, "to": _card_position(card), "size": card_size, "face_up": face_up[card]})
	await deal_cards(items, 0.04)
	hide_deck()
	dealing = false
	busy = false
	started_ms = Time.get_ticks_msec()
	set_message("")
	_refresh()
	_check_stuck()


# ---------------------------------------------------------------- ルール

func _is_red(card: Card) -> bool:
	return card.suit in RED_SUITS


func _can_found(card: Card, f: int) -> bool:
	return card.suit == f and card.rank == foundations[f].size() + 1


func _can_stack(card: Card, column: int) -> bool:
	var pile: Array = tableau[column]
	if pile.is_empty():
		return card.rank == 13
	var top: Card = pile[pile.size() - 1]
	return face_up[top] and _is_red(top) != _is_red(card) and top.rank == card.rank + 1


func _selected_cards() -> Array:
	match selection.get("pile", ""):
		"waste":
			return [waste[waste.size() - 1]]
		"foundation":
			var pile: Array = foundations[selection["index"]]
			return [pile[pile.size() - 1]]
		"tableau":
			return tableau[selection["index"]].slice(selection["start"])
	return []


# ---------------------------------------------------------------- 入力

func _on_card(pile: String, index: int, position_in_pile: int) -> void:
	if busy or finished:
		return
	if pile == "stock":
		selection = {}
		await _draw_stock()
		return

	var clicked := {"pile": pile, "index": index, "start": position_in_pile}
	if not selection.is_empty():
		if selection == clicked:
			# 同じカードをもう一度: 置ける場所へ自動で
			var cards := _selected_cards()
			if not await _auto_move(cards):
				set_message("置ける場所がありません")
			selection = {}
			_refresh()
			return
		if pile in ["tableau", "foundation"] and await _try_move(pile, index):
			return
	selection = clicked if _selectable(clicked) else {}
	set_message("")
	_refresh()


func _selectable(target: Dictionary) -> bool:
	match target["pile"]:
		"waste":
			return not waste.is_empty()
		"foundation":
			return not foundations[target["index"]].is_empty()
		"tableau":
			var pile: Array = tableau[target["index"]]
			return target["start"] >= 0 and target["start"] < pile.size() and face_up[pile[target["start"]]]
	return false


func _try_move(pile: String, index: int) -> bool:
	var cards := _selected_cards()
	if cards.is_empty():
		return false
	if pile == "foundation":
		if cards.size() != 1 or not _can_found(cards[0], index):
			return false
	elif not _can_stack(cards[0], index) or (selection["pile"] == "tableau" and selection["index"] == index):
		return false
	await _move(cards, pile, index)
	return true


## 選んだカードを、組札→場札（左から）の順に、置ける場所へ動かす。
func _auto_move(cards: Array) -> bool:
	if cards.is_empty():
		return false
	if cards.size() == 1 and selection["pile"] != "foundation" and _can_found(cards[0], cards[0].suit):
		await _move(cards, "foundation", cards[0].suit)
		return true
	for column in 7:
		if selection["pile"] == "tableau" and selection["index"] == column:
			continue
		if _can_stack(cards[0], column):
			await _move(cards, "tableau", column)
			return true
	return false


func _on_undo() -> void:
	if busy or finished or history.is_empty():
		return
	var state: Dictionary = history.pop_back()
	stock = state["stock"]
	waste = state["waste"]
	foundations = state["foundations"]
	tableau = state["tableau"]
	face_up = state["face_up"]
	moves = state["moves"]
	selection = {}
	set_message("1手もどしました")
	_refresh()


func _on_auto() -> void:
	if busy or finished or not _can_auto_complete():
		return
	busy = true
	selection = {}
	set_message("自動で片付けています")
	while _foundation_count() < 52:
		var moved := false
		for column in 7:
			var pile: Array = tableau[column]
			if pile.is_empty():
				continue
			var card: Card = pile[pile.size() - 1]
			if _can_found(card, card.suit):
				selection = {"pile": "tableau", "index": column, "start": pile.size() - 1}
				await _move([card], "foundation", card.suit, 0.12, false)
				moved = true
				break
		if not moved:
			break
	busy = false
	_check_win()


# ---------------------------------------------------------------- 動かす

func _push_history() -> void:
	history.append({
		"stock": stock.duplicate(), "waste": waste.duplicate(), "foundations": foundations.duplicate(true),
		"tableau": tableau.duplicate(true), "face_up": face_up.duplicate(), "moves": moves,
	})
	if history.size() > MAX_HISTORY:
		history.pop_front()


func _move(cards: Array, pile: String, index: int, duration: float = 0.22, check: bool = true) -> void:
	var was_busy := busy
	busy = true
	_push_history()
	var froms: Array = cards.map(func(c: Card) -> Vector2: return _card_position(c))
	match selection["pile"]:
		"waste":
			waste.pop_back()
		"foundation":
			foundations[selection["index"]].pop_back()
		"tableau":
			tableau[selection["index"]] = tableau[selection["index"]].slice(0, selection["start"])
	if pile == "foundation":
		foundations[index].append_array(cards)
	else:
		tableau[index].append_array(cards)
	selection = {}
	moves += 1
	var flipped := _flip_tops()

	moving = cards.duplicate()
	_refresh()
	for i in cards.size() - 1:
		fly_card(cards[i], froms[i], _card_position(cards[i]), card_size, card_size, true, duration)
	var last: Card = cards[cards.size() - 1]
	await fly_card(last, froms[cards.size() - 1], _card_position(last), card_size, card_size, true, duration)
	moving.clear()
	_refresh()
	for card: Card in flipped:
		var view := _view_of(card)
		if view != null:
			view.set_face_up(false)
			view.flip(true)
	busy = was_busy
	if check:
		_check_win()


## 場札のいちばん上が裏向きなら表にする。表にしたカードを返す。
func _flip_tops() -> Array:
	var flipped: Array = []
	for pile: Array in tableau:
		if not pile.is_empty() and not face_up[pile[pile.size() - 1]]:
			face_up[pile[pile.size() - 1]] = true
			flipped.append(pile[pile.size() - 1])
	return flipped


func _draw_stock() -> void:
	busy = true
	if stock.is_empty():
		if not waste.is_empty():
			_push_history()
			waste.reverse()
			stock = waste
			waste = []
			for card: Card in stock:
				face_up[card] = false
			moves += 1
			set_message("山札をもどしました")
			_refresh()
		busy = false
		_check_stuck()
		return
	_push_history()
	var from := _slot_position("stock", 0)
	var drawn: Array = []
	for i in mini(draw_count, stock.size()):
		var card: Card = stock.pop_back()
		face_up[card] = true
		waste.append(card)
		drawn.append(card)
	moves += 1
	moving = drawn
	_refresh()
	for i in drawn.size():
		await fly_card(drawn[i], from, _card_position(drawn[i]), card_size, card_size, true, 0.14)
	moving = []
	_refresh()
	busy = false
	_check_stuck()


func _foundation_count() -> int:
	var count := 0
	for pile: Array in foundations:
		count += pile.size()
	return count


func _can_auto_complete() -> bool:
	if not stock.is_empty() or not waste.is_empty():
		return false
	for pile: Array in tableau:
		for card: Card in pile:
			if not face_up[card]:
				return false
	return _foundation_count() < 52


func _check_win() -> void:
	_refresh()
	if finished:
		return
	if _foundation_count() < 52:
		_check_stuck()
		return
	finished = true
	show_result("クリア！", ["手数　%d" % moves, "タイム　%s" % _time_text()], true)


# ---------------------------------------------------------------- 手詰まり

func _check_stuck() -> void:
	if finished or busy or stuck_dialog != null or _foundation_count() >= 52 or _has_useful_move():
		return
	_show_stuck_dialog()


## 意味のある手が残っているか。同じ形の列どうしで行ったり来たりするだけの移動は数えない。
func _has_useful_move() -> bool:
	var reachable := _reachable_stock_cards()
	var tops: Array = []
	for pile: Array in tableau:
		if not pile.is_empty():
			tops.append(pile[pile.size() - 1])
	# 組札に置けるカード
	for card: Card in reachable + tops:
		if _can_found(card, card.suit):
			return true
	# 山札・捨て札から列に置けるカード
	for card: Card in reachable:
		for column in 7:
			if _can_stack(card, column):
				return true
	# 列から列への移動
	for column in 7:
		var pile: Array = tableau[column]
		var first := -1
		for i in pile.size():
			if face_up[pile[i]]:
				first = i
				break
		if first < 0:
			continue
		for i in range(first, pile.size()):
			for target in 7:
				if target == column or not _can_stack(pile[i], target):
					continue
				if i == first and first > 0:
					return true  # 裏のカードがめくれる
				if i == 0 and not tableau[target].is_empty():
					return true  # 列が空いて、Kを置けるようになる
				if i > first and _can_found(pile[i - 1], pile[i - 1].suit):
					return true  # 下のカードを組札に置けるようになる
	return false


## 今のまま山札をめくり続けたときに、捨て札のいちばん上に出てくるカード。
## 1枚めくりなら全部。3枚めくりは、3枚ずつめくった最後の1枚だけが使える。
func _reachable_stock_cards() -> Array:
	if draw_count == 1:
		return stock + waste
	var reachable: Array = []
	var s: Array = stock.duplicate()
	var w: Array = waste.duplicate()
	if not w.is_empty():
		reachable.append(w[w.size() - 1])
	var total := s.size() + w.size()
	for step in 2 * (ceili(total / 3.0) + 1):
		if s.is_empty():
			if w.is_empty():
				break
			w.reverse()
			s = w
			w = []
		for i in mini(3, s.size()):
			w.append(s.pop_back())
		var top: Card = w[w.size() - 1]
		if not top in reachable:
			reachable.append(top)
	return reachable


func _show_stuck_dialog() -> void:
	stuck_dialog = ColorRect.new()
	stuck_dialog.color = Color(0, 0, 0, 0.55)
	stuck_dialog.size = screen
	stuck_dialog.z_index = SHADE_Z
	add_child(stuck_dialog)
	var panel := UI.panel(stuck_dialog, (screen - Vector2(560, 300)) / 2.0, Vector2(560, 300))
	UI.label(panel, "手詰まりです", Vector2(0, 24), Vector2(560, 60), 40)
	UI.label(panel, "これ以上、動かせるカードがありません。\n1手もどして別の手をためすか、おわりにします。",
			Vector2(20, 94), Vector2(520, 80), 20)
	if history.is_empty():
		# 配った直後から手詰まりのときは、もどせないので「おわる」だけ
		UI.button(panel, "おわる", Vector2(170, 200), Vector2(220, 64), 26, _on_stuck_give_up)
	else:
		UI.button(panel, "もどす", Vector2(40, 200), Vector2(220, 64), 26, _on_stuck_undo)
		UI.button(panel, "おわる", Vector2(300, 200), Vector2(220, 64), 26, _on_stuck_give_up)


func _close_stuck_dialog() -> void:
	if stuck_dialog != null:
		stuck_dialog.queue_free()
		stuck_dialog = null


func _on_stuck_undo() -> void:
	_close_stuck_dialog()
	_on_undo()


func _on_stuck_give_up() -> void:
	_close_stuck_dialog()
	finished = true
	show_result("手詰まり…", ["組札　%d / 52枚" % _foundation_count(), "手数　%d" % moves,
			"タイム　%s" % _time_text()])


# ---------------------------------------------------------------- 表示

func _slot_position(pile: String, index: int) -> Vector2:
	match pile:
		"stock":
			return Vector2(origin_x, top_y)
		"waste":
			return Vector2(origin_x + column_step, top_y)
		"foundation":
			return Vector2(origin_x + (3 + index) * column_step, top_y)
	return Vector2(origin_x + index * column_step, tableau_y)


## 列のカードの位置。長い列は、下にはみ出さないよう重なりを詰める。
func _tableau_positions(column: int) -> Array[Vector2]:
	var pile: Array = tableau[column]
	var positions: Array[Vector2] = []
	if pile.is_empty():
		return positions
	var downs := 0
	for i in pile.size() - 1:
		if not face_up[pile[i]]:
			downs += 1
	var ups := pile.size() - 1 - downs
	var natural := downs * down_gap + ups * up_gap
	var room := bottom_limit - tableau_y - card_size.y
	var scale := minf(1.0, room / maxf(natural, 1.0))
	var y := tableau_y
	for i in pile.size():
		positions.append(Vector2(origin_x + column * column_step, y))
		y += (up_gap if face_up[pile[i]] else down_gap) * scale
	return positions


func _waste_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var shown := mini(waste.size(), 3 if draw_count == 3 else 1)
	var base := _slot_position("waste", 0)
	for i in waste.size():
		var fan := maxi(0, i - (waste.size() - shown))
		positions.append(base + Vector2(fan * waste_fan, 0))
	return positions


func _card_position(card: Card) -> Vector2:
	for column in 7:
		var index: int = tableau[column].find(card)
		if index >= 0:
			return _tableau_positions(column)[index]
	for f in 4:
		if card in foundations[f]:
			return _slot_position("foundation", f)
	var waste_index := waste.find(card)
	if waste_index >= 0:
		return _waste_positions()[waste_index]
	return _slot_position("stock", 0)


func _view_of(card: Card) -> CardView:
	for child in board_layer.get_children():
		if child is CardView and child.card == card:
			return child
	return null


func _refresh() -> void:
	UI.clear_children(board_layer)
	# 空の場所の目印（押すとそこへ置ける）
	_slot(_slot_position("stock", 0), "↻" if stock.is_empty() and not waste.is_empty() else "", "stock", 0, 0)
	for f in 4:
		_slot(_slot_position("foundation", f), Card.SUIT_MARKS[f], "foundation", f, 0)
	for column in 7:
		_slot(_slot_position("tableau", column), "K", "tableau", column, -1)
	if dealing:
		undo_button.disabled = true
		auto_button.visible = false
		_update_status()
		return

	if not stock.is_empty():
		var top := _card_view(stock[stock.size() - 1], _slot_position("stock", 0), false)
		top.set_clickable(true)
		top.pressed.connect(_on_card.bind("stock", 0, 0))
	var waste_positions := _waste_positions()
	for i in waste.size():
		if waste.size() - i > 3:
			continue
		var view := _card_view(waste[i], waste_positions[i], true)
		if i == waste.size() - 1:
			_make_selectable(view, "waste", 0, 0)
	for f in 4:
		var pile: Array = foundations[f]
		if not pile.is_empty():
			if pile.size() >= 2:
				_card_view(pile[pile.size() - 2], _slot_position("foundation", f), true)
			_make_selectable(_card_view(pile[pile.size() - 1], _slot_position("foundation", f), true), "foundation", f, 0)
	for column in 7:
		var pile: Array = tableau[column]
		var positions := _tableau_positions(column)
		for i in pile.size():
			var view := _card_view(pile[i], positions[i], face_up[pile[i]])
			if face_up[pile[i]]:
				_make_selectable(view, "tableau", column, i)

	# 選んでいるカードを明るく
	for card: Card in _selected_cards():
		var view := _view_of(card)
		if view != null:
			view.modulate = SELECT_COLOR
	undo_button.disabled = history.is_empty()
	auto_button.visible = _can_auto_complete()
	_update_status()


func _card_view(card: Card, pos: Vector2, up: bool) -> CardView:
	var view := CardView.new()
	board_layer.add_child(view)
	view.setup(card, card_size, up)
	view.position = pos
	view.visible = not card in moving
	return view


func _make_selectable(view: CardView, pile: String, index: int, position_in_pile: int) -> void:
	view.set_clickable(true)
	view.pressed.connect(_on_card.bind(pile, index, position_in_pile))


func _slot(pos: Vector2, text: String, pile: String, index: int, position_in_pile: int) -> void:
	var slot := Button.new()
	slot.position = pos
	slot.size = card_size
	slot.text = text
	slot.add_theme_font_size_override("font_size", 40 if portrait else 46)
	slot.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	var box := UI.flat_box(Color(0, 0, 0, 0.22), 10)
	for state in ["normal", "hover", "pressed", "focus"]:
		slot.add_theme_stylebox_override(state, box)
	slot.pressed.connect(_on_card.bind(pile, index, position_in_pile))
	board_layer.add_child(slot)


func _time_text() -> String:
	@warning_ignore("integer_division")
	var seconds := 0 if started_ms == 0 else (Time.get_ticks_msec() - started_ms) / 1000
	@warning_ignore("integer_division")
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _update_status() -> void:
	status_label.text = "手数 %d　タイム %s" % [moves, _time_text()]
