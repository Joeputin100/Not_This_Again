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

# ---------- Task 8: MultiMesh crowd manager ----------

const FlipbookCrowd = preload("res://scripts/flipbook_crowd.gd")

func test_crowd_routes_instance_to_its_clip_mesh():
	var crowd = FlipbookCrowd.new()
	add_child_autofree(crowd)
	crowd.configure("cowboy", ["cowboy_idle_a", "cowboy_run_shoot_fwd"])
	var id = crowd.add_member("cowboy_idle_a")
	assert_eq(crowd.clip_of(id), "cowboy_idle_a")
	crowd.set_member_clip(id, "cowboy_run_shoot_fwd")
	assert_eq(crowd.clip_of(id), "cowboy_run_shoot_fwd")
	assert_eq(crowd.mesh_instance_count("cowboy_idle_a"), 0)
	assert_eq(crowd.mesh_instance_count("cowboy_run_shoot_fwd"), 1)

func test_crowd_add_and_remove_members():
	var crowd = FlipbookCrowd.new()
	add_child_autofree(crowd)
	crowd.configure("cowboy", ["cowboy_idle_a"])
	var ids := []
	for i in 5:
		ids.append(crowd.add_member("cowboy_idle_a"))
	assert_eq(crowd.member_count(), 5)
	assert_eq(crowd.mesh_instance_count("cowboy_idle_a"), 5)
	crowd.remove_member(ids[2])
	assert_eq(crowd.member_count(), 4)
	assert_eq(crowd.mesh_instance_count("cowboy_idle_a"), 4)

func test_crowd_remove_unknown_id_is_noop():
	var crowd = FlipbookCrowd.new()
	add_child_autofree(crowd)
	crowd.configure("cowboy", ["cowboy_idle_a"])
	crowd.add_member("cowboy_idle_a")
	crowd.remove_member(99999)
	assert_eq(crowd.member_count(), 1)
