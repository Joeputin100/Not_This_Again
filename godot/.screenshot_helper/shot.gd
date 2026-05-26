extends Node
# Verification harness — loads a target scene, waits for textures + frames,
# captures the SubViewport's render target if there is one (the SP1 viewer
# wraps its 3D content in /ViewportContainer/Viewport3D), falls back to the
# main viewport's texture, writes PNG, quits. NOT part of the shipped build.

const OUT_PATH := "/tmp/sp1_screenshot.png"
# Wall-clock wait so software-rendering (Mesa llvmpipe) frame-rate doesn't
# blow up the timeout. 5s is plenty for SubViewport realize + NoiseTexture2D
# async generate + first crowd MultiMesh render even at sub-2-fps llvmpipe.
const WAIT_SECONDS := 5.0

var _scene_path := "res://scenes/sp1_crowd_viewer.tscn"
var _outpath := OUT_PATH
var _mode := "main"   # "main" (window composite, with UI) | "subviewport" (3D-only)

func _ready() -> void:
	# Allow override via CLI args: --scene <path> --out <png> --mode <main|subviewport>.
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			_scene_path = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			_outpath = args[i + 1]
		elif args[i] == "--mode" and i + 1 < args.size():
			_mode = args[i + 1]
	print("==> loading ", _scene_path, " mode=", _mode)
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		printerr("FAIL: load returned null for ", _scene_path)
		get_tree().quit(2); return
	var instance: Node = packed.instantiate()
	add_child(instance)
	# Use frame-count wait instead of wall-clock — under heavy software-renderer
	# load (800 grass tufts + 20 crowd MultiMesh instances) the SceneTree
	# timer can stall and never fire. 8 process_frames is enough at any fps
	# for NoiseTexture2D + atlas loads + first MultiMesh render to settle.
	for i in 8:
		await get_tree().process_frame
		print("    frame ", i + 1, " ready")
	var img: Image = null
	if _mode == "subviewport":
		var sv: SubViewport = instance.get_node_or_null("ViewportContainer/Viewport3D")
		if sv != null:
			sv.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var tex := sv.get_texture()
			img = tex.get_image() if tex else null
			print("    capturing inner SubViewport ", sv.size, " img=", img)
	if img == null:
		# Main viewport — composites the SubViewport + Background + UI exactly
		# as a sideloaded device renders. This is what the user sees on screen.
		var mv := get_viewport()
		await RenderingServer.frame_post_draw
		img = mv.get_texture().get_image()
		print("    capturing main viewport ", mv.size, " img=", img)
	if img == null:
		printerr("FAIL: viewport returned null Image")
		get_tree().quit(3); return
	var err := img.save_png(_outpath)
	if err != OK:
		printerr("FAIL: save_png error code ", err)
		get_tree().quit(4); return
	print("OK: ", _outpath, " ", img.get_width(), "x", img.get_height())
	get_tree().quit(0)
