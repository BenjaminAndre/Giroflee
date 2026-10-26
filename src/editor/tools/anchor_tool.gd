class_name AnchorTool
extends Tool
## "Ancrer à un symbole" (SRD FR-STACK-2): with symbols selected, one click on another symbol anchors
## the selection to it, making a stack that moves as one. The tool ends after the click; Escape
## abandons it. Cycles are refused by the command.


func tool_name() -> String:
	return "anchor"


func press(model: EditorModel, input: ToolInput) -> void:
	var excluded: Array = model.focus_excluded()
	excluded.append_array(model.selection)
	var picked: String = HitTest.pick(model.sheet(), model.ctx(), input.world, input.tolerance, excluded, model.spatial())
	if picked.is_empty() or model.sheet().entities[picked].type != "symbol":
		model.notice.emit("Cliquez sur le symbole auquel ancrer la sélection")
		return
	var result: CommandResult = model.anchor_selection_to(picked)
	if result.ok:
		model.set_tool("select")


func hint(_model: EditorModel) -> String:
	return "Ancrer : cliquez sur le symbole parent · Échap = annuler"
