extends Node2D

# --- EXPORTED SETTINGS ---
@export var painting_texture: Texture2D 

@export var cursor_speed: float = 400.0
@export var min_point_distance: float = 15.0
@export var snap_distance: float = 35.0 # How close to the start to finish

# --- NODE REFERENCES ---
@onready var cursor: CharacterBody2D = $Cursor
@onready var tape_line: Line2D = $PlayerTape
@onready var target_path: Path2D = $TargetShape
@onready var paint_results: Node2D = $PaintResults
@onready var target_preview: Sprite2D = $TargetPreview

# --- STATE VARIABLES ---
var is_tracing: bool = true
var last_point_pos: Vector2
var screen_center: Vector2

func _ready():
	# Dynamically find center of the current screen/viewport
	screen_center = get_viewport_rect().size / 2.0
	if target_preview:
		target_preview.position = screen_center

	# 1. Generate target shape to trace
	generate_target_shape()
	
	# 2. Position player cursor at the first point of the generated curve
	var start_pos = target_path.curve.get_point_position(0)
	cursor.global_position = start_pos
	last_point_pos = start_pos
	
	# 3. Setup tape visuals using Godot 4 syntax
	tape_line.clear_points()
	tape_line.add_point(start_pos)
	tape_line.width = 12.0
	tape_line.default_color = Color(0.9, 0.8, 0.6, 0.9)
	tape_line.joint_mode = Line2D.LINE_JOINT_ROUND
	tape_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	tape_line.end_cap_mode = Line2D.LINE_CAP_ROUND

func _process(delta):
	if not is_tracing: return
	
	# Movement handling
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	cursor.global_position += direction * cursor_speed * delta
	
	# Leave tape behind as cursor moves
	if cursor.global_position.distance_to(last_point_pos) > min_point_distance:
		tape_line.add_point(cursor.global_position)
		last_point_pos = cursor.global_position
		
	# Check for loop completion
	if tape_line.get_point_count() > 10:
		var start_point = tape_line.get_point_position(0)
		queue_redraw() # Draw green snap hint
		
		if cursor.global_position.distance_to(start_point) < snap_distance:
			finish_tracing()

func _input(event):
	if not is_tracing and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()

func _draw():
	if is_tracing and tape_line.get_point_count() > 10:
		var start_point = tape_line.get_point_position(0)
		draw_circle(start_point, snap_distance, Color(0.2, 1.0, 0.2, 0.3))

func generate_target_shape():
	var new_curve = Curve2D.new()
	var points = 8
	
	for i in range(points):
		var angle = (TAU / points) * i
		var radius = randf_range(120.0, 250.0)
		var pos = screen_center + Vector2(cos(angle), sin(angle)) * radius
		var tangent = Vector2(cos(angle + PI/2.0), sin(angle + PI/2.0)) * (radius * 0.3)
		new_curve.add_point(pos, -tangent, tangent)
		
	new_curve.add_point(new_curve.get_point_position(0), new_curve.get_point_in(0), new_curve.get_point_out(0))
	target_path.curve = new_curve
	
	# Create target line outline
	var outline = Line2D.new()
	outline.width = 4.0
	outline.default_color = Color(1, 1, 1, 0.7)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	for p in new_curve.get_baked_points():
		outline.add_point(p)
	target_path.add_child(outline)

func finish_tracing():
	is_tracing = false
	queue_redraw()
	
	# Close player tape visually
	tape_line.add_point(tape_line.get_point_position(0)) 
	
	var target_points = target_path.curve.get_baked_points()
	var player_points = tape_line.points
	
	# Geometry boolean operations
	var correct_areas = Geometry2D.intersect_polygons(player_points, target_points)
	var overpaint_areas = Geometry2D.clip_polygons(player_points, target_points)
	var underpaint_areas = Geometry2D.clip_polygons(target_points, player_points)
	
	target_path.hide()
	if target_preview:
		target_preview.hide()
	
	draw_results(correct_areas, overpaint_areas, underpaint_areas)

func draw_results(correct, overpaint, underpaint):
	var red_glow = Color(1.0, 0.0, 0.0, 0.85)
	
	for poly in correct:
		create_textured_polygon(poly, painting_texture)
		
	for poly in overpaint:
		create_solid_polygon(poly, red_glow)
		
	for poly in underpaint:
		create_solid_polygon(poly, red_glow)

func create_textured_polygon(points_array: PackedVector2Array, tex: Texture2D):
	if tex == null:
		push_error("No painting texture assigned in Inspector!")
		return
		
	var poly_node = Polygon2D.new()
	poly_node.polygon = points_array
	poly_node.texture = tex
	
	var tex_size = tex.get_size()
	var center_offset = screen_center - (tex_size / 2.0)
	
	var uv_array = PackedVector2Array()
	for point in points_array:
		uv_array.append(point - center_offset)
		
	poly_node.uv = uv_array
	paint_results.add_child(poly_node)

func create_solid_polygon(points_array: PackedVector2Array, poly_color: Color):
	var poly_node = Polygon2D.new()
	poly_node.polygon = points_array
	poly_node.color = poly_color
	paint_results.add_child(poly_node)
