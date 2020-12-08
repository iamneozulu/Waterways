# Copyright © 2020 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
tool
extends Spatial

const WaterHelperMethods = preload("res://addons/river_tool/water_helper_methods.gd")

const DEFAULT_SHADER_PATH = "res://addons/river_tool/shaders/river.shader"
const DEFAULT_WATER_TEXTURE_PATH = "res://addons/river_tool/textures/water1.png"
const FILTER_RENDERER_PATH = "res://addons/river_tool/FilterRenderer.tscn"
const NOISE_TEXTURE_PATH = "res://addons/river_tool/textures/noise.png"
const DEBUG_SHADER_PATH = "res://addons/river_tool/shaders/river_debug.shader"
const DEBUG_PATTERN_PATH = "res://addons/river_tool/textures/debug_pattern.png"

# Shape Properties
export(int, 1, 8) var step_length_divs := 1 setget set_step_length_divs
export(int, 1, 8) var step_width_divs := 1 setget set_step_width_divs
export(float, 0.1, 5.0) var smoothness := 0.5 setget set_smoothness

# Material Properties
export(Color, RGBA) var albedo := Color(0.1, 0.1, 0.1, 0.0) setget set_albedo
export(Color, RGBA) var foam_color := Color.white setget set_foam_color
export(float, 0.0, 4.0) var foam_amount := 1.0 setget set_foam_amount
export(float, 0.0, 1.0) var foam_smoothness := 1.0 setget set_foam_smoothness
export(float, 0.0, 1.0) var roughness := 0.2 setget set_roughness
export(float, -1.0, 1.0) var refraction := 0.05 setget set_refraction
export(Texture) var water_texture : Texture setget set_water_texture
export(float, 1.0, 20.0) var water_tiling := 1.0 setget set_water_tiling
export(float, -16.0, 16.0) var normal_scale := 1.0 setget set_normal_scale
export(float, 0.0, 1.0) var absorption := 0.0 setget set_absorption
export(float, 0.0, 10.0) var flow_speed := 1.0 setget set_flowspeed
export(float, 5.0, 100.0) var lod0_distance := 30.0 setget set_lod0_distance

var curve : Curve3D
var widths := [] setget set_widths
var valid_flowmap := false

var _steps := 2
var _st : SurfaceTool
var _mdt : MeshDataTool
var _mesh_instance : MeshInstance
var _default_shader : Shader
var _debug_shader : Shader
var _material : ShaderMaterial
var _debug_material : ShaderMaterial
var _first_enter_tree := true
var _filter_renderer
var _flow_foam_noise : Texture

# Signal used to update handles when values are changed on script side
signal river_changed


# This is to serialize values without exposing it in the inspector
func _get_property_list() -> Array:
	return [
		{
			name = "curve",
			type = TYPE_OBJECT,
			usage = PROPERTY_USAGE_STORAGE
		},
		{
			name = "widths",
			type = TYPE_ARRAY,
			usage = PROPERTY_USAGE_STORAGE
		},
		{
			name = "_flow_foam_noise",
			type = TYPE_OBJECT,
			usage = PROPERTY_USAGE_STORAGE
		},
		{
			name = "valid_flowmap",
			type = TYPE_BOOL,
			usage = PROPERTY_USAGE_STORAGE
		}
	]


# Internal Methods
func _init() -> void:
	print("init called")
	_default_shader = load(DEFAULT_SHADER_PATH) as Shader
	_debug_shader = load(DEBUG_SHADER_PATH) as Shader
	_st = SurfaceTool.new()
	_mdt = MeshDataTool.new()
	_filter_renderer = load(FILTER_RENDERER_PATH)
	_debug_material = ShaderMaterial.new()
	_debug_material.shader = _debug_shader
	_debug_material.set_shader_param("debug_pattern", load(DEBUG_PATTERN_PATH) as Texture)
	_material = ShaderMaterial.new()
	_material.shader = _default_shader
	set_water_texture(load(DEFAULT_WATER_TEXTURE_PATH) as Texture)


func _enter_tree() -> void:
	if Engine.editor_hint and _first_enter_tree:
		_first_enter_tree = false

	if not curve:
		curve = Curve3D.new()
		curve.bake_interval = 0.05
		curve.add_point(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25))
		curve.add_point(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25))
		widths = [1.0, 1.0]
	
	
	if get_child_count() <= 0:
		var new_mesh_instance := MeshInstance.new()
		new_mesh_instance.name = "RiverMeshInstance"
		add_child(new_mesh_instance)
		# Uncomment for debugging the MeshInstance object
		# new_mesh_instance.set_owner(get_tree().get_edited_scene_root()) 
		_mesh_instance = get_child(0) as MeshInstance
		_generate_river()
	else:
		_mesh_instance = get_child(0) as MeshInstance
		_material = _mesh_instance.mesh.surface_get_material(0) as ShaderMaterial
	
	set_materials("valid_flowmap", valid_flowmap)
	set_materials("flowmap", _flow_foam_noise)


func _get_configuration_warning() -> String:
	if valid_flowmap:
		return ""
	else:
		return "No flowmap is set. Select River -> Generate Flow & Foam Map to generate and assign one."


# Public Methods
func add_point(position : Vector3, index : int):
	if index == -1:
		var last_index := curve.get_point_count() - 1
		var dir := (position - curve.get_point_position(last_index) - curve.get_point_out(last_index) ).normalized() * 0.25
		curve.add_point(position, -dir, dir, -1)
		widths.append(widths[widths.size() - 1]) # If this is a new point at the end, add a width that's the same as last
	else:
		var dir := (curve.get_point_position(index + 1) - curve.get_point_position(index)).normalized() * 0.25
		curve.add_point(position, -dir, dir, index + 1)
		widths.insert(index + 1, (widths[index] + widths[index + 1]) / 2.0) # We set the width to the average of the two surrounding widths
	emit_signal("river_changed")
	_generate_river()


func remove_point(index : int):
	# We don't allow rivers shorter than 2 points
	if curve.get_point_count() <= 2:
		return
	curve.remove_point(index)
	widths.remove(index)
	emit_signal("river_changed")
	_generate_river()


# Setter Methods
func set_curve_point_position(index : int, position : Vector3) -> void:
	curve.set_point_position(index, position)
	_generate_river()


func set_curve_point_in(index : int, position : Vector3) -> void:
	curve.set_point_in(index, position)
	_generate_river()


func set_curve_point_out(index : int, position : Vector3) -> void:
	curve.set_point_out(index, position)
	_generate_river()


func set_widths(new_widths : Array) -> void:
	widths = new_widths
	if _first_enter_tree:
		return
	_generate_river()


# Parameter Setters
func set_step_length_divs(value : int) -> void:
	step_length_divs = value
	if _first_enter_tree:
		return
	valid_flowmap = false
	set_materials("valid_flowmap", valid_flowmap)
	_generate_river()
	emit_signal("river_changed")


func set_step_width_divs(value : int) -> void:
	step_width_divs = value
	if _first_enter_tree:
		return
	valid_flowmap = false
	set_materials("valid_flowmap", valid_flowmap)
	_generate_river()
	emit_signal("river_changed")


func set_smoothness(value : float) -> void:
	smoothness = value
	if _first_enter_tree:
		return
	valid_flowmap = false
	set_materials("valid_flowmap", valid_flowmap)
	_generate_river()
	emit_signal("river_changed")


func set_albedo(color : Color) -> void:
	albedo = color
	set_materials("albedo", color)


func set_foam_color(color : Color) -> void:
	foam_color = color
	set_materials("foam_color", color)


func set_foam_amount(amount : float) -> void:
	foam_amount = amount
	set_materials("foam_amount", foam_amount)


func set_foam_smoothness(amount : float) -> void:
	foam_smoothness = amount
	set_materials("foam_smoothness", amount)


func set_roughness(value : float) -> void:
	roughness = value
	set_materials("roughness", value)


func set_refraction(value : float) -> void:
	refraction = value
	set_materials("refraction", value)


func set_water_texture(texture : Texture) -> void:
	water_texture = texture
	set_materials("texture_water", texture)


func set_water_tiling(value : float) -> void:
	water_tiling = value
	set_materials("uv_tiling", value)


func set_normal_scale(value : float) -> void:
	normal_scale = value
	set_materials("normal_scale", value)


func set_absorption(value : float) -> void:
	absorption = value
	set_materials("absorption", value)


func set_flowspeed(value : float) -> void:
	flow_speed = value
	set_materials("flow_speed", value)


func set_lod0_distance(value : float) -> void:
	lod0_distance = value
	set_materials("lod0_distance", value)


# Getter Methods
func get_curve_points() -> PoolVector3Array:
	var points : PoolVector3Array
	for p in curve.get_point_count():
		points.append(curve.get_point_position(p))
	
	return points


func get_closest_point_to(point : Vector3) -> int:
	var points = []
	var closest_distance := 4096.0
	var closest_index
	for p in curve.get_point_count():
		var dist := point.distance_to(curve.get_point_position(p))
		if dist < closest_distance:
			closest_distance = dist
			closest_index = p
	
	return closest_index


# Public Methods
func bake_texture(resolution : float) -> void:
	_generate_river()
	_generate_flowmap(resolution)


func set_materials(param : String, value) -> void:
	_material.set_shader_param(param, value)
	_debug_material.set_shader_param(param, value)


func set_debug_view(index : int) -> void:
	if index == 0:
		_mesh_instance.material_override = null
	else:
		_debug_material.set_shader_param("mode", index)
		_mesh_instance.material_override =_debug_material


# Private Methods
func _generate_river() -> void:
	var average_width := WaterHelperMethods.sum_array(widths) / float(widths.size() / 2)
	_steps = int( max(1.0, round(curve.get_baked_length() / average_width)) )
	
	var river_width_values := WaterHelperMethods.generate_river_width_values(curve, _steps, step_length_divs, step_width_divs, widths)
	_mesh_instance.mesh = WaterHelperMethods.generate_river_mesh(curve, _steps, step_length_divs, step_width_divs, smoothness, river_width_values)
	_mesh_instance.mesh.surface_set_material(0, _material)


func _generate_flowmap(flowmap_resolution : float) -> void:
	WaterHelperMethods.reset_all_colliders(get_tree().root)
	
	var image := Image.new()
	image.create(flowmap_resolution, flowmap_resolution, true, Image.FORMAT_RGB8)
	image.fill(Color(0.0, 0.0, 0.0))
	
	image.lock()
	image = WaterHelperMethods.generate_collisionmap(image, _mesh_instance, _steps, step_length_divs, step_width_divs)
	print("finished collision map")
	image.unlock()
	
	# Calculate how many colums are in UV2
	var grid_side_float := sqrt(_steps)
	if fmod(grid_side_float, 1.0) != 0.0:
		grid_side_float += 1
	var grid_side := int(grid_side_float)
	
	var margin := int(round(float(flowmap_resolution) / float(grid_side)))
	
	image = WaterHelperMethods.add_margins(image, flowmap_resolution, margin)

	var texture_to_dilate := ImageTexture.new()
	texture_to_dilate.create_from_image(image)

	# Create correctly tiling noise for A channel
	var noise_texture := load(NOISE_TEXTURE_PATH) as Texture
	var noise_with_tiling := Image.new()
	var noise_with_margin_size := float(grid_side + 2) * (float(noise_texture.get_width()) / float(grid_side))
	noise_with_tiling.create(noise_with_margin_size, noise_with_margin_size, false, Image.FORMAT_RGB8)
	noise_with_tiling.lock()
	var slice_width := float(noise_texture.get_width()) / float(grid_side)
	for x in grid_side:
		noise_with_tiling.blend_rect(noise_texture.get_data(), Rect2(0.0, 0.0, slice_width, noise_texture.get_height()), Vector2(slice_width + float(x) * slice_width, slice_width))
	noise_with_tiling.unlock()
	var tiled_noise := ImageTexture.new()
	tiled_noise.create_from_image(noise_with_tiling)

	# Create renderer
	var renderer_instance = _filter_renderer.instance()

	self.add_child(renderer_instance)

	var dilate_amount = 0.6 / float(grid_side)
	var flowmap_blur_amount = 0.02 / float(grid_side) * flowmap_resolution
	var foam_offset_amount = 0.1 / float(grid_side)
	var foam_blur_amount = 0.03 / float(grid_side) * flowmap_resolution
	var dilated_texture = yield(renderer_instance.apply_dilate(texture_to_dilate, dilate_amount, flowmap_resolution), "completed")
	var normal_map = yield(renderer_instance.apply_normal(dilated_texture, flowmap_resolution), "completed")
	var flow_map = yield(renderer_instance.apply_normal_to_flow(normal_map, flowmap_resolution), "completed")
	var blurred_flow_map = yield(renderer_instance.apply_blur(flow_map, flowmap_blur_amount, flowmap_resolution), "completed")
	var foam_map = yield(renderer_instance.apply_foam(dilated_texture, foam_offset_amount, flowmap_resolution), "completed")
	var blurred_foam_map = yield(renderer_instance.apply_blur(foam_map, foam_blur_amount, flowmap_resolution), "completed")
	var combined_map = yield(renderer_instance.apply_combine(blurred_flow_map, blurred_foam_map, tiled_noise), "completed")

	remove_child(renderer_instance) # cleanup

	var flow_foam_noise_result = combined_map.get_data().get_rect(Rect2(margin, margin, flowmap_resolution, flowmap_resolution))

	_flow_foam_noise = ImageTexture.new()
	_flow_foam_noise.create_from_image(flow_foam_noise_result, 5)
	
	print("finished map bake")
	set_materials("flowmap", _flow_foam_noise)
	set_materials("valid_flowmap", true)
	valid_flowmap = true;
	
	update_configuration_warning()


# Signal Methods
func properties_changed() -> void:
	emit_signal("river_changed")
