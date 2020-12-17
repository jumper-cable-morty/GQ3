extends KinematicBody

#########
# Based on https://github.com/Zinglish/quake3-movement-unity3d/blob/master/CPMPlayer.cs
#########

var CMD = {
	"z_move" : 0,
	"x_move" : 0,
#    "up_move" : 0,
}

#var player_view     # Camera
#var player_view_y_offset = 0.6 # The height at which the camera is bound to
var x_mouse_sensitivity = 0.25
var y_mouse_sensitivity = 0.25

# Frame occuring factors
var gravity = 10
var friction = 6 #Ground friction

# Movement stuff
var move_speed = 7                  # Ground move speed
var run_acceleration = 14           # Ground accel
var run_deacceleration = 10         # Deacceleration that occurs when running on the ground
var air_acceleration = 2.0          # Air accel
var air_decceleration = 2           # Deacceleration experienced when ooposite strafing
var air_control = 0.05              # How precise air control is
var side_strafe_acceleration = 0.5    # How fast acceleration occurs to get up to side_strafe_speed when
var side_strafe_speed = 0.6         # What the max speed to generate when side strafing
var jump_speed = 5   #was 10        # The speed at which the character's up axis gains when hitting jump
#var move_scale = 1.0

# Camera rotations
onready var head = $Head

var move_direction_norm = Vector3()
var player_velocity = Vector3()
var player_top_velocity = 0.0

# Q3: players can queue the next jump just before he hits the ground
var wish_jump = false

# Used to display real time fricton values
var player_friction = 0.0

var on_floor = false

func _ready():
	$"Ground-Check".add_exception(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process_input(true)


func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg2rad(-event.relative.x * y_mouse_sensitivity))
		head.rotate_x(deg2rad(-event.relative.y * x_mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg2rad(-89), deg2rad(89))
	
	if event.is_action_pressed("jump"):
		wish_jump = true
	if event.is_action_released("jump"):
		wish_jump = false


func _physics_process(delta):
	# Movement, here's the important part
	set_movement_dir()
	if is_on_floor() or $"Ground-Check".is_colliding():
		ground_move(delta)
	elif not is_on_floor() or not $"Ground-Check".is_colliding():
		air_move(delta)
	
	print (player_velocity)
	move_and_slide(player_velocity)
	
	# Calculate top velocity
	var udp = player_velocity
	udp.y = 0.0
	if player_velocity.length() > player_top_velocity:
		player_top_velocity = player_velocity.length()

func is_grounded():
	if not is_on_floor() and $"Ground-Check".is_colliding():
		on_floor = true
	elif is_on_floor() and not $"Ground-Check".is_colliding():
		on_floor = false
	return on_floor

func set_movement_dir():
	CMD.z_move = 0
	CMD.x_move = 0
	var aim = get_global_transform().basis
	var direction = Vector3()
	direction -= aim[2] * Input.get_action_strength("move_ahead")
	direction += aim[2] * Input.get_action_strength("move_back")
	direction -= aim[0] * Input.get_action_strength("move_left")
	direction += aim[0] * Input.get_action_strength("move_right")
	CMD.z_move = direction.z
	CMD.x_move = direction.x

func ground_move(delta):
	var wishdir = Vector3()
	var _wishvel = Vector3()
	
	# Do not apply friction if the player is queueing up the next jump
	if not wish_jump:
		apply_friction(1.0, delta)
	else:
		apply_friction(0, delta)
	
	wishdir = Vector3(CMD.x_move, 0, CMD.z_move)
	wishdir.normalized()
	move_direction_norm = wishdir
	
	var wishspeed = wishdir.length()
	wishspeed *= move_speed
	
	accelerate(wishdir, wishspeed, run_acceleration, delta)
	
	# Reset the gravity velocity
	player_velocity.y = 0
	
	if wish_jump:
		player_velocity.y = jump_speed
		wish_jump = false

# Execs when the player is in the air
func air_move(delta):
	var wishdir
	var _wishvel = air_acceleration
	var accel
	
	wishdir =  Vector3(CMD.x_move, 0, CMD.z_move)
	var wishspeed = wishdir.length()
	wishspeed *= move_speed
	
	wishdir.normalized()
	move_direction_norm = wishdir
	
	# CPM: air_control
	var wishspeed2 = wishspeed
	if player_velocity.dot(wishdir) < 0:
		accel = air_decceleration
	else:
		accel = air_acceleration
	# If the player is ONLY strafing left or right
	if CMD.z_move == 0 and CMD.x_move != 0:
		if wishspeed > side_strafe_speed:
			wishspeed = side_strafe_speed
		accel = side_strafe_acceleration
	
	accelerate(wishdir, wishspeed, accel, delta)
	if air_control > 0:
		air_con(wishdir, wishspeed2, delta)
	# !CPM: air_control
	
	# Apply gravity
	player_velocity.y -= gravity * delta
	
	
# Air control occurs when the player is in the air, it allows
# players to move side to side much faster rather than being
# 'sluggish' when it comes to cornering.
func air_con(wishdir, wishspeed, delta):
	var zspeed
	var speed
	var dot
	var k
	
	# Can't control movement if not moving forward or backward
	if abs(CMD.z_move) < 0.001 or abs(wishspeed) < 0.001:
		return
	zspeed = player_velocity.y
	player_velocity.y = 0
	# Next two lines are equivalent to idTech's VectorNormalize()
	speed = player_velocity.length()
	player_velocity = player_velocity.normalized()
	dot = player_velocity.dot(wishdir)
	k = 32
	k *= air_control * dot * dot * delta
	
	# Change direction while slowing down
	if dot > 0:
		player_velocity.x = player_velocity.x * speed + wishdir.x * k
		player_velocity.y = player_velocity.y * speed + wishdir.y * k
		player_velocity.z = player_velocity.z * speed + wishdir.z * k
		
		player_velocity = player_velocity.normalized()
		move_direction_norm = player_velocity
	
	player_velocity.x *= speed
	player_velocity.y = zspeed # Note this line
	player_velocity.z *= speed

#Applies friction to the player, called in both the air and on the ground
func apply_friction(t, delta):
	var vec = player_velocity # Equivalent to: VectorCopy()
	var speed
	var newspeed
	var control
	var drop
	
	vec.y = 0.0
	speed = vec.length()
	drop = 0.0
	
	# Only if the player is on the ground then apply friction
	if is_grounded():
		if speed < run_deacceleration:
			control = run_deacceleration
		else:
			control = speed
		drop = control * friction * delta * t
	
	newspeed = speed - drop
	player_friction = newspeed
	if newspeed < 0:
		newspeed = 0
	if speed > 0:
		newspeed /= speed
	
	player_velocity.x *= newspeed
	player_velocity.y *= newspeed
	player_velocity.z *= newspeed

func accelerate(wishdir, wishspeed, accel, delta):
	var addspeed
	var accelspeed
	var currentspeed
	
	currentspeed = player_velocity.dot(wishdir)
	addspeed = wishspeed - currentspeed
	if addspeed <= 0:
		return
	accelspeed = accel * delta * wishspeed
	if accelspeed > addspeed:
		accelspeed = addspeed
	
	player_velocity.x += accelspeed * wishdir.x
	player_velocity.z += accelspeed * wishdir.z
