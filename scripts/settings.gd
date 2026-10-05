class_name Settings
extends RefCounted
## タイトルやルール選択で決めた設定を、各シーンへ受け渡すための置き場。

## 神経衰弱のCPUのつよさ。rate はめくられたカードを覚えている確率。
const MEMORY_CPU_LEVELS := [
	{"name": "よわい", "rate": 0.25},
	{"name": "ふつう", "rate": 0.5},
	{"name": "つよい", "rate": 0.85},
]

static var memory_cpu_level := 1

## たて画面(720x1280)で遊ぶかどうか。起動引数 `-- --portrait` でも指定できる。
static var portrait := "--portrait" in OS.get_cmdline_user_args()
static var orientation_chosen := "--portrait" in OS.get_cmdline_user_args()
