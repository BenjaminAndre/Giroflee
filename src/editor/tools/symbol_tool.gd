class_name SymbolTool
extends Tool
## Places electric symbols (SRD FR-SYM). A symbol gets the active circuit and the next free index of
## that circuit; with Alt held it reuses the index of the previous placement, which links it to the
## same point (a switch and its lamp). A symbol whose pack type attaches to walls (the socket) sits
## against the wall's drawn edge (its back touching it) and faces into the room, unless the author rotated the placement by
## hand with R. H, V and R act on the placement before the click.

var type: String = ""
var _hover: Vector2 = Vector2.ZERO
var _has_hover: bool = false
var _alt: bool = false


func _init(p_type: String = "") -> void:
	type = p_type


func tool_name() -> String:
	return type


func press(model: EditorModel, input: ToolInput) -> void:
	var props: Dictionary = placement_props(model, input.world, input.alt)
	var id: String = model.new_id()
	var normalized: Dictionary = Schema.normalize(Schema.entity_spec("symbol"), props, true)
	if not JsonUtil.flag(normalized, "ok"):
		model.notice.emit(str(normalized["error"]))
		return
	var full: Dictionary = normalized["props"]
	var solved: Dictionary = LabelSolver.solve(model.sheet(), model.ctx(), [id], [Entity.new(id, "symbol", full)])
	if solved.has(id):
		var offsets: Dictionary = solved[id]
		full.merge(offsets, true)
	var result: CommandResult = model.add_entities([{"id": id, "type": "symbol", "props": full}])
	if result.ok:
		model.note_placed(full)


func move(model: EditorModel, input: ToolInput) -> void:
	_hover = input.world
	_alt = input.alt
	_has_hover = true
	model.changed.emit()


func preview(model: EditorModel) -> DrawList:
	if not _has_hover:
		return DrawList.new()
	return Tool.entity_preview(model, "symbol", placement_props(model, _hover, _alt))


func hint(model: EditorModel) -> String:
	var def: SymbolLibrary.Def = SymbolLibrary.for_pack(model.doc().pack_ref).def(type)
	var title: String = def.title if def != null else type
	return "%s : clic pour placer (circuit %s) · Alt = même point que le précédent · H / V = retourner · R = tourner · Échap = terminer" % [title, model.active_circuit]


## Complete, schema-valid props for a symbol of this tool's type at `world`. `reuse` is the Alt state.
func placement_props(model: EditorModel, world: Vector2, reuse: bool) -> Dictionary:
	var library: SymbolLibrary = SymbolLibrary.for_pack(model.doc().pack_ref)
	var def: SymbolLibrary.Def = library.def(type)
	var props: Dictionary = {
		"symbol_type": type, "pos": [0, 0],
		"rotation": model.place_rotation, "flip_h": model.place_flip_h, "flip_v": model.place_flip_v,
		"count": model.place_count,
	}
	if def == null or def.uses_circuit:
		props["circuit"] = model.active_circuit
		props["index"] = model.index_for_placement(reuse)
	var snapped: Vector2 = model.snap(world).pos
	props["pos"] = [roundi(snapped.x), roundi(snapped.y)]
	if def != null and def.attach == "wall" and not model.place_rotation_manual:
		_attach_to_wall(model, world, props)
	return props


## Moves `props` onto the drawn edge of the nearest wall, facing into the room (FR-SYM-4).
func _attach_to_wall(model: EditorModel, world: Vector2, props: Dictionary) -> void:
	var hit: WallLocator.Hit = WallLocator.locate(model.sheet(), world, model.tolerance(28.0), model.spatial())
	if hit == null:
		return
	var wall: Entity = model.sheet().entities[hit.wall_id]
	var library: SymbolLibrary = SymbolLibrary.for_pack(model.doc().pack_ref)
	var half: float = EntityGeometry.wall_weight_world(wall.props, model.ctx()) * 0.5 + SymbolGeometry.back_depth(library.def(type), model.ctx())
	var along: float = roundf(hit.offset_mm / 50.0) * 50.0
	var on_line: Vector2 = hit.point + hit.direction * (along - hit.offset_mm)
	var normal: Vector2 = Vector2(-hit.direction.y, hit.direction.x) * float(hit.side)
	var at: Vector2 = on_line + normal * half
	props["pos"] = [roundi(at.x), roundi(at.y)]
	# the artwork faces +y at rotation 0
	props["rotation"] = fposmod(snappedf(rad_to_deg(atan2(-normal.x, normal.y)), 0.01), 360.0)
