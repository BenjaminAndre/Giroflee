class_name JsonUtil
extends RefCounted
## Small typed helpers for working with JSON-shaped Variants under strict typing.


## True for an int, or a float with an integral value (JSON reads every number as a float).
static func is_integral(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f) and f == floorf(f)
	return false


## Converts an integral number to int. Call `is_integral()` first.
static func to_int(value: Variant) -> int:
	if value is int:
		var i: int = value
		return i
	var f: float = value
	return roundi(f)


static func is_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value
		return is_finite(f)
	return false


static func to_float(value: Variant) -> float:
	if value is int:
		var i: int = value
		return float(i)
	var f: float = value
	return f


## True when `value` is made only of bool, finite numbers, String, Array and
## Dictionary with String keys (no null, no engine types).
static func is_json_value(value: Variant) -> bool:
	if value is bool or value is String:
		return true
	if value is int or value is float:
		return is_number(value)
	if value is Array:
		var arr: Array = value
		for item: Variant in arr:
			if not is_json_value(item):
				return false
		return true
	if value is Dictionary:
		var dict: Dictionary = value
		for key: Variant in dict.keys():
			if not (key is String):
				return false
			if not is_json_value(dict[key]):
				return false
		return true
	return false


static func deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		var dict: Dictionary = value
		return dict.duplicate(true)
	if value is Array:
		var arr: Array = value
		return arr.duplicate(true)
	return value


static func has_string(source: Dictionary, key: String) -> bool:
	return source.has(key) and source[key] is String


static func has_array(source: Dictionary, key: String) -> bool:
	return source.has(key) and source[key] is Array


static func has_dict(source: Dictionary, key: String) -> bool:
	return source.has(key) and source[key] is Dictionary


## Reads a boolean entry (false when absent or not a bool).
static func flag(source: Dictionary, key: String) -> bool:
	var value: Variant = source.get(key, false)
	if value is bool:
		var b: bool = value
		return b
	return false
