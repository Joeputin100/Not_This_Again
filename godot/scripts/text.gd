extends Node

# Text autoload — single point of access for all visible UI strings.
# Iter 31 setup: loads godot/assets/text/<lang>.json and exposes:
#   Text.get("path.to.key")              → returns string
#   Text.get("path.to.array_key.0")      → returns indexed array element
#   Text.format("template_key", {n: 5})  → returns string with {placeholders} filled
#   Text.set_language("es")              → swap loaded language at runtime
#
# Plan-for-localization scaffolding: existing scenes can keep their
# hardcoded text for now and migrate piecemeal. New text (e.g., Pete's
# Yosemite-Sam dialog lines from iter 32) goes straight into en.json.

const DEFAULT_LANGUAGE: String = "en"
const TEXT_DIR: String = "res://assets/text"

var _current_language: String = DEFAULT_LANGUAGE
var _data: Dictionary = {}

func _ready() -> void:
	load_language(DEFAULT_LANGUAGE)

func load_language(lang: String) -> bool:
	var path := "%s/%s.json" % [TEXT_DIR, lang]
	if not FileAccess.file_exists(path):
		push_warning("Text: language file missing: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Text: failed to open %s" % path)
		return false
	var content: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		push_warning("Text: failed to parse %s as JSON dict" % path)
		return false
	_data = parsed as Dictionary
	_current_language = lang
	return true

func set_language(lang: String) -> bool:
	return load_language(lang)

# Look up a dotted key path. Numeric segments index into arrays.
# Returns "" if the path doesn't resolve — caller is responsible for
# handling fallback display (keeps UI alive if a key is mid-rename).
func get(key_path: String) -> String:
	var parts: PackedStringArray = key_path.split(".")
	var node: Variant = _data
	for part in parts:
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		elif node is Array:
			var idx: int = part.to_int()
			if idx >= 0 and idx < (node as Array).size():
				node = (node as Array)[idx]
			else:
				return ""
		else:
			return ""
	if node is String:
		return node as String
	# If the resolved node is a non-string (Array or Dict), the caller
	# probably wanted a child path. Return empty rather than misleading
	# str(node) output.
	return ""

# Convenience: pick a random element from an array-valued key. Returns
# "" if the key isn't an array or is empty. Iter 32 will use this for
# Pete's varied taunt selection.
func random(array_key_path: String) -> String:
	var parts: PackedStringArray = array_key_path.split(".")
	var node: Variant = _data
	for part in parts:
		if node is Dictionary and (node as Dictionary).has(part):
			node = (node as Dictionary)[part]
		else:
			return ""
	if not (node is Array) or (node as Array).is_empty():
		return ""
	var arr: Array = node as Array
	return str(arr[randi() % arr.size()])

# Template substitution: {placeholder} → vars[placeholder]. Numeric
# values are stringified via str().
func format(key_path: String, vars: Dictionary) -> String:
	var tmpl: String = get(key_path)
	if tmpl.is_empty():
		return ""
	for k in vars:
		tmpl = tmpl.replace("{%s}" % str(k), str(vars[k]))
	return tmpl
