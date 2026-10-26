extends GutTest
@warning_ignore_start("unsafe_call_argument")


func _parse(text: String) -> Variant:
	var json: JSON = JSON.new()
	assert_eq(json.parse(text), OK, "writer output must be valid JSON: " + text)
	return json.data


func test_keys_are_sorted_and_scalar_arrays_stay_on_one_line() -> void:
	var text: String = JsonWriter.stringify({"b": [1, 2], "a": "x"})
	assert_eq(text, "{\n  \"a\": \"x\",\n  \"b\": [1, 2]\n}")


func test_arrays_of_arrays_get_one_element_per_line() -> void:
	var text: String = JsonWriter.stringify({"points": [[0, 0], [10, 5]]})
	assert_eq(text, "{\n  \"points\": [\n    [0, 0],\n    [10, 5]\n  ]\n}")


func test_empty_containers() -> void:
	assert_eq(JsonWriter.stringify({"a": {}, "b": []}), "{\n  \"a\": {},\n  \"b\": []\n}")


func test_output_parses_back_to_the_same_data() -> void:
	var data: Dictionary = {
		"name": "Étage \"1\"",
		"nums": [1, 2.5, -3],
		"nested": {"list": [{"k": true}, {"k": false}], "empty": []},
		"text": "line\nbreak\ttab",
	}
	var back: Dictionary = _parse(JsonWriter.stringify(data))
	assert_eq(back["name"], "Étage \"1\"")
	assert_eq(back["text"], "line\nbreak\ttab")
	assert_eq(back["nums"], [1.0, 2.5, -3.0])
	var nested: Dictionary = back["nested"]
	var list: Array = nested["list"]
	assert_eq(list.size(), 2)


func test_floats_keep_full_precision() -> void:
	var value: float = 0.1 + 0.2
	var back: Dictionary = _parse(JsonWriter.stringify({"v": value}))
	assert_eq(back["v"], value, "lossless float round trip")


func test_output_is_idempotent_through_a_parse() -> void:
	# floats on purpose: JSON parsing reads every number as a float
	var data: Dictionary = {"z": [[1.0, 2.0], [3.0, 4.0]], "a": {"y": 1.5, "x": [0.5]}}
	var once: String = JsonWriter.stringify(data)
	var twice: String = JsonWriter.stringify(_parse(once))
	assert_eq(twice, once)
