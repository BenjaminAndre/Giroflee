extends GutTest
@warning_ignore_start("unsafe_call_argument")

var kit: EditorKit


func before_each() -> void:
	kit = EditorKit.create()


func _names() -> Array[String]:
	var out: Array[String] = []
	for id: String in kit.doc().plan_ids():
		out.append(kit.doc().get_sheet(id).display_name())
	return out


func test_a_new_project_starts_with_one_empty_etage() -> void:
	assert_eq(kit.doc().plan_ids().size(), 1)
	assert_eq(_names(), ["Rez"])
	assert_eq(kit.model.active_sheet_id, kit.doc().plan_ids()[0])
	assert_false(kit.session.can_undo(), "creating the first étage is not an undo step")


func test_new_sheet_inherits_settings_gets_a_free_name_and_becomes_active() -> void:
	kit.model.set_sheet_props({"scale_den": 100, "grid_step_mm": 250})
	kit.model.new_sheet()
	assert_eq(_names(), ["Rez", "Étage"])
	assert_eq(kit.sheet().props["scale_den"], 100)
	assert_eq(kit.sheet().props["grid_step_mm"], 250)
	assert_eq(kit.sheet().display_name(), "Étage")
	kit.model.new_sheet()
	assert_eq(kit.sheet().display_name(), "Étage 2", "names stay unique")
	assert_eq(kit.doc().plan_ids().find(kit.model.active_sheet_id), 2)


func test_new_sheet_goes_right_after_the_active_one() -> void:
	kit.model.new_sheet()
	kit.model.new_sheet()
	kit.model.set_active_sheet(kit.doc().plan_ids()[0])
	kit.model.new_sheet()
	assert_eq(kit.doc().plan_ids().find(kit.model.active_sheet_id), 1)


func test_ctrl_t_creates_an_etage_and_ctrl_tab_cycles() -> void:
	kit.key(KEY_T, false, true)
	assert_eq(_names(), ["Rez", "Étage"])
	var second: String = kit.model.active_sheet_id
	kit.key(KEY_TAB, false, true)
	assert_eq(kit.model.sheet().kind, "unifilaire", "the unifilaire is part of the cycle")
	kit.key(KEY_TAB, false, true)
	assert_eq(kit.model.active_sheet_id, kit.doc().plan_ids()[0])
	kit.key(KEY_TAB, true, true)
	assert_eq(kit.model.sheet().kind, "unifilaire", "Ctrl+Shift+Tab goes back")
	kit.key(KEY_TAB, true, true)
	assert_eq(kit.model.active_sheet_id, second, "and wraps to the last étage")


func test_duplicate_copies_the_architecture_but_not_the_symbols() -> void:
	var wall: String = kit.add("wall", {"points": [[0, 0], [4000, 0]]})
	kit.add("opening", {"kind": "door", "pos": [1000, 0], "width_mm": 900, "host_wall": wall, "host_offset_mm": 1000})
	kit.add("grey_block", {"pos": [0, 0], "size": [500, 500]})
	kit.add("stair", {"pos": [0, 0], "width_mm": 900, "steps": 10, "tread_mm": 250})
	kit.add("text", {"pos": [0, 0], "text": "Salon", "role": "room"})
	kit.add("symbol", {"symbol_type": "lamp", "pos": [10, 10], "circuit": "A", "index": 1})
	var source_id: String = kit.model.active_sheet_id
	kit.model.duplicate_sheet(false)
	assert_eq(_names(), ["Rez", "Rez (copie)"])
	assert_eq(kit.sheet().entities.size(), 5, "the symbol stayed behind")
	assert_eq(kit.entities_of("symbol").size(), 0)
	assert_ne(kit.model.active_sheet_id, source_id)
	var copied_wall: String = kit.entities_of("wall")[0].id
	assert_ne(copied_wall, wall, "fresh ids")
	assert_eq(kit.entities_of("opening")[0].props["host_wall"], copied_wall, "the door follows the copied wall, not the original")
	assert_eq(kit.doc().check_integrity(), "")


func test_duplicate_with_symbols_copies_everything() -> void:
	kit.add("wall", {"points": [[0, 0], [4000, 0]]})
	kit.add("symbol", {"symbol_type": "lamp", "pos": [10, 10], "circuit": "A", "index": 1})
	kit.model.duplicate_sheet(true)
	assert_eq(kit.sheet().entities.size(), 2)
	assert_eq(kit.entities_of("symbol").size(), 1)


func test_duplicate_is_one_undo_step_and_keeps_sheet_settings() -> void:
	kit.model.set_sheet_props({"scale_den": 100})
	kit.add("wall", {"points": [[0, 0], [4000, 0]]})
	kit.session.history.clear()
	kit.model.duplicate_sheet(false)
	assert_eq(kit.sheet().props["scale_den"], 100)
	assert_eq(kit.session.history.undo_depth(), 1)
	kit.key(KEY_Z, false, true)
	assert_eq(kit.doc().plan_ids().size(), 1)
	assert_eq(kit.model.active_sheet_id, kit.doc().plan_ids()[0], "active étage falls back after the undo")
	assert_eq(kit.doc().check_integrity(), "")


func test_duplicating_an_empty_etage_works() -> void:
	kit.model.duplicate_sheet(false)
	assert_eq(kit.doc().plan_ids().size(), 2)


func test_delete_sheet_picks_a_neighbour_and_refuses_the_last_one() -> void:
	kit.model.new_sheet()
	kit.model.new_sheet()
	kit.model.set_active_sheet(kit.doc().plan_ids()[1])
	var doomed: String = kit.model.active_sheet_id
	kit.model.delete_sheet()
	assert_false(kit.doc().sheets.has(doomed))
	assert_eq(kit.doc().plan_ids().size(), 2)
	assert_true(kit.doc().sheets.has(kit.model.active_sheet_id))
	kit.model.delete_sheet()
	watch_signals(kit.model)
	kit.model.delete_sheet()
	assert_eq(kit.doc().plan_ids().size(), 1, "the last étage cannot be deleted")
	assert_signal_emitted(kit.model, "notice")


func test_rename_trims_and_ignores_empty_names() -> void:
	var id: String = kit.model.active_sheet_id
	kit.model.rename_sheet(id, "  +1  ")
	assert_eq(kit.sheet().display_name(), "+1")
	kit.model.rename_sheet(id, "   ")
	assert_eq(kit.sheet().display_name(), "+1")


func test_f2_renames_the_etage_when_nothing_is_selected_and_edits_a_selected_text() -> void:
	watch_signals(kit.model)
	kit.key(KEY_F2)
	assert_signal_emitted(kit.model, "rename_requested")
	var t: String = kit.add("text", {"pos": [100, 100], "text": "Hall"})
	kit.model.set_selection([t])
	kit.key(KEY_F2)
	assert_signal_emitted(kit.model, "text_requested")


func test_selection_does_not_follow_to_another_etage() -> void:
	var w: String = kit.add("wall", {"points": [[0, 0], [100, 0]]})
	kit.model.set_selection([w])
	kit.model.new_sheet()
	assert_eq(kit.model.selection, [])


func test_ghost_toggle_defaults_to_the_etage_below() -> void:
	kit.model.new_sheet()
	var below: String = kit.doc().plan_ids()[0]
	assert_false(kit.doc().config["ghost_on"], "off by default (FR-PLAN-7)")
	kit.model.toggle_ghost()
	assert_true(kit.doc().config["ghost_on"])
	assert_eq(kit.sheet().props["ghost_sheets"], [below])
	kit.model.toggle_ghost()
	assert_false(kit.doc().config["ghost_on"])
	assert_eq(kit.sheet().props["ghost_sheets"], [below], "the chosen étage is remembered")


func test_hints_toggle() -> void:
	assert_true(kit.doc().config["hints"])
	kit.model.toggle_hints()
	assert_false(kit.doc().config["hints"])


# --- clipboard / duplicate / rotate / flip ----------------------------------------------------

func test_copy_paste_creates_new_entities_with_the_same_shape() -> void:
	var w: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	kit.model.set_selection([w])
	kit.key(KEY_C, false, true)
	kit.move(Vector2(9000, 8000))
	kit.key(KEY_V, false, true)
	assert_eq(kit.entities_of("wall").size(), 2)
	var pasted: String = kit.model.selection[0]
	assert_ne(pasted, w)
	assert_eq(kit.doc().find_entity(pasted).props["points"], [[9000, 8000], [13000, 8000]], "origin lands on the cursor, snapped")


func test_paste_keeps_the_door_attached_to_the_pasted_wall() -> void:
	var w: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	kit.add("opening", {"kind": "door", "pos": [3000, 2000], "width_mm": 900, "host_wall": w, "host_offset_mm": 1000})
	kit.model.set_selection([w])
	kit.model.copy_selection()
	kit.model.paste(Vector2(2000, 8000))
	var walls: Array[Entity] = kit.entities_of("wall")
	assert_eq(walls.size(), 2)
	assert_eq(kit.entities_of("opening").size(), 2, "the hosted door travelled with the wall")
	assert_eq(kit.model.selection.size(), 2)
	for door: Entity in kit.entities_of("opening"):
		var host: String = door.props["host_wall"]
		assert_true(kit.doc().has_entity(host), "no dangling host")
	assert_eq(kit.doc().check_integrity(), "")


func test_paste_of_a_door_whose_wall_was_not_copied_is_free_standing() -> void:
	var w: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	var d: String = kit.add("opening", {"kind": "door", "pos": [3000, 2000], "width_mm": 900, "host_wall": w, "host_offset_mm": 1000})
	kit.model.set_selection([d])
	kit.model.copy_selection()
	kit.model.paste(Vector2(3000, 5000))
	var pasted: Entity = kit.doc().find_entity(kit.model.selection[0])
	assert_eq(pasted.props["host_wall"], "")
	assert_eq(pasted.props["host_offset_mm"], 0)


func test_paste_works_across_etages_and_projects() -> void:
	var w: String = kit.add("wall", {"points": [[0, 0], [4000, 0]]})
	kit.model.set_selection([w])
	kit.model.copy_selection()
	var other: EditorKit = EditorKit.create(99)
	other.model.clipboard_text = kit.model.clipboard_text
	other.model.paste(Vector2(1000, 1000))
	assert_eq(other.entities_of("wall").size(), 1)
	kit.model.new_sheet()
	kit.model.paste(Vector2(1000, 1000))
	assert_eq(kit.entities_of("wall").size(), 1)


func test_pasting_ordinary_text_does_nothing() -> void:
	kit.model.clipboard_text = "just some words"
	watch_signals(kit.model)
	kit.model.paste()
	assert_signal_emitted(kit.model, "notice")
	assert_eq(kit.sheet().entities.size(), 0)


func test_cut_removes_and_copies() -> void:
	var w: String = kit.add("wall", {"points": [[0, 0], [4000, 0]]})
	kit.model.set_selection([w])
	kit.key(KEY_X, false, true)
	assert_eq(kit.entities_of("wall").size(), 0)
	kit.model.paste(Vector2(0, 0))
	assert_eq(kit.entities_of("wall").size(), 1)


func test_ctrl_d_duplicates_offset_and_keeps_the_clipboard() -> void:
	var w: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	kit.model.clipboard_text = "previous clipboard"
	kit.model.set_selection([w])
	kit.key(KEY_D, false, true)
	assert_eq(kit.entities_of("wall").size(), 2)
	assert_ne(kit.model.selection[0], w, "the copy is selected")
	assert_eq(kit.doc().find_entity(kit.model.selection[0]).props["points"][0], [2200, 1800], "offset by two grid steps")
	assert_eq(kit.model.clipboard_text, "previous clipboard")


func test_delete_removes_the_selection() -> void:
	var w: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000]]})
	kit.model.set_selection([w])
	kit.key(KEY_DELETE)
	assert_eq(kit.entities_of("wall").size(), 0)
	assert_eq(kit.model.selection, [])


func test_select_all_and_arrow_nudge_use_the_grid_step() -> void:
	var a: String = kit.add("grey_block", {"pos": [1000, 1000], "size": [100, 100]})
	var b: String = kit.add("grey_block", {"pos": [3000, 1000], "size": [100, 100]})
	kit.key(KEY_A, false, true)
	assert_eq(kit.model.selection.size(), 2)
	kit.key(KEY_RIGHT)
	kit.key(KEY_UP)
	assert_eq(kit.doc().find_entity(a).props["pos"], [1100, 1100])
	assert_eq(kit.doc().find_entity(b).props["pos"], [3100, 1100])


func test_rotating_four_times_returns_exactly_to_the_start() -> void:
	var w: String = kit.add("wall", {"points": [[2000, 2000], [6000, 2000], [6000, 3500]]})
	var d: String = kit.add("opening", {"kind": "door", "pos": [3000, 2000], "width_mm": 900})
	var before: Dictionary = kit.doc().find_entity(w).props.duplicate(true)
	var door_before: Dictionary = kit.doc().find_entity(d).props.duplicate(true)
	kit.model.set_selection([w, d])
	for i: int in 4:
		kit.key(KEY_R)
	assert_eq(kit.doc().find_entity(w).props["points"], before["points"])
	assert_eq(kit.doc().find_entity(d).props["pos"], door_before["pos"])
	assert_eq(kit.doc().find_entity(d).props["rotation"], 0.0)


func test_rotation_direction_and_pivot() -> void:
	var b: String = kit.add("grey_block", {"pos": [1000, 1000], "size": [2000, 1000]})
	kit.model.set_selection([b])
	kit.key(KEY_R, true)
	var props: Dictionary = kit.doc().find_entity(b).props
	assert_eq(props["rotation"], 90.0, "Shift+R is counter-clockwise (math angles)")
	var bounds: Rect2 = EntityGeometry.bounds(kit.doc().find_entity(b), kit.model.ctx())
	assert_eq(bounds.get_center(), Vector2(2000, 1500), "rotated about the centre of its bounds")
	assert_eq(bounds.size, Vector2(1000, 2000))


func test_h_and_v_flip_the_selection_only_for_flippable_entities() -> void:
	var d: String = kit.add("opening", {"kind": "door", "pos": [0, 0], "width_mm": 900})
	var w: String = kit.add("wall", {"points": [[0, 0], [100, 0]]})
	kit.model.set_selection([d, w])
	kit.key(KEY_H)
	assert_eq(kit.doc().find_entity(d).props["flip_h"], true)
	kit.key(KEY_V)
	assert_eq(kit.doc().find_entity(d).props["flip_v"], true)
	kit.key(KEY_H)
	assert_eq(kit.doc().find_entity(d).props["flip_h"], false)


func test_apply_props_edits_several_entities_in_one_step() -> void:
	var a: String = kit.add("text", {"pos": [0, 0], "text": "A"})
	var b: String = kit.add("text", {"pos": [0, 500], "text": "B"})
	kit.session.history.clear()
	assert_true(kit.model.apply_props([a, b], {"size_pt": 18.0, "font": "OpenDyslexic"}).ok)
	assert_eq(kit.doc().find_entity(b).props["size_pt"], 18.0)
	assert_eq(kit.session.history.undo_depth(), 1)


func test_failed_actions_report_through_notice() -> void:
	watch_signals(kit.model)
	kit.model.apply_props(["ghost"], {"size_pt": 1.0})
	assert_signal_emitted(kit.model, "notice")


func test_snap_can_be_toggled_off() -> void:
	kit.model.snap_enabled = false
	var s: SnapEngine.Result = kit.model.snap(Vector2(1234, 5678))
	assert_eq(s.pos, Vector2(1234, 5678))
