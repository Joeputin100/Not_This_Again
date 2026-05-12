extends GutTest

const DebugLogScript = preload("res://scripts/debug_log.gd")

var log: Node

func before_each():
	log = autofree(DebugLogScript.new())

func test_starts_empty():
	assert_eq(log.line_count(), 0)
	assert_eq(log.get_text(), "")

func test_add_increments_line_count():
	log.add("hello")
	assert_eq(log.line_count(), 1)

func test_add_two_lines():
	log.add("a")
	log.add("b")
	assert_eq(log.line_count(), 2)

func test_get_text_contains_message():
	log.add("greetings stranger")
	assert_true("greetings stranger" in log.get_text(),
		"message should appear in log text")

func test_get_text_includes_timestamp_prefix():
	log.add("msg")
	# Timestamp format is HH:MM:SS, so the line starts with "[" and has ":"
	var text: String = log.get_text()
	assert_true(text.begins_with("["), "log line should start with [")
	assert_true(":" in text, "timestamp should contain colons")

func test_get_text_joins_with_newlines():
	log.add("first")
	log.add("second")
	var text: String = log.get_text()
	assert_true("first" in text)
	assert_true("second" in text)
	assert_true("\n" in text, "lines should be newline-joined")

func test_clear_empties_buffer():
	log.add("a")
	log.add("b")
	log.clear()
	assert_eq(log.line_count(), 0)
	assert_eq(log.get_text(), "")

func test_caps_at_max_lines():
	for i in DebugLogScript.MAX_LINES + 20:
		log.add("line " + str(i))
	assert_eq(log.line_count(), DebugLogScript.MAX_LINES,
		"buffer should cap at MAX_LINES")

func test_oldest_dropped_on_overflow():
	log.add("DROPPED_LINE")
	for i in DebugLogScript.MAX_LINES:
		log.add("kept " + str(i))
	var text: String = log.get_text()
	assert_false("DROPPED_LINE" in text,
		"oldest line should fall off the end")
	assert_true("kept 0" in text,
		"the first 'kept' line should still be in the buffer")

func test_exactly_max_lines_keeps_all():
	# At exactly MAX_LINES, nothing should be dropped.
	for i in DebugLogScript.MAX_LINES:
		log.add("k" + str(i))
	assert_eq(log.line_count(), DebugLogScript.MAX_LINES)
	assert_true("k0" in log.get_text(), "first line should remain")
