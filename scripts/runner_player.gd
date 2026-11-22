extends CharacterBody3D

const LANES := [-2.5, 0.0, 2.5]
const LANE_SPEED := 15.0
const GRAVITY := 24.0
const JUMP_VELOCITY := 9.0
const ROBBER_PATH := "res://models/robber.glb"

var lane := 1
var active := false
var sliding := false
var slide_left := 0.0
var touch_start := Vector2.ZERO
var touch_down := false
var collider: CollisionShape3D
var capsule: CapsuleShape3D
var robber_model: Node3D

func _ready() -> void:
	name = "Player"
	robber_model = _load_glb(ROBBER_PATH)
	robber_model.rotation.y = PI
	add_child(robber_model)
	collider = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	position = Vector3(0, 0, 0)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if slide_left > 0.0:
		slide_left -= delta
		if slide_left <= 0.0:
			_end_slide()
	velocity.x = move_toward(velocity.x, (LANES[lane] - position.x) * LANE_SPEED, LANE_SPEED * 3.0 * delta)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A, KEY_LEFT:
				_change_lane(-1)
			KEY_D, KEY_RIGHT:
				_change_lane(1)
			KEY_W, KEY_SPACE, KEY_UP:
				_jump()
			KEY_S, KEY_DOWN:
				_start_slide()
	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
			touch_down = true
		elif touch_down:
			touch_down = false
			_handle_swipe(event.position - touch_start)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			touch_start = event.position
			touch_down = true
		elif touch_down:
			touch_down = false
			_handle_swipe(event.position - touch_start)

func _handle_swipe(delta: Vector2) -> void:
	if delta.length() < 45.0:
		return
	if absf(delta.x) > absf(delta.y):
		_change_lane(1 if delta.x > 0.0 else -1)
	elif delta.y < 0.0:
		_jump()
	else:
		_start_slide()

func _change_lane(direction: int) -> void:
	lane = clampi(lane + direction, 0, 2)

func _jump() -> void:
	if is_on_floor() and not sliding:
		velocity.y = JUMP_VELOCITY

func _start_slide() -> void:
	if sliding or not is_on_floor():
		return
	sliding = true
	slide_left = 0.85
	capsule.height = 0.95
	collider.position.y = 0.48
	robber_model.scale.y = 0.52

func _end_slide() -> void:
	sliding = false
	capsule.height = 1.8
	collider.position.y = 0.9
	if robber_model != null:
		robber_model.scale = Vector3.ONE

func reset_runner() -> void:
	lane = 1
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	_end_slide()
	active = true

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material

func _load_glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result: Error = document.append_from_file(path, state)
	assert(result == OK, "Unable to load model %s: %s" % [path, error_string(result)])
	var imported_root := document.generate_scene(state) as Node3D
	assert(imported_root != null, "GLB root is not Node3D: %s" % path)
	return imported_root
