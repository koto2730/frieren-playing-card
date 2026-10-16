class_name Card
extends RefCounted
## トランプ1枚分のデータ。

const SUIT_NAMES := ["spade", "heart", "diamond", "club"]
const SUIT_MARKS := ["♠", "♥", "♦", "♣"]
const RANK_NAMES := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const JOKER_SUIT := -1

var suit: int
var rank: int  # 1〜13。ジョーカーは 0=黒 / 1=赤


func _init(s: int, r: int) -> void:
	suit = s
	rank = r


func is_joker() -> bool:
	return suit == JOKER_SUIT


func texture_path() -> String:
	if is_joker():
		return "res://assets/cards/joker_red.svg" if rank == 1 else "res://assets/cards/joker_black.svg"
	return "res://assets/cards/%s_%s.svg" % [SUIT_NAMES[suit], RANK_NAMES[rank - 1]]


func label() -> String:
	if is_joker():
		return "ジョーカー"
	return SUIT_MARKS[suit] + RANK_NAMES[rank - 1]


## 手札の並べ替え用（数字順、ジョーカーは最後）。
func order() -> int:
	if is_joker():
		return 9999
	return rank * 10 + suit


static func make_deck(jokers: int = 0) -> Array[Card]:
	var deck: Array[Card] = []
	for s in 4:
		for r in range(1, 14):
			deck.append(Card.new(s, r))
	for i in jokers:
		deck.append(Card.new(JOKER_SUIT, i % 2))
	deck.shuffle()
	return deck
