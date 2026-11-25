class_name CosmosQuest
extends Node
## The main quest as the 3D game carries it (stage 5): its stage and whether
## it's finished, from your save (the quest's own scenes - beacons, the
## Minotaur - are the 2D game's for now), read by the Station Menu's MAIN
## QUESTS and saved back as they were.

var stage := -1
var finished := false
var lore := {}


func load_save_data(d: Dictionary) -> void:
	stage = int(d.get("stage", -1))
	finished = bool(d.get("finished", false))
	lore = {}
	for id in d.get("lore", []):
		lore[id] = true


func get_save_data() -> Dictionary:
	return {"stage": stage, "finished": finished, "lore": lore.keys()}


func current() -> Dictionary:
	if stage < 0 or stage >= QuestData.STAGES.size():
		return {}
	return QuestData.STAGES[stage]


func chapter_title() -> String:
	var s := current()
	return QuestData.CHAPTERS[s["chapter"]] if not s.is_empty() else ""


func objective_text() -> String:
	var s := current()
	if finished:
		return "Main quest complete - the archive awaits"
	return str(s.get("objective", "")) if not s.is_empty() else ""
