class_name JsonWriter
extends RefCounted
## Deterministic, git-friendly JSON text (SRD FR-FILE-1): keys sorted, two-space indent,
## arrays of scalars (coordinates, id lists) kept on one line, floats written losslessly.


static func stringify(value: Variant, indent: String = "  ") -> String:
	return _write(value, indent, 0)


static func _write(value: Variant, indent: String, level: int) -> String:
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.is_empty():
			return "{}"
		var keys: Array[String] = []
		for raw_key: Variant in dict.keys():
			keys.append(str(raw_key))
		keys.sort()
		var inner: String = indent.repeat(level + 1)
		var parts: PackedStringArray = PackedStringArray()
		for key: String in keys:
			parts.append("%s%s: %s" % [inner, _scalar(key), _write(dict[key], indent, level + 1)])
		return "{\n%s\n%s}" % [",\n".join(parts), indent.repeat(level)]
	if value is Array:
		var arr: Array = value
		if arr.is_empty():
			return "[]"
		if _is_scalar_array(arr):
			var items: PackedStringArray = PackedStringArray()
			for item: Variant in arr:
				items.append(_scalar(item))
			return "[%s]" % ", ".join(items)
		var pad: String = indent.repeat(level + 1)
		var lines: PackedStringArray = PackedStringArray()
		for item: Variant in arr:
			lines.append(pad + _write(item, indent, level + 1))
		return "[\n%s\n%s]" % [",\n".join(lines), indent.repeat(level)]
	return _scalar(value)


static func _is_scalar_array(arr: Array) -> bool:
	for item: Variant in arr:
		if item is Dictionary or item is Array:
			return false
	return true


static func _scalar(value: Variant) -> String:
	return JSON.stringify(value, "", false, true)
