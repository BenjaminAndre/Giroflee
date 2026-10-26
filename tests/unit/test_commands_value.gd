extends GutTest
@warning_ignore_start("unsafe_call_argument")

var s: Session


func before_each() -> void:
	s = TestKit.session()


func test_set_config_is_validated_and_normalised() -> void:
	assert_true(s.run_one("doc.set", {"section": "config", "key": "font_size_pt", "value": 12}).ok)
	var size: Variant = s.document().config["font_size_pt"]
	assert_true(size is float, "ints are stored as float for float keys")
	assert_eq(size, 12.0)
	assert_true(s.run_one("doc.set", {"section": "config", "key": "font_family", "value": "OpenDyslexic"}).ok)
	assert_eq(s.document().config["font_family"], "OpenDyslexic")


func test_set_config_rejects_unknown_key_and_wrong_type() -> void:
	assert_false(s.run_one("doc.set", {"section": "config", "key": "theme", "value": "dark"}).ok)
	assert_false(s.run_one("doc.set", {"section": "config", "key": "font_size_pt", "value": "big"}).ok)
	assert_false(s.run_one("doc.set", {"section": "config", "key": "provisoire_mark", "value": 1}).ok)


func test_set_free_sections_accept_json_values() -> void:
	assert_true(s.run_one("doc.set", {"section": "cartouche", "key": "owner", "value": "Jeanne"}).ok)
	assert_true(s.run_one("doc.set", {"section": "board", "key": "head", "value": {"meter": "kWh", "items": [1, 2]}}).ok)
	assert_true(s.run_one("doc.set", {"section": "circuits", "key": "A", "value": {"title": "Salon"}}).ok)
	assert_eq(s.document().cartouche["owner"], "Jeanne")
	assert_eq(s.document().circuits["A"], {"title": "Salon"})


func test_set_rejects_null_nonjson_and_bad_section() -> void:
	assert_false(s.run_one("doc.set", {"section": "cartouche", "key": "x", "value": null}).ok)
	assert_false(s.run_one("doc.set", {"section": "cartouche", "key": "x", "value": Vector2(1, 2)}).ok)
	assert_false(s.run_one("doc.set", {"section": "cartouche", "key": "x"}).ok, "value required")
	assert_false(s.run_one("doc.set", {"section": "walls", "key": "x", "value": 1}).ok)
	assert_false(s.run_one("doc.set", {"section": "cartouche", "key": "", "value": 1}).ok)


func test_set_same_value_is_an_empty_patch() -> void:
	s.run_one("doc.set", {"section": "cartouche", "key": "owner", "value": "Jeanne"})
	var result: CommandResult = s.run_one("doc.set", {"section": "cartouche", "key": "owner", "value": "Jeanne"})
	assert_true(result.ok)
	assert_eq(result.patch.ops.size(), 0)


func test_unset() -> void:
	s.run_one("doc.set", {"section": "cartouche", "key": "owner", "value": "Jeanne"})
	assert_true(s.run_one("doc.unset", {"section": "cartouche", "key": "owner"}).ok)
	assert_false(s.document().cartouche.has("owner"))
	assert_false(s.run_one("doc.unset", {"section": "cartouche", "key": "owner"}).ok, "already absent")
	assert_false(s.run_one("doc.unset", {"section": "config", "key": "font_family"}).ok, "config keys cannot be unset")


func test_set_stores_a_copy_not_a_reference() -> void:
	var value: Dictionary = {"a": [1, 2]}
	s.run_one("doc.set", {"section": "board", "key": "k", "value": value})
	var inner: Array = value["a"]
	inner.append(3)
	var stored: Dictionary = s.document().board["k"]
	assert_eq(stored["a"], [1, 2], "later edits of the caller's object do not reach the document")
