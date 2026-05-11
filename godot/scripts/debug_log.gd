extends Node

# Autoloaded singleton — in-memory ring buffer of recent log lines.
# Used by the main menu's COPY button so you can paste both the build
# identifier AND the running event log into a bug report.
#
# Also mirrors every line to print(), which goes to logcat on Android
# (useful if you have adb access).

const MAX_LINES: int = 100

var _lines: Array[String] = []

# Add a line with a timestamp prefix. Old lines drop off when we
# exceed MAX_LINES so we don't grow unbounded.
func add(msg: String) -> void:
	var ts: String = Time.get_time_string_from_system()
	var line: String = "[%s] %s" % [ts, msg]
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	print(line)

func clear() -> void:
	_lines.clear()

# Newline-joined dump of the current buffer. Suitable to append to
# clipboard content or paste into a bug report.
func get_text() -> String:
	return "\n".join(_lines)

func line_count() -> int:
	return _lines.size()
