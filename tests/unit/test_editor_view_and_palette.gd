extends GutTest
@warning_ignore_start("unsafe_call_argument")

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func test_each_etage_has_its_own_view() -> void:
	var first: ViewTransform = kit.model.view()
	first.zoom = 0.02
	kit.model.new_sheet()
	assert_ne(kit.model.view().zoom, 0.02, "a new étage starts fitted to its page")
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	assert_eq(kit.model.view().zoom, 0.02, "the first view was remembered")


func test_the_initial_view_shows_the_whole_page() -> void:
	var visible: Rect2 = kit.model.view().visible_world_rect()
	assert_true(visible.encloses(FrameBuilder.page_rect(kit.sheet())))


func test_wheel_pans_vertically_and_shift_wheel_horizontally() -> void:
	var view: ViewTransform = kit.model.view()
	var centre: Vector2 = view.center
	kit.wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(5000, 5000))
	assert_true(view.center.y > centre.y or view.center.y < centre.y, "vertical pan")
	assert_eq(view.center.x, centre.x)
	var after_vertical: Vector2 = view.center
	kit.wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(5000, 5000), true)
	assert_ne(view.center.x, after_vertical.x, "shift+wheel pans horizontally")
	assert_eq(view.center.y, after_vertical.y)


func test_ctrl_wheel_zooms_around_the_cursor() -> void:
	var view: ViewTransform = kit.model.view()
	var cursor: Vector2 = Vector2(12000, 7000)
	var screen: Vector2 = view.world_to_screen(cursor)
	var before: float = view.zoom
	kit.wheel(MOUSE_BUTTON_WHEEL_UP, cursor, false, true)
	assert_true(view.zoom > before)
	assert_true(view.world_to_screen(cursor).distance_to(screen) < 0.01, "the point under the cursor did not move")
	kit.wheel(MOUSE_BUTTON_WHEEL_DOWN, cursor, false, true)
	assert_almost_eq(view.zoom, before, 0.0001)


func test_space_drag_and_middle_drag_pan_without_touching_the_document() -> void:
	var view: ViewTransform = kit.model.view()
	var before: Vector2 = view.center
	kit.key(KEY_SPACE)
	var start: Vector2 = Vector2(5000, 5000)
	kit.press(start)
	var moved: InputEventMouseMotion = InputEventMouseMotion.new()
	moved.position = kit.screen(start) + Vector2(100, 40)
	kit.input.handle(moved)
	kit.release(start)
	kit.key_up(KEY_SPACE)
	assert_ne(view.center, before, "space+drag pans")
	assert_eq(kit.sheet().entities.size(), 0, "and does not draw")
	var middle_before: Vector2 = view.center
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = Vector2(300, 300)
	kit.input.handle(press)
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.position = Vector2(400, 300)
	kit.input.handle(drag)
	press.pressed = false
	kit.input.handle(press)
	assert_ne(view.center, middle_before, "middle button pans")


func test_ctrl_p_and_ctrl_n_are_forwarded_to_the_window() -> void:
	watch_signals(kit.input)
	kit.key(KEY_P, false, true)
	kit.key(KEY_N, false, true)
	assert_signal_emitted(kit.input, "palette_requested")
	assert_signal_emitted(kit.input, "new_window_requested")


func test_unbound_keys_are_not_consumed() -> void:
	assert_false(kit.key(KEY_Q), "Q is not bound")
	assert_false(kit.key(KEY_J))
	assert_false(kit.key(KEY_S, false, false, true), "Alt+S is not bound")


func test_tool_keys_are_ignored_with_ctrl() -> void:
	kit.key(KEY_W, false, true)
	assert_eq(kit.model.tool_name, "select")


func test_escape_clears_the_selection_when_nothing_else_to_cancel() -> void:
	var w: String = kit.add("wall", {"points": [[0, 0], [100, 0]]})
	kit.model.set_selection([w])
	kit.key(KEY_ESCAPE)
	assert_eq(kit.model.selection, [])


func test_changing_tool_cancels_a_gesture_in_progress() -> void:
	kit.key(KEY_W)
	kit.click(Vector2(1000, 1000))
	kit.key(KEY_D)
	kit.key(KEY_W)
	kit.key(KEY_ENTER)
	assert_eq(kit.entities_of("wall").size(), 0, "the half-drawn wall was discarded")


# --- palette -------------------------------------------------------------------------------

func test_palette_lists_french_commands_with_their_shortcuts() -> void:
	var entries: Array[EditorCommands.Entry] = EditorCommands.build(kit.model)
	var by_id: Dictionary = {}
	for entry: EditorCommands.Entry in entries:
		by_id[entry.id] = entry
	assert_true(by_id.has("sheet.duplicate"))
	assert_eq(by_id["sheet.new"].shortcut, "Ctrl+T")
	assert_eq(by_id["tool.wall"].shortcut, "W")
	assert_eq(by_id["edit.undo"].title, "Annuler")


func test_palette_search_finds_commands_fuzzily() -> void:
	var entries: Array[EditorCommands.Entry] = EditorCommands.build(kit.model)
	var hits: Array[int] = EditorCommands.search(entries, "dupl etage")
	assert_true(hits.size() >= 2)
	assert_eq(entries[hits[0]].id, "sheet.duplicate", "the shorter title ranks first")
	var ghost: Array[int] = EditorCommands.search(entries, "fantome")
	assert_eq(entries[ghost[0]].id, "sheet.ghost", "accents are ignored")
	assert_eq(EditorCommands.search(entries, "").size(), entries.size(), "empty query lists everything")
	assert_eq(EditorCommands.search(entries, "zzzzqq").size(), 0)


func test_palette_actions_work() -> void:
	var entries: Array[EditorCommands.Entry] = EditorCommands.build(kit.model)
	for entry: EditorCommands.Entry in entries:
		if entry.id == "sheet.duplicate":
			entry.action.call()
	assert_eq(kit.doc().plan_ids().size(), 2)
	for entry: EditorCommands.Entry in entries:
		if entry.id == "tool.stair":
			entry.action.call()
	assert_eq(kit.model.tool_name, "stair")
	for entry: EditorCommands.Entry in entries:
		if entry.id == "edit.snap":
			entry.action.call()
	assert_false(kit.model.snap_enabled)


# --- fuzzy ---------------------------------------------------------------------------------

func test_fuzzy_basics() -> void:
	assert_true(Fuzzy.score("nvl", "Nouvel étage") >= 0)
	assert_eq(Fuzzy.score("xyz", "Nouvel étage"), -1)
	assert_true(Fuzzy.score("ETAGE", "Nouvel étage") >= 0, "case and accent insensitive")
	assert_true(Fuzzy.score("etage", "Nouvel étage") > Fuzzy.score("etge", "Nouvel étage"), "a contiguous match scores higher")
	assert_true(Fuzzy.score("sup", "Supprimer l'étage") > Fuzzy.score("sup", "Étage suivant précédent supprimé"), "start of the title wins")
	assert_eq(Fuzzy.normalize("Œuvre à Ç"), "oeuvre a c")


func test_fuzzy_rank_is_stable_for_equal_scores() -> void:
	var ranked: Array[int] = Fuzzy.rank("a", PackedStringArray(["a1", "a2", "b"]))
	assert_eq(ranked, [0, 1])


func test_the_page_is_refitted_when_the_viewport_gets_its_real_size() -> void:
	var fresh: EditorKit = EditorKit.create()
	fresh.model.set_viewport_size(Vector2(0, 0))
	var tiny: float = fresh.model.view().zoom
	fresh.model.set_viewport_size(Vector2(1600, 800))
	assert_true(fresh.model.view().zoom > tiny * 3.0, "the untouched view was refitted")
	assert_true(fresh.model.view().visible_world_rect().encloses(FrameBuilder.page_rect(fresh.sheet())))
	fresh.model.view().pan_by_screen(Vector2(10, 0))
	var kept: float = fresh.model.view().zoom
	fresh.model.set_viewport_size(Vector2(800, 400))
	assert_eq(fresh.model.view().zoom, kept, "a view the user has moved is left alone")
