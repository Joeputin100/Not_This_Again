extends GutTest

const FlipbookPlayer = preload("res://scripts/flipbook_player.gd")

# ---------- Task 7: single-character flipbook player ----------

func test_set_clip_updates_material_params():
	var p = FlipbookPlayer.new()
	add_child_autofree(p)
	p.set_clip("cowboy_idle_a")
	var mat: ShaderMaterial = p.get_active_material(0)
	assert_eq(mat.get_shader_parameter("cols"), 10, "cols from atlas json")
	assert_eq(mat.get_shader_parameter("frame_count"), 96)

func test_set_clip_remembers_current_clip():
	var p = FlipbookPlayer.new()
	add_child_autofree(p)
	p.set_clip("cowboy_idle_a")
	assert_eq(p.get_clip(), "cowboy_idle_a")
	p.set_clip("cowboy_run_shoot_fwd")
	assert_eq(p.get_clip(), "cowboy_run_shoot_fwd")

func test_set_clip_idempotent():
	# Calling set_clip with the same name twice should not rebuild material.
	var p = FlipbookPlayer.new()
	add_child_autofree(p)
	p.set_clip("cowboy_idle_a")
	var mat_before: ShaderMaterial = p.get_active_material(0)
	p.set_clip("cowboy_idle_a")
	var mat_after: ShaderMaterial = p.get_active_material(0)
	assert_eq(mat_before, mat_after, "same material instance after no-op set_clip")
