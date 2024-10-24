extends CharacterBody3D

# Movement
@export var MAX_VELOCITY_AIR = 0.6 # Air control
@export var MAX_VELOCITY_GROUND = 6.0
var MAX_ACCELERATION = 10 * MAX_VELOCITY_GROUND
@export var GRAVITY = 28.0 #15.34
@export var STOP_SPEED = 1.5 #1.5
var JUMP_IMPULSE = sqrt(2 * GRAVITY * 2.0) #sqrt(2 * GRAVITY * 0.85)
@export var PLAYER_WALKING_MULTIPLIER = 0.666
@export var MOUSE_SENSITIVITY : float = 0.075

@export_range(5, 10, 0.1) var CROUCH_SPEED : float = 2.2 # 5.0
@export var TOGGLE_CROUCH : bool = true

@export var ANIMATIONPLAYER : AnimationPlayer
@export var CROUCH_SHAPECAST : Node3D

var direction = Vector3()
var friction = 6 #4
var wish_jump
var walking = false

var _is_crouching : bool = false

const MAX_STEP_HEIGHT = 0.15
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor := -INF

# FPV Camera
@onready var camera = %Camera
var is_zoomed: bool = false
@export var normal_fov: float = 95.0
@export var zoomed_fov: float = 60.0
@export var zoom_duration: float = 0.4

# In the air
var is_in_air = false
var max_air_distance = 0.0
var initial_y_position = 0.0
var last_frame_was_on_floor = 0

# Pushing detection / momentum WIP START
@export_range(0.0, 1.0, 0.001) var force_multiplier = 0.045

var current_platform: Node3D = null
var previous_platform_transform: Transform3D
var is_being_pushed: bool = false
# Pushing detection / momentum WIP END

# Test if this curve works with TWEENS
# @export var custom_curve: Curve

func _ready():

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	CROUCH_SHAPECAST.add_exception($".")

# Zoom key
func _input(event):
	# Zoom key
	if event.is_action_pressed("zoom"):
		# print("ZOOM")
		toggle_zoom()
	
	# Crouch key
	if event.is_action_pressed("crouch"):
		toggle_crouch()
	
	# Exit key
	if event.is_action_pressed("exit"):
		get_tree().quit()
	
	# Camera rotation
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_handle_camera_rotation(event)
	
func _handle_camera_rotation(event: InputEvent):
	# Rotate the camera based on the mouse movement
	var mouse_x = -event.relative.x * MOUSE_SENSITIVITY
	var mouse_y = -event.relative.y * MOUSE_SENSITIVITY
	rotate_y(deg_to_rad(mouse_x))
	$Head.rotate_x(deg_to_rad(mouse_y))
	
	# Stop the head from rotating too far up or down + soft clamp
	var head_rot_x = $Head.rotation.x
	var new_head_rot_x = clamp(head_rot_x, deg_to_rad(-90) - (head_rot_x - deg_to_rad(60)) * 0.1, deg_to_rad(60) + (head_rot_x - deg_to_rad(-80)) * 0.1)
	$Head.rotation.x = lerp($Head.rotation.x, new_head_rot_x, 0.35)


# Stair functions START

func is_surface_too_steep(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func _run_body_test_motion(from : Transform3D, motion : Vector3, result = null) -> bool:
	if not result: result = PhysicsTestMotionResult3D.new()
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(self.get_rid(), params, result)

func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	var floor_below : bool = %StairsBelowRayCast3D.is_colliding() and not is_surface_too_steep(%StairsBelowRayCast3D.get_collision_normal())
	var was_on_floor_last_frame = Engine.get_physics_frames() - _last_frame_was_on_floor == 1
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if _run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap

func _snap_up_stairs_check(delta) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	# Don't snap stairs if trying to jump, also no need to check for stairs ahead if not moving
	if self.velocity.y > 0 or (self.velocity * Vector3(1,0,1)).length() == 0: return false
	var expected_move_motion = self.velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance = self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	# We give some clearance above to ensure there's ample room for the player.
	# If it hits a step <= MAX_STEP_HEIGHT, we can teleport the player on top of the step
	# along with their intended motion forward.
	var down_check_result = PhysicsTestMotionResult3D.new()
	if (_run_body_test_motion(step_pos_with_clearance, Vector3(0,-MAX_STEP_HEIGHT*2,0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get a bit of jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		# 0.005 - less stuck, but 0.001 works best so far!
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.0008 or (down_check_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT: return false
		%StairsAheadRayCast3D.global_position = down_check_result.get_collision_point() + Vector3(0,MAX_STEP_HEIGHT,0) + expected_move_motion.normalized() * 0.1
		%StairsAheadRayCast3D.force_raycast_update()
		if %StairsAheadRayCast3D.is_colliding() and not is_surface_too_steep(%StairsAheadRayCast3D.get_collision_normal()):
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

# Stair functions END

func _physics_process(delta):
	process_input()
	process_movement(delta)
	
	# Pushing detection / momentum WIP START
	if is_on_floor():
		var collision = get_last_slide_collision()
		if collision:
			var collider = collision.get_collider()
			
			# Platform detection
			if collider != current_platform:
				current_platform = collider
				previous_platform_transform = current_platform.global_transform
				is_being_pushed = false
			
			if current_platform:
				# Get platform's transform change
				var current_transform = current_platform.global_transform
				
				# Calculate platform's effective velocity at the character's position
				var platform_velocity = _calculate_velocity_at_point(
					previous_platform_transform,
					current_transform,
					global_position,
					delta
				)
				
				# Apply platform velocity to character
				velocity += platform_velocity * force_multiplier
				
				# Update for next frame
				previous_platform_transform = current_transform
				
				# Report significant movement
				if platform_velocity.length() > 0.1:
					if not is_being_pushed:
						print("Started being pushed by platform")
						is_being_pushed = true
				elif is_being_pushed:
					print("No longer being pushed")
					is_being_pushed = false
	else:
		current_platform = null
		is_being_pushed = false
	# Pushing detection / momentum WIP END   

	# Check if we just left the ground
	if not is_on_floor() and !is_in_air:
		is_in_air = true
		initial_y_position = global_position.y
		max_air_distance = 0.0
		print("Left ground!")
   
	# While in air, track maximum distance
	if is_in_air:
		var current_distance = abs(initial_y_position - global_position.y)
		max_air_distance = max(max_air_distance, current_distance)
   
   # Check if we just landed
	if is_on_floor() and is_in_air:
		is_in_air = false
		print("Landed! Maximum air distance was: ", max_air_distance)
   
	if is_on_floor():
		last_frame_was_on_floor = Engine.get_physics_frames()

	GlobalScript.debug.add_property("FPS",GlobalScript.debug.frames_per_second, 1)
	GlobalScript.debug.add_property("Speed",str(velocity.length()).pad_decimals(3), 2)
	GlobalScript.debug.add_property("X rotation", str(rad_to_deg($Head.rotation.x)).pad_decimals(3), 3)
	
func process_input():
	direction = Vector3()
	
	# Movement directions
	if is_on_floor() or _snapped_to_stairs_last_frame:
		if Input.is_action_pressed("forward"):
			direction -= transform.basis.z
		elif Input.is_action_pressed("backward"):
			direction += transform.basis.z
		if Input.is_action_pressed("left"):
			direction -= transform.basis.x
		elif Input.is_action_pressed("right"):
			direction += transform.basis.x
	
	# Jumping
	wish_jump = Input.is_action_just_pressed("jump")
	
	# Walking
	# walking = Input.is_action_pressed("walk")
	
func process_movement(delta):
	# Get the normalized input direction so that we don't move faster on diagonals
	var wish_dir = direction.normalized()

	if is_on_floor() or _snapped_to_stairs_last_frame:
		# If wish_jump is true then we won't apply any friction and allow the 
		# player to jump instantly, this gives us a single frame where we can 
		if wish_jump and _is_crouching == false: # "_is_crouching == false" disables jump while crouched
			velocity.y = JUMP_IMPULSE
			# Update velocity as if we are in the air
			velocity = update_velocity_air(wish_dir, delta)
			wish_jump = false
		else:
			velocity = update_velocity_ground(wish_dir, delta)
	else:
		# Only apply gravity while in the air
		velocity.y -= GRAVITY * delta
		velocity = update_velocity_air(wish_dir, delta)

	
	# Move the player once velocity has been calculated
	if not _snap_up_stairs_check(delta):
		move_and_slide()
		_snap_down_to_stairs_check()
	#move_and_slide()
	#_snap_down_to_stairs_check()

func accelerate(wish_dir: Vector3, max_velocity: float, delta):
	# Get our current speed as a projection of velocity onto the wish_dir
	var current_speed = velocity.normalized().dot(wish_dir)
	# How much we accelerate is the difference between the max speed and the current speed
	# clamped to be between 0 and MAX_ACCELERATION which is intended to stop you from going too fast
	var add_speed = clamp(max_velocity - current_speed, 0, MAX_ACCELERATION * delta)
	
	return velocity + add_speed * wish_dir
	
func update_velocity_ground(wish_dir: Vector3, delta):
	# Apply friction when on the ground and then accelerate
	var speed = velocity.length()
	
	if speed != 0:
		var control = max(STOP_SPEED, speed)
		var drop = control * friction * delta
		
		# Scale the velocity based on friction
		velocity *= max(speed - drop, 0) / speed
	
	return accelerate(wish_dir, MAX_VELOCITY_GROUND, delta)
	
func update_velocity_air(wish_dir: Vector3, delta):
	# Do not apply any friction
	return accelerate(wish_dir, MAX_VELOCITY_AIR, delta)

func crouching(state : bool):
	match state:
		true:
			ANIMATIONPLAYER.play("Crouch", 0, CROUCH_SPEED)
		false:
			ANIMATIONPLAYER.play("Crouch", 0, -CROUCH_SPEED, true)

func toggle_crouch():
	if _is_crouching == true and CROUCH_SHAPECAST.is_colliding() == false:
		crouching(false)
	elif _is_crouching == false:
		crouching(true)

func _on_animation_player_animation_started(anim_name):
	if anim_name == "Crouch":
		_is_crouching = !_is_crouching

#func uncrouch_check():
	#if CROUCH_SHAPECAST.is_colliding() == false:
		#crouching(false)
	#if CROUCH_SHAPECAST.is_colliding() == true:
		#await get_tree().create_timer(0.1).timeout
		#uncrouch_check()

func toggle_zoom():
	await get_tree().create_timer(0.15).timeout  # delay
	is_zoomed = not is_zoomed
	var target_fov = zoomed_fov if is_zoomed else normal_fov
	create_tween().tween_property(camera, "fov", target_fov, zoom_duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)

# Pushing detection / momentum WIP START
func _calculate_velocity_at_point(old_transform: Transform3D, new_transform: Transform3D, point: Vector3, delta: float) -> Vector3:
	# Get the point's position relative to the platform's origin
	var local_point = old_transform.inverse() * point
	
	# Get the point's new position after transform change
	var new_point = new_transform * local_point
	
	# The velocity is the difference in positions
	return (new_point - point) / delta
# Pushing detection / momentum WIP END
