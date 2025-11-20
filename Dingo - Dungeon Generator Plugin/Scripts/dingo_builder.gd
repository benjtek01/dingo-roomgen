@tool
extends Node3D
##This script reads data from the GridMap & instantiates the appropriate scenes for different tile IDs
##it removes unecesssary meshes between tiles & randomizes variations for room pieces

#region INSPECTOR SETUP
#==INSPECTOR SETUP BUILD========================================================
@export_category("Build me a dungeon!")
#start button
@export var start : bool = false : set = set_start
func set_start(_val: bool) -> void:
	if Engine.is_editor_hint():
		cancel_build = false
		build_rooms()
	
#cancel button
@export var cancel : bool = false : set = set_cancel
func set_cancel(_val: bool) -> void:
	if Engine.is_editor_hint():
		cancel_build = true
var cancel_build: bool = false
	
#==INSPECTOR SETUP BUILD SETTINGS===============================================
@export_category("Build settings")
#building animation speed
@export var build_speed: float = 0.05
#gridmap path
@export var grid_map_path : NodePath
@onready var grid_map : GridMap = get_node(grid_map_path)
	
#==INSPECTOR SETUP ROOM SETUP===================================================
@export_category("Room setup")
#corridor scene to be added
@export var corridor_scene : PackedScene
#rooms to be added
@export var room_types: Array[RoomType] = []
#endregion

#region ONREADY
#build when game starts
func _ready() -> void:
	if not Engine.is_editor_hint():
		build_rooms()
#endregion

#region DIRECTIONS DICTIONARY
#==DIRECTIONS DICTIONARY========================================================
var directions : Dictionary = {
	"up" : Vector3i.FORWARD,
	"down" : Vector3i.BACK,
	"left" : Vector3i.LEFT,
	"right" : Vector3i.RIGHT
}
#endregion

#region CALL KEEP RANDOM
#keeps a random mesh variation from scene setup (for each piece)
func call_keep_random_on(node: Node):
	for dir in ["up", "down", "left", "right"]:
		node.call("keep_random_wall_" + dir)
		node.call("keep_random_door_" + dir)
	node.call("keep_random_floor")
	node.call("keep_random_ceiling")

#endregion

#region BUILD STATIC ROOMS
#==BUILD STATIC ROOMS==================================================
#finds center of each room and places scene there
func st_place_static_rooms():
	#loop through all cells in gridmap 
	var used_cells = grid_map.get_used_cells()
	var handled_cells := {}
	var t := 0
	#exit if cancelled, skip already processed, skip non room tiles
	for cell in used_cells:
		if check_cancel():
			return
		if handled_cells.has(cell):
			continue
		var tile_id = grid_map.get_cell_item(cell)
		if tile_id < 2:
			continue
			#check static type
		var room_type = st_get_static_room_type(tile_id)
		if room_type == null:
			continue
			#use flood fill to group
		var group = st_flood_fill(cell, used_cells, handled_cells)
		for c in group:
			handled_cells[c] = true
			#compute center
		var center = st_compute_group_center(group)
			#get next scene and position in center
		var scene = room_type.get_next_scene()
		if scene != null:
			var instance = scene.instantiate()
			instance.position = center
			add_child(instance)
			instance.set_owner(owner)
			t += 1
			if t % 1 == 0:
				await get_tree().create_timer(build_speed).timeout
			if check_cancel():
				return

func st_get_static_room_type(tile_id: int) -> RoomType:
	#search room types for matching ID (static)
	for rt in room_types:
		if rt.tile_id == tile_id and rt.scene_mode == RoomType.SceneMode.STATIC:
			return rt
	return null

func st_flood_fill(cell: Vector3i, used_cells: Array, handled_cells: Dictionary) -> Array:
	#flood fill algorithim 
	var group = [cell]
	var queue = [cell]
	var tile_id = grid_map.get_cell_item(cell)
	#take first cell from queue & check neighbors to group
	while queue.size() > 0:
		var current = queue.pop_front()
		for dir in directions.values():
			var neighbor = current + dir
			if used_cells.has(neighbor) and not handled_cells.has(neighbor):
				if grid_map.get_cell_item(neighbor) == tile_id:
					group.append(neighbor)
					queue.append(neighbor)
				handled_cells[neighbor] = true
	return group

func st_compute_group_center(group: Array) -> Vector3:
	#compute center of group
	var center := Vector3.ZERO
	for c in group:
		center += Vector3(c) + Vector3(0.5, 0, 0.5)
	return center / group.size()
#endregion

#region REMOVE PIECES
#15 = door 14 = corridor 
#removes walls & doors between cells based on type & neighbor type
func handle_cells(cell: Node3D, dir: String, cell_index: int, neighbor_index: int):
	#NO NEIGHBOR (neighbor is air)
	if neighbor_index == -1:
		cell.call("remove_door_" + dir)
		return
	#CORRIDOR CELL (cell is corridor, neighbor is corridor or door)
	if cell_index == 14:
		if neighbor_index == 14 or neighbor_index == 15:
			cell.call("remove_wall_" + dir)
		else:
			return
	#ROOM CELL
	if cell_index >= 2:
		#if neighbor is corridor 
		if neighbor_index == 14:
			#check if corridor is end corridor
			var corridor_cell = Vector3(cell.position) + Vector3(directions[dir])
			var corridor_neighbors = 0
			for d in directions.values():
				var n_cell = Vector3(corridor_cell) + Vector3(d)
				var n_index = grid_map.get_cell_item(Vector3i(n_cell))
				if n_index == 14:
					corridor_neighbors += 1
			if corridor_neighbors <= 1:
				#if end corridor
				cell.call("remove_wall_" + dir)
			else:
				#if not end corridor
				cell.call("remove_door_" + dir)
			return
			#if neighbor is another room
		elif neighbor_index >= 2:
			cell.call("remove_wall_" + dir)
			cell.call("remove_door_" + dir)

func handle_doors(instance: Node3D, cell: Vector3i):
	#loop through directions
	var cell_index = grid_map.get_cell_item(cell)
	for i in range(4):
		var dir_name = directions.keys()[i]
		var neighbor_cell = cell + directions.values()[i]
		var neighbor_index = grid_map.get_cell_item(neighbor_cell)
		#if cell is a door 
		if cell_index == 15:
			#if neighbor is a room and not a corridor 
			if neighbor_index >= 2 and neighbor_index != 14:
				instance.call("remove_wall_" + dir_name)
				instance.call("remove_door_" + dir_name)
				#if neighbor is a corridor 
			elif neighbor_index == 14:
				instance.call("remove_wall_" + dir_name)
				#if neighbor is air 
			else:
				instance.call("remove_door_" + dir_name)
		#if not a door 
		else:
			if is_instance_valid(instance):
				handle_cells(instance, dir_name, cell_index, neighbor_index)
#endregion

#region HELPER FUNCTIONS
#check if cancelled 
func check_cancel() -> bool:
	if cancel_build:
		print_cancelled()
		return true
	return false

#clear all children of this node
func clear_children():
	for c in get_children():
		remove_child(c)
		c.queue_free()
	await get_tree().process_frame

#create room instance based on cell index
func create_instance_for_cell(_cell: Vector3i, cell_index: int) -> Node3D:
	var instance: Node3D = null
	#if corridor
	if cell_index == 14:
		instance = corridor_scene.instantiate()
	#if room
	elif cell_index >= 2:
		var room_type: RoomType = null
		for rt in room_types:
		#sort dynamic & static
			if rt.tile_id == cell_index and rt.scene_mode == RoomType.SceneMode.DYNAMIC:
				room_type = rt
				break
		if room_type != null:
			var scene: PackedScene = room_type.get_next_scene()
			if scene != null:
				instance = scene.instantiate()
	return instance

#place instance in center of tile as a child of this node
func place_instance(instance: Node3D, cell: Vector3i):
	instance.position = Vector3(cell) + Vector3(0.5, 0, 0.5)
	add_child(instance)
	instance.set_owner(owner)

#check if a door touches a static room (used to create space for static rooms)
func touches_static_room(cell: Vector3i) -> bool:
	for dir in directions.values():
		var neighbor = cell + dir
		var neighbor_index = grid_map.get_cell_item(neighbor)
		#if neighbor is a room
		if neighbor_index >= 2:
			for rt in room_types:
				#if neighbor is static
				if rt.tile_id == neighbor_index and rt.scene_mode == RoomType.SceneMode.STATIC:
					return true
	return false

#find closest dynamic room (for doors)
func find_closest_dynamic_room(cell: Vector3i, room_instances: Dictionary) -> Node3D:
	var closest_dynamic_room = null
	var closest_dist := INF
	#go through all cells that contain a room
	for room_cell in room_instances.keys():
		if check_cancel():
			return null
		#get room type
		var room_inst = room_instances[room_cell]
		var room_type: RoomType = null
		if "room_type" in room_inst:
			room_type = room_inst.room_type
		elif "tile_id" in room_inst:
			for rt in room_types:
				if rt.tile_id == room_inst.tile_id:
					room_type = rt
					break
		#skip static rooms
		if room_type != null and room_type.scene_mode == RoomType.SceneMode.STATIC:
			continue
		#skip corridors
		if grid_map.get_cell_item(room_cell) == 14:
			continue
		#get distance & update if closer
		var dist = cell.distance_to(room_cell)
		if dist < closest_dist:
			closest_dist = dist
			closest_dynamic_room = room_inst
	return closest_dynamic_room
#endregion

#region MAIN BUILD ROOMS FUNCTION
#==BUILD ROOMS==================================================
func build_rooms():
	#clear existing rooms
	await clear_children()
	if check_cancel():
		return
	var room_instances := {}
	#place static rooms 
	await st_place_static_rooms()
	if check_cancel():
		return
	#create scene instances for used tile indexes
	var used_cells := grid_map.get_used_cells()
	var t := 0
	for cell in used_cells:
		if check_cancel():
			return
		var cell_index = grid_map.get_cell_item(cell)
		var instance = create_instance_for_cell(cell, cell_index)
		if instance != null:
			place_instance(instance, cell)
			room_instances[cell] = instance
		t += 1
		if t % 50 == 0:
			await get_tree().create_timer(build_speed).timeout
	for instance in room_instances.values():
		if check_cancel():
			return
		#randomize variations
		call_keep_random_on(instance)
	for cell in used_cells:
		if check_cancel():
			return
		#if not door
		if grid_map.get_cell_item(cell) != 15:
			continue
		#skip if touching a static room 
		if touches_static_room(cell):
			continue
		#find closest dynamic room
		var closest_dynamic_room = find_closest_dynamic_room(cell, room_instances)
		if closest_dynamic_room == null:
			continue
		#duplicate nearest dynamic room as a door instance 
		var door_instance: Node3D = closest_dynamic_room.duplicate()
		add_child(door_instance)
		door_instance.set_owner(owner)
		#randomize & position in center 
		call_keep_random_on(door_instance)
		door_instance.position = Vector3(cell) + Vector3(0.5, 0, 0.5)
		#have the door inherit tile ID & roomtype from closest dynamic room
		if "tile_id" in closest_dynamic_room:
			door_instance.tile_id = closest_dynamic_room.tile_id
		elif "room_type" in closest_dynamic_room:
			door_instance.room_type = closest_dynamic_room.room_type
			door_instance.tile_id = closest_dynamic_room.room_type.tile_id
		room_instances[cell] = door_instance
	t = 0
	#call handle doors on cells
	for cell in room_instances.keys():
		if check_cancel():
			return
		var instance = room_instances[cell]
		if not is_instance_valid(instance):
			continue
		handle_doors(instance, cell)
		t += 1
		if t % 10 == 0:
			await get_tree().create_timer(build_speed).timeout
	await get_tree().process_frame
	if not cancel_build:
		print_finished()

#endregion

#region PRINT 
func print_cancelled():
	print("Build cancelled!")

func print_finished():
	print("Build finished!")
#endregion
