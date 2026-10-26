class_name CircuitFocus
extends RefCounted
## Which circuits are greyed out on screen (SRD FR-FOCUS). A click on a circuit in the side panel
## greys it (or shows it again); a double-click makes it the "solo" circuit, greying all others, and
## a double-click on the solo circuit restores exactly what was visible before the solo. This is
## view state: it never touches the project and is never exported (ARCH-7).

var _dimmed: Dictionary = {}
var _solo: String = ""
var _before_solo: Dictionary = {}


func is_dimmed(letter: String) -> bool:
	return _dimmed.has(letter)


func is_solo(letter: String) -> bool:
	return not _solo.is_empty() and _solo == letter


## Greyed circuits, sorted.
func dimmed_letters() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _dimmed.keys():
		out.append(str(key))
	out.sort()
	return out


## Greys `letter` out, or shows it again. During a solo this adds or removes it from what is shown.
func toggle(letter: String) -> void:
	if _dimmed.has(letter):
		_dimmed.erase(letter)
	else:
		_dimmed[letter] = true


## Solo `letter` among `all_letters` (the circuits currently listed), or, if it already is the solo
## circuit, go back to what was visible before the solo.
func solo(letter: String, all_letters: Array[String]) -> void:
	if is_solo(letter):
		_dimmed = _before_solo.duplicate()
		_solo = ""
		_before_solo = {}
		return
	if _solo.is_empty():
		_before_solo = _dimmed.duplicate()
	_solo = letter
	_dimmed = {}
	for other: String in all_letters:
		if other != letter:
			_dimmed[other] = true


func reset() -> void:
	_dimmed = {}
	_solo = ""
	_before_solo = {}
