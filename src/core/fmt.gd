class_name Fmt
extends RefCounted
## Text formatting for readouts, in French conventions (decimal comma).


## "3,45 m" for lengths of a metre or more, "850 mm" below.
static func length(mm: float) -> String:
	var abs_mm: float = absf(mm)
	if abs_mm >= 1000.0:
		return ("%.2f m" % (mm / 1000.0)).replace(".", ",")
	return "%d mm" % roundi(mm)
