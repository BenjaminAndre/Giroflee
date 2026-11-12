class_name ReportBuilder
extends RefCounted
## Checks the project and lists what is missing or doubtful (SRD section 9). Pure and deterministic:
## the same document gives the same issues in the same order. Nothing here blocks anything.

## Order of the rules in the list (after the errors-first sort).
const RULE_ORDER: Array[String] = [
	"symbol_without_circuit", "symbol_without_index", "control_without_consumer", "head_chain",
	"cartouche_required", "consumer_without_control", "circuit_defaults", "max_points", "breaker_cable",
	"differential_required", "bathroom", "outside_page", "unifilaire_layout", "rule_unconfigured",
]


## All issues, errors first. Acknowledged ones are included and flagged.
static func build(doc: Document) -> Array[Issue]:
	var library: SymbolLibrary = SymbolLibrary.for_pack(doc.pack_ref)
	var catalog: Catalog = Catalog.for_pack(doc.pack_ref)
	var rules: Rules = Rules.for_pack(doc.pack_ref)
	var model: UniModel = UnifilaireBuilder.derive(doc)
	var uni: Sheet = doc.unifilaire_sheet()
	var uni_id: String = uni.id if uni != null else ""
	var issues: Array[Issue] = []

	_symbols_without_circuit(doc, library, issues)
	_points(doc, model, library, uni_id, issues)
	_head_chain(model, catalog, rules, uni_id, issues)
	_cartouche(doc, rules, uni_id, issues)
	_circuit_defaults(model, uni_id, issues)
	_max_points(doc, model, rules, uni_id, issues)
	_breaker_cable(model, catalog, rules, uni_id, issues)
	_differentials(model, catalog, rules, uni_id, issues)
	_bathroom(doc, rules, issues)
	_outside_page(doc, issues)
	for note: String in model.warnings + _layout_warnings(doc, uni, model):
		issues.append(_make("unifilaire_layout", Issue.WARNING, note, uni_id, [], "", "", note))

	for issue: Issue in issues:
		issue.acknowledged = doc.acknowledgements.has(issue.key)
	issues.sort_custom(_before)
	return issues


## Open errors: what makes an export "provisoire" (SRD FR-RPT-5).
static func open_errors(doc: Document) -> int:
	var count: int = 0
	for issue: Issue in build(doc):
		if issue.is_error() and not issue.acknowledged:
			count += 1
	return count


# --- rules -----------------------------------------------------------------------------------------


static func _symbols_without_circuit(doc: Document, library: SymbolLibrary, out: Array[Issue]) -> void:
	for sheet_id: String in doc.plan_ids():
		var sheet: Sheet = doc.get_sheet(sheet_id)
		var no_circuit: Array[String] = []
		var no_index: Array[String] = []
		for entity_id: String in sheet.sorted_entity_ids():
			var entity: Entity = sheet.entities[entity_id]
			if entity.type != "symbol":
				continue
			var def: SymbolLibrary.Def = library.def(str(entity.props["symbol_type"]))
			if def != null and not def.uses_circuit:
				continue
			var index: int = entity.props["index"]
			if entity.props["circuit"] == "":
				no_circuit.append(entity_id)
			elif index <= 0:
				no_index.append(entity_id)
		if not no_circuit.is_empty():
			out.append(_make("symbol_without_circuit", Issue.ERROR, "%d symbole(s) sans circuit sur « %s »" % [no_circuit.size(), sheet.display_name()], sheet_id, no_circuit, "", "", no_circuit))
		if not no_index.is_empty():
			out.append(_make("symbol_without_index", Issue.ERROR, "%d symbole(s) avec un circuit mais sans indice sur « %s »" % [no_index.size(), sheet.display_name()], sheet_id, no_index, "", "", no_index))


static func _points(doc: Document, model: UniModel, library: SymbolLibrary, uni_id: String, out: Array[Issue]) -> void:
	for column: UniModel.Column in model.columns:
		for point: UniModel.Point in column.sorted_points():
			var label: String = "%s%d" % [column.letter, point.index]
			var first_sheet: String = doc.sheet_id_of_entity(point.symbol_ids[0]) if not point.symbol_ids.is_empty() else uni_id
			if point.is_open():
				out.append(_make("control_without_consumer", Issue.ERROR, "Point %s : un interrupteur sans lampe ni prise à commander" % label, first_sheet, point.symbol_ids, column.letter, "", point.symbol_ids))
				continue
			var needs: bool = false
			for item: UniModel.Item in point.items:
				var def: SymbolLibrary.Def = library.def(item.type)
				needs = needs or (def != null and def.needs_control)
			if needs and not point.has_control:
				out.append(_make("consumer_without_control", Issue.WARNING, "Point %s : une lampe sans interrupteur" % label, first_sheet, point.symbol_ids, column.letter, "", point.symbol_ids))


static func _head_chain(model: UniModel, catalog: Catalog, rules: Rules, uni_id: String, out: Array[Issue]) -> void:
	if model.head.is_empty():
		out.append(_make("head_chain", Issue.ERROR, "Tête de ligne absente : compteur, différentiel et disjoncteur général à choisir", uni_id, [], "", "", "empty"))
		return
	var kinds: Array[String] = []
	for entry: Dictionary in model.head:
		var item: Catalog.Item = catalog.item(str(entry["catalog"]))
		if item != null:
			kinds.append(item.kind)
	var wanted: Dictionary = rules.head_requirements()
	var required: Array = wanted["kinds"]
	var names: Dictionary = {"meter": "compteur", "breaker": "disjoncteur général", "differential": "différentiel de tête"}
	for kind: Variant in required:
		if not kinds.has(str(kind)):
			out.append(_make("head_chain", Issue.ERROR, "Tête de ligne incomplète : %s manquant" % str(names.get(kind, kind)), uni_id, [], "", "", "missing %s" % str(kind)))


static func _cartouche(doc: Document, rules: Rules, uni_id: String, out: Array[Issue]) -> void:
	var labels: Dictionary = CartoucheBuilder.field_labels(doc.pack_ref)
	for key: String in rules.required_cartouche_fields():
		if str(doc.cartouche.get(key, "")).strip_edges().is_empty():
			out.append(_make("cartouche_required", Issue.ERROR, "Cartouche : « %s » est vide" % str(labels.get(key, key)), uni_id, [], "", "", key))


static func _circuit_defaults(model: UniModel, uni_id: String, out: Array[Issue]) -> void:
	for column: UniModel.Column in model.columns:
		var parts: PackedStringArray = PackedStringArray()
		if column.breaker_defaulted:
			parts.append("disjoncteur")
		if column.cable_defaulted:
			parts.append("câble")
		if not parts.is_empty():
			out.append(_make("circuit_defaults", Issue.WARNING, "Circuit %s : %s par défaut, à confirmer" % [column.letter, " et ".join(parts)], uni_id, [], column.letter, "", [column.breaker, column.cable]))


static func _max_points(doc: Document, model: UniModel, rules: Rules, uni_id: String, out: Array[Issue]) -> void:
	var limit: int = rules.max_points()
	if limit < 0:
		out.append(_unconfigured("max_points_per_circuit"))
		return
	for column: UniModel.Column in model.columns:
		var count: int = Numbering.point_count(doc, column.letter)
		if count > limit:
			out.append(_make("max_points", Issue.WARNING, "Circuit %s : %d points (maximum %d)" % [column.letter, count, limit], uni_id, [], column.letter, "", count))


static func _breaker_cable(model: UniModel, catalog: Catalog, rules: Rules, uni_id: String, out: Array[Issue]) -> void:
	var allowed: Array = rules.allowed_pairs()
	if allowed.is_empty():
		out.append(_unconfigured("breaker_cable_pairs"))
		return
	for column: UniModel.Column in model.columns:
		var breaker: Catalog.Item = catalog.item(column.breaker)
		var cable: Catalog.Item = catalog.item(column.cable)
		if breaker == null or cable == null or breaker.rating_a == 0 or cable.section_mm2 == 0.0:
			continue
		var fits: bool = false
		for raw: Variant in allowed:
			var pair: Dictionary = raw
			var rating: Variant = pair.get("breaker_a")
			var section: Variant = pair.get("section_mm2")
			if JsonUtil.is_number(rating) and JsonUtil.is_number(section) and is_equal_approx(JsonUtil.to_float(rating), float(breaker.rating_a)) and is_equal_approx(JsonUtil.to_float(section), cable.section_mm2):
				fits = true
		if not fits:
			out.append(_make("breaker_cable", Issue.WARNING, "Circuit %s : disjoncteur %s avec câble %s, couple non prévu" % [column.letter, breaker.label, cable.label], uni_id, [], column.letter, "", [column.breaker, column.cable]))


## Smallest residual current (mA) of the differentials in front of bus slot `slot` (head chain and
## bus devices before it); 0 when none.
static func _protection_ma(model: UniModel, catalog: Catalog, slot: int) -> int:
	var best: int = 0
	var seen: Array[String] = []
	for entry: Dictionary in model.head:
		seen.append(str(entry["catalog"]))
	for i: int in slot:
		if model.bus[i].is_device:
			seen.append(model.bus[i].catalog)
	for catalog_id: String in seen:
		var item: Catalog.Item = catalog.item(catalog_id)
		if item != null and item.kind == "differential" and item.residual_ma > 0:
			best = item.residual_ma if best == 0 else mini(best, item.residual_ma)
	return best


static func _differentials(model: UniModel, catalog: Catalog, rules: Rules, uni_id: String, out: Array[Issue]) -> void:
	var parsed: Dictionary = rules.differential_rules()
	var unconfigured: int = parsed["unconfigured"]
	var configured: Array = parsed["configured"]
	if unconfigured > 0:
		out.append(_unconfigured("differential_required"))
	for raw: Variant in configured:
		var rule: Dictionary = raw
		var type: String = rule["symbol_type"]
		var limit: int = rule["max_ma"]
		for slot: int in model.bus.size():
			if model.bus[slot].is_device:
				continue
			var column: UniModel.Column = model.columns[model.bus[slot].column]
			if not _has_type(column, type):
				continue
			var protection: int = _protection_ma(model, catalog, slot)
			if protection == 0 or protection > limit:
				out.append(_make("differential_required", Issue.WARNING, "Circuit %s : %s sans différentiel de %d mA ou moins en amont" % [column.letter, _type_name(type), limit], uni_id, [], column.letter, "", [type, limit, protection]))


static func _has_type(column: UniModel.Column, type: String) -> bool:
	for point: UniModel.Point in column.sorted_points():
		for item: UniModel.Item in point.items:
			if item.type == type:
				return true
	return false


static func _type_name(type: String) -> String:
	var names: Dictionary = {"socket": "prises", "lamp": "lampes"}
	return str(names.get(type, type))


static func _bathroom(doc: Document, rules: Rules, out: Array[Issue]) -> void:
	var rule: Dictionary = rules.bathroom()
	var radius: int = rule["radius_mm"]
	if radius < 0:
		out.append(_unconfigured("bathroom"))
		return
	var keywords: Array = rule["keywords"]
	for sheet_id: String in doc.plan_ids():
		var sheet: Sheet = doc.get_sheet(sheet_id)
		for entity_id: String in sheet.sorted_entity_ids():
			var room: Entity = sheet.entities[entity_id]
			if room.type != "text" or room.props["role"] != "room" or not _matches(str(room.props["text"]), keywords):
				continue
			var at: Vector2 = EntityGeometry.vec(room.props["pos"])
			var near: Array[String] = []
			for other_id: String in sheet.sorted_entity_ids():
				var other: Entity = sheet.entities[other_id]
				if other.type == "symbol" and EntityGeometry.vec(other.props["pos"]).distance_to(at) <= float(radius):
					near.append(other_id)
			if not near.is_empty():
				out.append(_make("bathroom", Issue.WARNING, "« %s » : %s" % [str(room.props["text"]), str(rule["message"])], sheet_id, near, "", "", near))


static func _matches(text: String, keywords: Array) -> bool:
	var lowered: String = text.to_lower()
	for keyword: Variant in keywords:
		if lowered.contains(str(keyword).to_lower()):
			return true
	return false


static func _outside_page(doc: Document, out: Array[Issue]) -> void:
	for sheet_id: String in doc.plan_ids():
		var sheet: Sheet = doc.get_sheet(sheet_id)
		var ctx: RenderContext = RenderContext.for_sheet(doc, sheet)
		var page: Rect2 = FrameBuilder.page_rect(sheet)
		var outside: Array[String] = []
		for entity_id: String in sheet.sorted_entity_ids():
			var entity: Entity = sheet.entities[entity_id]
			if not page.encloses(EntityGeometry.bounds(entity, ctx)):
				outside.append(entity_id)
		if not outside.is_empty():
			out.append(_make("outside_page", Issue.WARNING, "%d élément(s) hors de la page sur « %s »" % [outside.size(), sheet.display_name()], sheet_id, outside, "", "", outside))


static func _layout_warnings(doc: Document, uni: Sheet, model: UniModel) -> Array[String]:
	if uni == null:
		return []
	return UnifilaireLayout.compute(doc, uni, model).warnings


# --- building issues -------------------------------------------------------------------------------


static func _unconfigured(rule_id: String) -> Issue:
	return _make("rule_unconfigured", Issue.WARNING, "Règle non configurée : %s (à renseigner dans rules.json)" % rule_id, "", [], "", "", rule_id)


static func _make(rule: String, severity: String, message: String, sheet_id: String, ids: Array[String], circuit: String, head_id: String, data: Variant) -> Issue:
	var issue: Issue = Issue.new()
	issue.rule = rule
	issue.severity = severity
	issue.message = message
	issue.sheet_id = sheet_id
	issue.entity_ids = ids.duplicate()
	issue.circuit = circuit
	issue.head_id = head_id
	var subjects: Array[String] = ids.duplicate()
	subjects.sort()
	var fingerprint: String = "%s|%s|%s|%s|%s" % [rule, ",".join(PackedStringArray(subjects)), circuit, head_id, str(data)]
	issue.key = "%s:%s" % [rule, fingerprint.sha256_text().substr(0, 12)]
	return issue


static func _before(a: Issue, b: Issue) -> bool:
	if a.is_error() != b.is_error():
		return a.is_error()
	var ra: int = RULE_ORDER.find(a.rule)
	var rb: int = RULE_ORDER.find(b.rule)
	if ra != rb:
		return ra < rb
	return a.key < b.key
