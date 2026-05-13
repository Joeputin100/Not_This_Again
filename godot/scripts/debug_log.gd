extends Node

# Autoloaded singleton — in-memory ring buffer of recent log lines.
# Used by the main menu's COPY button so you can paste both the build
# identifier AND the running event log into a bug report.
#
# Also mirrors every line to print(), which goes to logcat on Android
# (useful if you have adb access).
#
# Iter 93: each add() also appends to user://debug.log on disk so
# breadcrumbs from a crashed/frozen session survive a force-quit. The
# next app launch reads + prepends the previous session's tail so the
# COPY action shows last-session-FROZEN-here followed by this-session
# logs. Critical for diagnosing the iter 92 3D-preview freeze where
# the in-memory log was lost when the user force-quit.

const MAX_LINES: int = 100
const LOG_PATH: String = "user://debug.log"
# Tail of previous session preserved at boot. Bounded so a multi-MB
# file doesn't pin memory.
const PREVIOUS_SESSION_TAIL_LINES: int = 60

var _lines: Array[String] = []
# Header line marking the current session boundary in the persisted
# file. Helps the user see 'session N' vs 'session N+1' divisions
# when reading the COPY output.
var _session_header_written: bool = false

func _ready() -> void:
	# Iter 93: at boot, append a session-header marker to the on-disk
	# log + load the most recent PREVIOUS_SESSION_TAIL_LINES into memory
	# so the COPY action shows them. Then keep appending live entries.
	_load_previous_session_tail()
	_write_session_header()

# Add a line with a timestamp prefix. Old lines drop off when we
# exceed MAX_LINES so we don't grow unbounded.
func add(msg: String) -> void:
	var ts: String = Time.get_time_string_from_system()
	var line: String = "[%s] %s" % [ts, msg]
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	print(line)
	# Iter 93: persist to disk so a freeze/force-quit doesn't lose it.
	_append_to_disk(line)

func clear() -> void:
	_lines.clear()

# Newline-joined dump of the current buffer. Suitable to append to
# clipboard content or paste into a bug report.
func get_text() -> String:
	return "\n".join(_lines)

func line_count() -> int:
	return _lines.size()

# Iter 93: append a single line to user://debug.log. Open in APPEND
# mode each call — slower than holding an open handle but resilient
# to crashes (flushes per call). Truncates the file if it gets larger
# than 256KB so we don't grow unbounded across many sessions.
const MAX_LOG_BYTES: int = 262144
func _append_to_disk(line: String) -> void:
	# Iter 93: standalone test instances (autofree(.new())) aren't in
	# the scene tree. Skip disk writes for them — only the autoload
	# at /root/DebugLog persists.
	if not is_inside_tree():
		return
	# If file is huge, rotate by keeping the tail.
	if FileAccess.file_exists(LOG_PATH):
		var size: int = FileAccess.get_file_as_bytes(LOG_PATH).size()
		if size > MAX_LOG_BYTES:
			_rotate_log()
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		# File doesn't exist yet — create it.
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()

# Rotate: keep the last half of the file, drop the older half.
func _rotate_log() -> void:
	var content: String = FileAccess.get_file_as_string(LOG_PATH)
	var lines: PackedStringArray = content.split("\n")
	var keep_from: int = lines.size() / 2
	var tail: PackedStringArray = lines.slice(keep_from)
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	for line in tail:
		f.store_line(line)
	f.close()

# Iter 93: read previous session's tail at boot, prepend to in-memory.
# Stops at PREVIOUS_SESSION_TAIL_LINES so we don't bloat _lines.
func _load_previous_session_tail() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var content: String = FileAccess.get_file_as_string(LOG_PATH)
	var all_lines: PackedStringArray = content.split("\n")
	# Drop trailing empty line if present
	if all_lines.size() > 0 and all_lines[all_lines.size() - 1] == "":
		all_lines.remove_at(all_lines.size() - 1)
	var start: int = maxi(0, all_lines.size() - PREVIOUS_SESSION_TAIL_LINES)
	for i in range(start, all_lines.size()):
		_lines.append(all_lines[i])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)

# Iter 93: marker line at session start so the COPY output is readable.
func _write_session_header() -> void:
	if _session_header_written:
		return
	_session_header_written = true
	var dt: String = Time.get_datetime_string_from_system()
	var hdr: String = "──── new session @ %s ────" % dt
	_lines.append(hdr)
	_append_to_disk(hdr)
