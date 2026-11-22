extends Node3D

const PlayerScript = preload("res://scripts/runner_player.gd")
const CASH_PATH := "res://models/cash_stack.glb"
const BARRIER_PATH := "res://models/low_barrier.glb"
const GATE_PATH := "res://models/high_gate.glb"
const LANES := [-2.5, 0.0, 2.5]
const SEGMENT_LENGTH := 36.0

var player: CharacterBody3D
var camera: Camera3D
var road_segments: Array[Node3D] = []
var actors: Array[Node3D] = []
var ui_layer: CanvasLayer
var top_bar: HBoxContainer
var cash_label: Label
var distance_label: Label
var police_label: Label
var overlay: Control
var overlay_title: Label
var overlay_text: Label
var primary_button: Button
var magnet_button: Button
var loot_button: Button
var pause_button: Button
var state := "menu"
var run_cash := 0
var wallet := 0
var run_distance := 0.0
var police_pressure := 0.0
var world_speed := 13.0
var spawn_distance := 12.0
var magnet_time := 0.0
var magnet_upgrade := 0
var loot_upgrade := 0
var save := ConfigFile.new()
var road_material: StandardMaterial3D
var sidewalk_material: StandardMaterial3D
var building_materials: Array[StandardMaterial3D] = []
var cash_prototype: Node3D
var barrier_prototype: Node3D
var gate_prototype: Node3D

func _ready() -> void:
	_load_save()
	cash_prototype = _load_glb(CASH_PATH)
	barrier_prototype = _load_glb(BARRIER_PATH)
	gate_prototype = _load_glb(GATE_PATH)
	_build_world()
	_build_ui()
	_show_menu()

func _process(delta: float) -> void:
	if state != "running":
		return
	world_speed = minf(21.0, 13.0 + run_distance * 0.0007)
	var travel := world_speed * delta
	run_distance += travel
	magnet_time = maxf(0.0, magnet_time - delta)
	for segment in road_segments:
		segment.position.z += travel
		if segment.position.z > 42.0:
			segment.position.z -= SEGMENT_LENGTH * road_segments.size()
	for actor in actors.duplicate():
		actor.position.z += travel
		_process_actor(actor)
		if is_instance_valid(actor) and actor.position.z > 8.0:
			actors.erase(actor)
			actor.queue_free()
	spawn_distance -= travel
	if spawn_distance <= 0.0:
		_spawn_wave()
		spawn_distance = randf_range(19.0, 27.0)
	cash_label.text = "$ %d" % (wallet + run_cash)
	distance_label.text = "%dm" % int(run_distance)
	police_label.text = "РџРћР›РР¦РРЇ  %d%%" % int(police_pressure * 100.0)
	var pursuer: Node3D = get_meta("pursuer")
	pursuer.position.x = move_toward(pursuer.position.x, LANES[player.lane], delta * 4.0)
	if police_pressure >= 1.0:
		_end_run(true)

func _build_world() -> void:
	randomize()
	road_material = _material(Color(0.105, 0.13, 0.17), 0.9)
	sidewalk_material = _material(Color(0.33, 0.36, 0.4), 0.85)
	building_materials = [
		_material(Color(0.2, 0.28, 0.39)),
		_material(Color(0.31, 0.27, 0.32)),
		_material(Color(0.22, 0.35, 0.38)),
		_material(Color(0.39, 0.31, 0.23))
	]
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.055, 0.11, 0.2)
	sky_material.sky_horizon_color = Color(0.55, 0.29, 0.21)
	sky_material.ground_bottom_color = Color(0.08, 0.095, 0.12)
	sky_material.ground_horizon_color = Color(0.32, 0.25, 0.22)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.57, 0.62, 0.78)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -25, 0)
	sun.light_color = Color(1.0, 0.78, 0.58)
	sun.light_energy = 1.2
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.name = "EndlessRoadFloor"
	var floor_shape_node := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8.7, 0.5, 500.0)
	floor_shape_node.shape = floor_shape
	floor_shape_node.position = Vector3(0, -0.3, -120)
	floor_body.add_child(floor_shape_node)
	add_child(floor_body)
	for i in range(6):
		var segment := _create_road_segment()
		segment.position.z = -18.0 - float(i) * SEGMENT_LENGTH
		add_child(segment)
		road_segments.append(segment)
	player = PlayerScript.new()
	player.name = "Runner"
	add_child(player)
	camera = Camera3D.new()
	camera.position = Vector3(0, 5.6, 9.5)
	camera.current = true
	camera.fov = 58.0
	add_child(camera)
	camera.look_at(Vector3(0, 1.7, -8.0), Vector3.UP)
	var pursuer := _make_police_car()
	pursuer.name = "PolicePursuit"
	pursuer.position = Vector3(0, 0, 5.2)
	add_child(pursuer)
	set_meta("pursuer", pursuer)

func _create_road_segment() -> Node3D:
	var segment := Node3D.new()
	var road := _box(segment, Vector3(0, -0.06, 0), Vector3(8.7, 0.12, SEGMENT_LENGTH), road_material, "Road")
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1, 1]:
		var sx := float(side)
		_box(segment, Vector3(sx * 5.3, -0.04, 0), Vector3(1.9, 0.2, SEGMENT_LENGTH), sidewalk_material, "Sidewalk")
	for lane_line in [-1, 1]:
		for dash in range(6):
			_box(segment, Vector3(float(lane_line) * 1.25, 0.015, -15.0 + float(dash) * 6.0), Vector3(0.055, 0.025, 3.2), _material(Color(0.88, 0.76, 0.48)), "LaneMark")
	for side in [-1, 1]:
		for building_index in range(2):
			var width := randf_range(3.2, 5.0)
			var height := randf_range(8.0, 19.0)
			var z := -10.0 + float(building_index) * 19.0
			var x := float(side) * randf_range(8.3, 10.1)
			var building := _box(segment, Vector3(x, height * 0.5 - 0.05, z), Vector3(width, height, 12.0), building_materials.pick_random(), "Building")
			building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			for floor_index in range(1, int(height / 2.5)):
				var window_material := _material(Color(1.0, 0.64, 0.28), 0.35, true)
				var window_x := x - float(side) * (width * 0.5 + 0.015)
				_box(segment, Vector3(window_x, float(floor_index) * 2.5, z - 3.0), Vector3(0.04, 0.72, 0.9), window_material, "Window")
	return segment

func _process_actor(actor: Node3D) -> void:
	if not is_instance_valid(actor) or actor.get_meta("resolved", false):
		return
	var kind: String = actor.get_meta("kind")
	var actor_lane: int = actor.get_meta("lane")
	var lane_match: bool = actor_lane == player.lane and absf(player.position.x - LANES[actor_lane]) < 1.1
	if kind == "money" or kind == "magnet":
		var magnet_collect := kind == "money" and magnet_time > 0.0 and actor.position.z > -10.0
		if actor.position.z >= -0.7 and actor.position.z <= 1.7 and (lane_match or magnet_collect):
			actor.set_meta("resolved", true)
			if kind == "money":
				run_cash += 10 * (1 + loot_upgrade)
			else:
				magnet_time = 8.0 + float(magnet_upgrade) * 4.0
				_run_effect(actor, Color(0.2, 0.85, 1.0))
			actor.queue_free()
			actors.erase(actor)
		return
	if kind == "patrol" and actor.position.z >= -0.45 and actor.position.z <= 1.5 and not lane_match:
		if absf(player.position.x - LANES[actor_lane]) < 2.15:
			actor.set_meta("resolved", true)
			police_pressure = minf(1.0, police_pressure + 0.14)
			actor.queue_free()
			actors.erase(actor)
		return
	if actor.position.z >= -0.45 and actor.position.z <= 1.5 and lane_match:
		actor.set_meta("resolved", true)
		var avoided := false
		if kind == "barricade":
			avoided = player.position.y > 0.52
		elif kind == "gate":
			avoided = player.sliding
		if not avoided:
			if kind == "patrol":
				_end_run(true)
			else:
				police_pressure = minf(1.0, police_pressure + 0.28)
				_run_effect(actor, Color(1.0, 0.28, 0.18))
				if police_pressure >= 1.0:
					_end_run(true)
		actor.queue_free()
		actors.erase(actor)

func _spawn_wave() -> void:
	var obstacle_lane := randi_range(0, 2)
	var kind: String = ["barricade", "gate", "patrol"].pick_random()
	_spawn_actor(kind, obstacle_lane, -78.0)
	var cash_lane := randi_range(0, 2)
	for i in range(4):
		_spawn_actor("money", cash_lane, -84.0 - float(i) * 2.2)
	if randf() < 0.11:
		_spawn_actor("magnet", randi_range(0, 2), -94.0)

func _spawn_actor(kind: String, lane_index: int, z: float) -> void:
	var actor := Node3D.new()
	actor.name = kind.capitalize()
	actor.position = Vector3(LANES[lane_index], 0, z)
	actor.set_meta("kind", kind)
	actor.set_meta("lane", lane_index)
	actor.set_meta("resolved", false)
	match kind:
		"barricade":
			actor.add_child(barrier_prototype.duplicate())
		"gate":
			actor.add_child(gate_prototype.duplicate())
		"patrol":
			var car := _make_police_car()
			actor.add_child(car)
		"money":
			actor.add_child(cash_prototype.duplicate())
		"magnet":
			_box(actor, Vector3(0, 0.95, 0), Vector3(0.65, 0.8, 0.25), _material(Color(0.18, 0.76, 1.0), 0.25, true), "Magnet")
	add_child(actor)
	actors.append(actor)

func _make_police_car() -> Node3D:
	var car := Node3D.new()
	_box(car, Vector3(0, 0.58, 0), Vector3(1.9, 0.85, 3.0), _material(Color(0.12, 0.2, 0.32)), "CarBody")
	_box(car, Vector3(0, 1.12, -0.18), Vector3(1.36, 0.5, 1.28), _material(Color(0.28, 0.58, 0.77)), "Windshield")
	_box(car, Vector3(-0.42, 1.42, -0.15), Vector3(0.42, 0.16, 0.2), _material(Color(0.25, 0.55, 1.0), 0.2, true), "BlueLight")
	_box(car, Vector3(0.42, 1.42, -0.15), Vector3(0.42, 0.16, 0.2), _material(Color(1.0, 0.18, 0.16), 0.2, true), "RedLight")
	for wx in [-0.86, 0.86]:
		for wz in [-0.95, 0.95]:
			_box(car, Vector3(wx, 0.25, wz), Vector3(0.18, 0.42, 0.5), _material(Color(0.035, 0.045, 0.06)), "Wheel")
	return car

func _run_effect(_actor: Node3D, _color: Color) -> void:
	police_pressure = minf(1.0, police_pressure + 0.0)

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(root)
	top_bar = HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 28
	top_bar.offset_top = 34
	top_bar.offset_right = -28
	top_bar.add_theme_constant_override("separation", 18)
	root.add_child(top_bar)
	cash_label = _label("$ 0", 29, Color(0.57, 1.0, 0.74))
	distance_label = _label("0m", 27, Color.WHITE)
	police_label = _label("РџРћР›РР¦РРЇ  0%", 20, Color(1.0, 0.53, 0.39))
	cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	distance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	police_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(cash_label)
	top_bar.add_child(distance_label)
	top_bar.add_child(police_label)
	pause_button = _button("в…Ў", 24)
	pause_button.custom_minimum_size = Vector2(70, 64)
	pause_button.pressed.connect(_toggle_pause)
	top_bar.add_child(pause_button)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.05, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.09, 0.14, 0.98)
	style.border_color = Color(0.18, 0.72, 0.78, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(26)
	style.content_margin_left = 44
	style.content_margin_right = 44
	style.content_margin_top = 42
	style.content_margin_bottom = 42
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	panel.add_child(stack)
	overlay_title = _label("NIGHT RUN", 50, Color(0.95, 0.75, 0.35))
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(overlay_title)
	overlay_text = _label("РЎРѕСЂРІРё РєСѓС€ Рё СѓС…РѕРґРё РѕС‚ РїРѕРіРѕРЅРё", 22, Color(0.78, 0.86, 0.94))
	overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(overlay_text)
	primary_button = _button("РР“Р РђРўР¬", 28)
	primary_button.pressed.connect(_on_primary_pressed)
	stack.add_child(primary_button)
	magnet_button = _button("РњРђР“РќРРў  вЂў  50", 20)
	magnet_button.pressed.connect(_buy_magnet)
	stack.add_child(magnet_button)
	loot_button = _button("РњРќРћР–РРўР•Р›Р¬ Р”РћР‘Р«Р§Р  вЂў  100", 20)
	loot_button.pressed.connect(_buy_loot)
	stack.add_child(loot_button)
	var controls := _label("РЎРІР°Р№Рї в†ђ в†’: РїРѕР»РѕСЃР°     в†‘ / РџР РћР‘Р•Р›: РїСЂС‹Р¶РѕРє     в†“ / S: РїРѕРґРєР°С‚", 17, Color(0.58, 0.69, 0.79))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(controls)
	_update_upgrade_text()

func _show_menu() -> void:
	state = "menu"
	player.active = false
	top_bar.visible = false
	overlay.visible = true
	overlay_title.text = "NIGHT RUN"
	overlay_text.text = "РЎРѕСЂРІРё РєСѓС€ Рё СѓС…РѕРґРё РѕС‚ РїРѕРіРѕРЅРё\nР‘Р°Р»Р°РЅСЃ: $%d" % wallet
	primary_button.text = "РР“Р РђРўР¬"
	_update_upgrade_text()

func _start_run() -> void:
	state = "running"
	run_cash = 0
	run_distance = 0.0
	police_pressure = 0.0
	magnet_time = 0.0
	spawn_distance = 14.0
	for actor in actors:
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()
	player.reset_runner()
	top_bar.visible = true
	overlay.visible = false

func _end_run(arrested: bool) -> void:
	if state != "running":
		return
	state = "over"
	player.active = false
	wallet += run_cash
	_save_progress()
	top_bar.visible = false
	overlay.visible = true
	overlay_title.text = "РђР Р•РЎРў" if arrested else "РџРћР“РћРќРЇ"
	overlay_text.text = "Р”РёСЃС‚Р°РЅС†РёСЏ: %d Рј\nР”РѕР±С‹С‡Р°: $%d\nР‘Р°Р»Р°РЅСЃ: $%d" % [int(run_distance), run_cash, wallet]
	primary_button.text = "Р•Р©РЃ Р РђР—"
	_update_upgrade_text()

func _toggle_pause() -> void:
	if state == "running":
		state = "paused"
		player.active = false
		overlay.visible = true
		overlay_title.text = "РџРђРЈР—Рђ"
		overlay_text.text = "РџРµСЂРµРґС‹С€РєР° РІ РїРѕРіРѕРЅРµ"
		primary_button.text = "РџР РћР”РћР›Р–РРўР¬"
	elif state == "paused":
		_resume_run()

func _on_primary_pressed() -> void:
	if state == "paused":
		_resume_run()
	else:
		_start_run()

func _resume_run() -> void:
	state = "running"
	player.active = true
	overlay.visible = false

func _buy_magnet() -> void:
	var price := 50 + magnet_upgrade * 50
	if wallet < price:
		overlay_text.text = "РќРµ С…РІР°С‚Р°РµС‚ $%d. Р‘Р°Р»Р°РЅСЃ: $%d" % [price - wallet, wallet]
		return
	wallet -= price
	magnet_upgrade += 1
	_save_progress()
	_update_upgrade_text()
	if state == "menu":
		overlay_text.text = "РЈР»СѓС‡С€РµРЅРёРµ РєСѓРїР»РµРЅРѕ! Р‘Р°Р»Р°РЅСЃ: $%d" % wallet

func _buy_loot() -> void:
	var price := 100 + loot_upgrade * 100
	if wallet < price:
		overlay_text.text = "РќРµ С…РІР°С‚Р°РµС‚ $%d. Р‘Р°Р»Р°РЅСЃ: $%d" % [price - wallet, wallet]
		return
	wallet -= price
	loot_upgrade += 1
	_save_progress()
	_update_upgrade_text()
	if state == "menu":
		overlay_text.text = "РЈР»СѓС‡С€РµРЅРёРµ РєСѓРїР»РµРЅРѕ! Р‘Р°Р»Р°РЅСЃ: $%d" % wallet

func _update_upgrade_text() -> void:
	if magnet_button != null:
		magnet_button.text = "РњРђР“РќРРў %dСЃ  вЂў  $%d" % [8 + magnet_upgrade * 4, 50 + magnet_upgrade * 50]
		loot_button.text = "РњРќРћР–РРўР•Р›Р¬ x%d  вЂў  $%d" % [1 + loot_upgrade, 100 + loot_upgrade * 100]

func _load_save() -> void:
	if save.load("user://save.cfg") == OK:
		wallet = int(save.get_value("progress", "wallet", 0))
		magnet_upgrade = int(save.get_value("upgrades", "magnet", 0))
		loot_upgrade = int(save.get_value("upgrades", "loot", 0))

func _save_progress() -> void:
	save.set_value("progress", "wallet", wallet)
	save.set_value("upgrades", "magnet", magnet_upgrade)
	save.set_value("upgrades", "loot", loot_upgrade)
	var err := save.save("user://save.cfg")
	if err != OK:
		push_error("Unable to save progress: %s" % error_string(err))

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = material
	instance.name = node_name
	parent.add_child(instance)
	return instance

func _material(color: Color, roughness := 0.75, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.65
	return material

func _load_glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var result: Error = document.append_from_file(path, gltf_state)
	assert(result == OK, "Unable to load model %s: %s" % [path, error_string(result)])
	var imported_root := document.generate_scene(gltf_state) as Node3D
	assert(imported_root != null, "GLB root is not Node3D: %s" % path)
	return imported_root

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 72)
	button.add_theme_font_size_override("font_size", font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.42, 0.49)
	normal.set_corner_radius_all(14)
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.56, 0.62)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button
