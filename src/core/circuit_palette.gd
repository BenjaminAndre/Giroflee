class_name CircuitPalette
extends RefCounted
## Circuit letters and their on-screen colours (SRD FR-LOOK-2). The colours are the colour-blind
## safe Okabe-Ito set; with 26 letters they repeat, which is why the letter is always shown and
## `pattern()` gives a second cue (0 for the first eight letters, then 1, 2, 3). Exports do not
## use these colours unless asked to.

const LETTERS: PackedStringArray = [
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
	"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
]

const COLORS: Array[Color] = [
	Color(0.902, 0.624, 0.0),   # orange       #E69F00
	Color(0.337, 0.706, 0.914), # sky blue     #56B4E9
	Color(0.0, 0.620, 0.451),   # bluish green #009E73
	Color(0.800, 0.475, 0.655), # purple       #CC79A7
	Color(0.0, 0.447, 0.698),   # blue         #0072B2
	Color(0.835, 0.369, 0.0),   # vermillion   #D55E00
	Color(0.520, 0.520, 0.0),   # olive (Okabe-Ito yellow is too pale on white paper)
	Color(0.424, 0.435, 0.522), # grey         #6C6F85
]


static func is_letter(text: String) -> bool:
	return LETTERS.has(text)


static func index(letter: String) -> int:
	return LETTERS.find(letter)


static func color(letter: String) -> Color:
	var i: int = LETTERS.find(letter)
	if i < 0:
		return PlanTheme.BLACK
	return COLORS[i % COLORS.size()]


## 0 for A-H, 1 for I-P, 2 for Q-X, 3 for Y-Z: the second cue when colours repeat.
static func pattern(letter: String) -> int:
	var i: int = LETTERS.find(letter)
	if i < 0:
		return 0
	return i / COLORS.size()
