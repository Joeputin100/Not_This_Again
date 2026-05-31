extends Node

# Offline bake harness: render the seascape_bake canvas_item shader to a PNG
# sequence by stepping its u_time uniform. Run headless via Xvfb + Godot:
#   DISPLAY=:99 godot --path godot --rendering-driver opengl3 res://.shader_render/render.tscn
# Frames -> godot/.shader_render/frames/sea_NNN.png (then assembled + looped in Python).

const W := 256
const N := 72       # render frames (Python crossfades these into a ~48-frame seamless loop)
const DT := 0.13    # wave-time step per frame

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://.shader_render/frames")
	var sv := SubViewport.new()
	sv.size = Vector2i(W, W)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	add_child(sv)
	var cr := ColorRect.new()
	cr.size = Vector2(W, W)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://.shader_render/seascape_bake.gdshader")
	mat.set_shader_parameter("u_res", Vector2(W, W))
	cr.material = mat
	sv.add_child(cr)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for i in N:
		mat.set_shader_parameter("u_time", float(i) * DT)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		img.save_png("res://.shader_render/frames/sea_%03d.png" % i)
		print("==> frame ", i)
	print("==> BAKE DONE ", N)
	get_tree().quit()
