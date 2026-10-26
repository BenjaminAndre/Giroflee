class_name PlanRenderer
extends RefCounted
## Turns a plan sheet into a DrawList (SRD ARCH-12). Pure: same document, same list.
##
## Order (bottom to top): ghost sheets, frame, grey blocks, stairs, openings, walls, labels,
## étage title. Within a type, entities are drawn in id order, so output is deterministic.

const TYPE_ORDER: Array[String] = ["grey_block", "stair", "opening", "wall", "text"]


## Options: {"ghost": bool} overrides whether the sheet's ghost view is drawn (default: the
## sheet's own `ghost_on`); {"frame": bool} (default true) draws the border frame;
## {"overrides": {entity_id: props}} draws those entities with other properties (live previews
## of drags and resizes, before any command is committed).
static func build(doc: Document, sheet_id: String, options: Dictionary = {}) -> DrawList:
	var list: DrawList = DrawList.new()
	var sheet: Sheet = doc.get_sheet(sheet_id)
	if sheet == null:
		return list
	var ctx: RenderContext = RenderContext.for_sheet(doc, sheet)

	var show_ghost: bool = sheet.props["ghost_on"]
	if options.has("ghost"):
		show_ghost = options["ghost"]
	if show_ghost and sheet.kind == "plan":
		var ghosts: Array = sheet.props["ghost_sheets"]
		for ghost_id: Variant in ghosts:
			var ghost_sheet: Sheet = doc.get_sheet(str(ghost_id))
			if ghost_sheet != null:
				_add_entities(ghost_sheet, ctx, true, list)

	var show_frame: bool = true
	if options.has("frame"):
		show_frame = options["frame"]
	if show_frame:
		FrameBuilder.build(sheet, ctx, list)

	var overrides: Dictionary = {}
	if options.has("overrides"):
		overrides = options["overrides"]
	_add_entities(sheet, ctx, false, list, overrides)
	_add_title(sheet, ctx, list)
	return list


static func _add_entities(sheet: Sheet, ctx: RenderContext, ghost: bool, out: DrawList, overrides: Dictionary = {}) -> void:
	for type: String in TYPE_ORDER:
		for entity_id: String in sheet.sorted_entity_ids():
			var entity: Entity = sheet.entities[entity_id]
			if entity.type != type:
				continue
			if overrides.has(entity_id):
				var props: Dictionary = overrides[entity_id]
				entity = Entity.new(entity_id, entity.type, props)
			EntityGeometry.add_ops(entity, ctx, ghost, out)


## The étage name, typed once, shown as the large dark-red title (SRD 5.1).
static func _add_title(sheet: Sheet, ctx: RenderContext, out: DrawList) -> void:
	var name: String = sheet.display_name()
	if name.is_empty():
		return
	var pos_mm: Array = sheet.props["title_pos_mm"]
	var px: int = pos_mm[0]
	var py: int = pos_mm[1]
	var size: float = ctx.pt_to_world(ctx.font_size_pt * PlanTheme.role_factor("floor"))
	var op: DrawOp = DrawOp.label(name, FrameBuilder.page_to_world(sheet, float(px), float(py)), size, PlanTheme.DARK_RED, "floor_title")
	op.anchor = "center"
	op.bold = true
	out.add(op)
