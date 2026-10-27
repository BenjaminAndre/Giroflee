class_name UniModel
extends RefCounted
## The unifilaire derived from the plans and the board (SRD section 8): circuits as columns, their
## points as rows, the bus and the head chain. Pure data, no drawing; `UnifilaireBuilder` makes it and
## `UnifilaireLayout` places it on the page.


## Consecutive symbols of one type in a point, collapsed (a triple socket, two lamps on one switch).
class Item:
	extends RefCounted
	var type: String = ""
	var role: String = "consumer"
	## Sum of the `count` of the symbols collapsed here.
	var count: int = 1
	var ids: Array[String] = []

	func to_dict() -> Dictionary:
		return {"type": type, "role": role, "count": count, "ids": ids.duplicate()}


## All symbols of one circuit sharing one index, on any étage.
class Point:
	extends RefCounted
	var index: int = 0
	var items: Array[Item] = []
	var has_control: bool = false
	var has_consumer: bool = false
	## Symbol ids (sorted); the first one is where a click jumps to.
	var symbol_ids: Array[String] = []

	## A control with nothing to command: drawn with `?` (SRD FR-UNI-4).
	func is_open() -> bool:
		return has_control and not has_consumer

	func to_dict() -> Dictionary:
		var list: Array = []
		for item: Item in items:
			list.append(item.to_dict())
		return {"index": index, "items": list, "open": is_open(), "symbols": symbol_ids.duplicate()}


class Column:
	extends RefCounted
	var letter: String = ""
	var title: String = ""
	## The title was proposed from nearby room labels rather than typed.
	var title_proposed: bool = false
	var breaker: String = ""
	var cable: String = ""
	var breaker_defaulted: bool = true
	var cable_defaulted: bool = true
	## Index -> Point.
	var points: Dictionary = {}
	## No symbol at all: a spare circuit (SRD 8.2).
	var spare: bool = true
	## Listed in `board.bus` (otherwise it was appended because it is in use).
	var in_bus: bool = false

	func highest_index() -> int:
		var highest: int = 0
		for key: Variant in points.keys():
			var index: int = key
			highest = maxi(highest, index)
		return highest

	func sorted_points() -> Array[Point]:
		var keys: Array = points.keys()
		keys.sort()
		var out: Array[Point] = []
		for key: Variant in keys:
			var point: Point = points[key]
			out.append(point)
		return out

	func to_dict() -> Dictionary:
		var list: Array = []
		for point: Point in sorted_points():
			list.append(point.to_dict())
		return {
			"letter": letter, "title": title, "title_proposed": title_proposed,
			"breaker": breaker, "cable": cable,
			"breaker_defaulted": breaker_defaulted, "cable_defaulted": cable_defaulted,
			"spare": spare, "in_bus": in_bus, "points": list,
		}


## One place along the bus: a circuit column or a device.
class BusItem:
	extends RefCounted
	var is_device: bool = false
	## Column index, for a circuit.
	var column: int = -1
	## Device uuid and catalogue id.
	var id: String = ""
	var catalog: String = ""

	func to_dict() -> Dictionary:
		if is_device:
			return {"type": "device", "id": id, "catalog": catalog}
		return {"type": "circuit", "column": column}


var columns: Array[Column] = []
var bus: Array[BusItem] = []
## Head chain, from the feed to the bus: [{"id", "catalog"}].
var head: Array[Dictionary] = []
## Rows of the ruler: the larger of the pack minimum and the highest index in use (never capped).
var rows: int = 8
var warnings: Array[String] = []


func column_for(letter: String) -> Column:
	for column: Column in columns:
		if column.letter == letter:
			return column
	return null


func to_dict() -> Dictionary:
	var column_list: Array = []
	for column: Column in columns:
		column_list.append(column.to_dict())
	var bus_list: Array = []
	for item: BusItem in bus:
		bus_list.append(item.to_dict())
	return {"columns": column_list, "bus": bus_list, "head": head.duplicate(true), "rows": rows, "warnings": warnings.duplicate()}
