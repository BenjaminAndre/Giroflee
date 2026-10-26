class_name IdGenerator
extends RefCounted
## Client-side generator of unique ids (UUID v4). Ids are made before a command is submitted,
## never inside command application (SRD ARCH-3). Pass a seed for reproducible tests.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func next_uuid() -> String:
	var bytes: PackedByteArray = PackedByteArray()
	for i: int in 16:
		bytes.append(_rng.randi() & 0xFF)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
