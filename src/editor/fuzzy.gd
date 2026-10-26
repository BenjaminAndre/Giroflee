class_name Fuzzy
extends RefCounted
## Fuzzy matching for the command palette: case- and accent-insensitive, characters of the
## query must appear in order in the candidate. Higher score = better match.

const ACCENTS: Dictionary = {
	"à": "a", "â": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e",
	"î": "i", "ï": "i", "ô": "o", "ö": "o", "ù": "u", "û": "u", "ü": "u",
	"ç": "c", "œ": "oe", "æ": "ae", "’": "'",
}


static func normalize(text: String) -> String:
	var lower: String = text.to_lower()
	var out: String = ""
	for i: int in lower.length():
		var ch: String = lower[i]
		out += str(ACCENTS.get(ch, ch))
	return out


## Score of `query` against `candidate`, or -1 when it does not match. A consecutive run,
## a match at the start of a word and an early match all score higher.
static func score(query: String, candidate: String) -> int:
	var q: String = normalize(query).strip_edges()
	var c: String = normalize(candidate)
	if q.is_empty():
		return 0
	var total: int = 0
	var pos: int = 0
	var previous: int = -2
	for i: int in q.length():
		var ch: String = q[i]
		if ch == " ":
			previous = -2
			continue
		var found: int = c.find(ch, pos)
		if found < 0:
			return -1
		var points: int = 10
		if found == previous + 1:
			points += 15
		if found == 0 or c[found - 1] == " " or c[found - 1] == "'" or c[found - 1] == "-":
			points += 12
		points -= mini(found, 20) / 4
		total += points
		previous = found
		pos = found + 1
	if c.begins_with(q):
		total += 30
	elif c.contains(q):
		total += 15
	return total


## Indices of `candidates` that match, best first (ties keep the original order).
static func rank(query: String, candidates: PackedStringArray) -> Array[int]:
	var scored: Array[Dictionary] = []
	for i: int in candidates.size():
		var s: int = score(query, candidates[i])
		if s >= 0:
			scored.append({"index": i, "score": s})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = a["score"]
		var sb: int = b["score"]
		if sa != sb:
			return sa > sb
		var ia: int = a["index"]
		var ib: int = b["index"]
		return ia < ib)
	var out: Array[int] = []
	for entry: Dictionary in scored:
		var index: int = entry["index"]
		out.append(index)
	return out
