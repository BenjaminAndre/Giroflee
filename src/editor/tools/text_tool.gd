class_name TextTool
extends Tool
## Places free text. The click only asks the UI for an inline editor (`text_requested`); the
## label is created when the user confirms the text (EditorModel.add_text).


func tool_name() -> String:
	return "text"


func press(model: EditorModel, input: ToolInput) -> void:
	model.text_requested.emit(model.snap(input.world).pos, "", "")


func hint(_model: EditorModel) -> String:
	return "Texte : cliquez pour écrire · Échap = terminer"
