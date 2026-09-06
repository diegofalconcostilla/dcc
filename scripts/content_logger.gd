class_name ContentLogger
extends RefCounted

## Append-only JSONL logger for every LLM-generated loot/achievement event
## (and the fallback used when the LLM call fails or fails validation), so
## sessions can be replayed later to judge content quality. One file per
## process run under res://logs/, named by the run's start time.

static var _log_path := ""

static func _ensure_path() -> String:
	if _log_path != "":
		return _log_path
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("logs"):
		dir.make_dir("logs")
	_log_path = "res://logs/session_%d.jsonl" % Time.get_unix_time_from_system()
	return _log_path

## event should describe one content-generation decision, e.g.:
## {"kind": "loot", "tier": ..., "context": {...}, "prompt": ..., "raw_response": ..., "source": ..., "result": {...}}
static func log_event(event: Dictionary) -> void:
	var path := _ensure_path()
	var file: FileAccess
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		file.seek_end()
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[ContentLogger] could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	var entry := event.duplicate()
	entry["timestamp"] = Time.get_datetime_string_from_system(true)
	file.store_line(JSON.stringify(entry))
	file.close()
