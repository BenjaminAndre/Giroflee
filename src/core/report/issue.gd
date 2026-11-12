class_name Issue
extends RefCounted
## One line of the report (SRD section 9). Data only; `ReportBuilder` makes them.

const ERROR: String = "error"
const WARNING: String = "warning"

## Rule id, e.g. "control_without_consumer".
var rule: String = ""
var severity: String = WARNING
## French message.
var message: String = ""
## Where to look: an étage (plan or unifilaire), the symbols on it, a circuit column, a head item.
var sheet_id: String = ""
var entity_ids: Array[String] = []
var circuit: String = ""
var head_id: String = ""
## Rule id + subjects + hash of the data the message is about (FR-RPT-7): it changes when that data does.
var key: String = ""
var acknowledged: bool = false


func is_error() -> bool:
	return severity == ERROR


func to_dict() -> Dictionary:
	return {
		"rule": rule, "severity": severity, "message": message, "sheet": sheet_id,
		"symbols": entity_ids.duplicate(), "circuit": circuit, "head": head_id,
		"key": key, "acknowledged": acknowledged,
	}
