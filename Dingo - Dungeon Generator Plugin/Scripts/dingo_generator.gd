@tool
extends Node3D
#region INSPECTOR SETUP
#start button
@export_category("Generate me a dungeon!")
@export var start: bool = false : set = set_start
@export var cancel: bool = false : set = set_cancel_generation
#general generation settings
@export_category("Generation settings")
@onready var grid_map: GridMap = $GridMap
@export_range(0,1) var corridor_amount : float = 0.25
@export var guarantee_all_room_amounts: bool = false
@export var guarantee_all_static_doors: bool = true
@export var generation_speed: float = 0.02
#area rooms can be generated
@export_category("Generation area")
@export var border_width: int = 20 : set = set_border_width
@export var border_height: int = 20 : set = set_border_height
#room types to be added
@export_category("Room setup")
@export var room_types: Array[RoomType] = []
#start button
func set_start(val: bool) -> void:
	start = val
	if start:
		start = false
		cancelled = false
		if guarantee_all_static_doors:
			await generate_until_all_doors()
		elif guarantee_all_room_amounts:
			await generate_until_all_rooms()
		else:
			await generate()
	print_finished()
#cancel button
var cancelled: bool = false
func set_cancel_generation(val: bool) -> void:
	cancel = val
	if cancel:
		cancelled = true
		cancel = false
		print_cancelled()
#endregion

#region ROOM DATA VARIABLES
var all_room_tiles: Array = []
var all_room_positions: Array = []
var room_positions_by_name := {}
var rpv2 : PackedVector2Array = PackedVector2Array()
var hallways : Array = []
var room_type_for_room : Array = []
#endregion

#region GURANTEE ROOMS/DOOR FUNCTIONS
#runs generate until all rooms have been placed
func generate_until_all_rooms() -> void:
	var all_rooms_placed: bool = false
	var total_attempts := 0
	var max_total_attempts := 50
	cancelled = false
	#runs until all rooms are placed or max attempts
	while not all_rooms_placed and total_attempts < max_total_attempts:
		if cancelled:
			print_cancelled()
			break
		await generate()
		all_rooms_placed = true
		#check if goal room amount was met for each room type
		for rt in room_types:
			if rt == null:
				continue
			var room_name = rt.name if rt.name != "" else "Unnamed Room Type"
			var actual_count = room_positions_by_name.get(room_name, []).size()
			if actual_count < rt.room_amount:
				all_rooms_placed = false
				break
		#if not all rooms were placed try again
		if not all_rooms_placed:
			print("Not all rooms placed, retrying generation...")
			clear_grid()
			total_attempts += 1
	#if max attempts was reached
	if not all_rooms_placed:
		push_warning("Could not place all rooms after %d attempts or cancelled" % max_total_attempts)
#runs generate until all static doors have been placed
func generate_until_all_doors() -> void:
	var all_doors_placed: bool = false
	var total_attempts := 0
	var max_total_attempts := 50
	cancelled = false
	#runs until all doors are placed or max attempts
	while not all_doors_placed and total_attempts < max_total_attempts:
		if cancelled:
			print_cancelled()
			break
		await generate()
		all_doors_placed = true
		#check if goal door amount was met for each room type
		for i in range(room_type_for_room.size()):
			var rt = room_type_for_room[i]
			if rt.door_mode != RoomType.DoorMode.STATIC:
				continue
			var room_tiles = all_room_tiles[i]
			#get room origin
			var origin = get_room_origin(room_tiles)
			for door_offset in rt.static_doors:
				#check if door is at the offset
				var door_pos = origin + door_offset
				if door_pos.x < 0 or door_pos.z < 0 or door_pos.x >= border_width or door_pos.z >= border_height:
					all_doors_placed = false
					break
				var cell_id = grid_map.get_cell_item(door_pos)
				if cell_id != 15:
					all_doors_placed = false
					break
			if not all_doors_placed:
				break
		#retry if failed attemmpt
		if not all_doors_placed:
			print("Not all static doors placed, retrying generation...")
			clear_grid()
			total_attempts += 1
	if not all_doors_placed:
		push_warning("Could not place all static doors after %d attempts or cancelled" % max_total_attempts)
#endregion

#region GENERATION AREA & RANGED AREA PREVIEW
#==VISUALIZATION FOR BORDER & RANGED PREVIEW====================================
func _process(_delta):
	#boolean if range values are edited or not, if yes update visualization
	if not Engine.is_editor_hint():
		return
	var needs_update := false
	#check for room types being adjusted in the editor to update
	for room_type in room_types:
		if room_type == null or room_type.placement_mode != RoomType.PlacementMode.RANGED:
			#ignore non ranged types
			continue
		#check if any area values have been changed
		var val = [room_type.range_min, room_type.range_max, room_type.min_size, room_type.max_size, room_type.room_margin]
		if not room_type.has_meta("_last_val") or room_type.get_meta("_last_val") != val:
			room_type.set_meta("_last_val", val)
			room_type.set_meta("_editing", true)
			needs_update = true
		else:
			room_type.set_meta("_editing", false)
#update visualization if value is changed
	if needs_update:
		clear_grid()
		visualize_borders()
		visualize_ranged_preview()

#update borders and ranged preview if editing
func set_border_width(val: int) -> void:
	border_width = val
	if Engine.is_editor_hint() and grid_map:
		visualize_borders()
		visualize_ranged_preview()

func set_border_height(val: int) -> void:
	border_height = val
	if Engine.is_editor_hint() and grid_map:
		visualize_borders()
		visualize_ranged_preview()

#clear whole gridmap
func clear_grid():
	if not grid_map:
		return
	grid_map.clear()
	all_room_tiles.clear()
	all_room_positions.clear()
	room_positions_by_name.clear()
	rpv2 = PackedVector2Array()
	hallways.clear()
	room_type_for_room.clear()

#visualize borders (0 should be tilemap for borders)
func visualize_borders():
	if not grid_map:
		return
	clear_grid()
	for x in range(-1, border_width + 1):
		grid_map.set_cell_item(Vector3i(x, 0, -1), 0)
		grid_map.set_cell_item(Vector3i(x, 0, border_height), 0)
	for z in range(-1, border_height + 1):
		grid_map.set_cell_item(Vector3i(-1, 0, z), 0)
		grid_map.set_cell_item(Vector3i(border_width, 0, z), 0)

#visualize tilemap (1 should be tilemap for ranged preview)
func visualize_ranged_preview():
	if not grid_map:
		return
	clear_ranged_preview()
	for room_type in room_types:
		if room_type == null or room_type.placement_mode != RoomType.PlacementMode.RANGED:
			continue
			#if editing, update visualization and clamp to size of border
		if room_type.has_meta("_editing") and room_type.get_meta("_editing"):
			var min_x = int(clamp(room_type.range_min.x, 0, border_width - 1))
			var max_x = int(clamp(room_type.range_max.x, 0, border_width - 1))
			var min_z = int(clamp(room_type.range_min.z, 0, border_height - 1))
			var max_z = int(clamp(room_type.range_max.z, 0, border_height - 1))
			#only show visualization for the room being edited
			for x in range(min_x, max_x + 1):
				for z in range(min_z, max_z + 1):
					grid_map.set_cell_item(Vector3i(x, 0, z), 1)
			break 

func clear_ranged_preview():
	#clear ranged preview
	if not grid_map:
		return
	for x in range(border_width):
		for z in range(border_height):
			if grid_map.get_cell_item(Vector3i(x, 0, z)) == 1:
				grid_map.set_cell_item(Vector3i(x, 0, z), -1)
#endregion

#region MAIN GENERATE FUNCTION
#===GENERATE DUNGEON============================================================
func generate():
	if not grid_map:
		return
	clear_grid()
	visualize_borders()
	#sort rooms by priority
	var sorted_types: Array = []
	for rt in room_types:
		if rt != null:
			sorted_types.append(rt)
	sorted_types.sort_custom(Callable(self, "cmp_room_priority"))
	#data to be tracked
	var total_rooms = 0
	var room_count_by_type := {}
	room_positions_by_name.clear()
	#define amount to be placed and tries
	for room_type in sorted_types:
		if room_type == null:
			continue
		var placed = 0
		var tries = 0
		var max_tries = room_type.room_amount * room_type.recursion
		#set room name
		var room_name = room_type.name if room_type.name != "" else "Unnamed Room Type"
		room_positions_by_name[room_name] = []
		room_count_by_type[room_name] = 0
		#try placing rooms
		while placed < room_type.room_amount and tries < max_tries:
			var pos = await try_place_room(room_type)
			#check if valid
			if pos.x >= 0:
				#update data
				room_positions_by_name[room_name].append(pos)
				room_count_by_type[room_name] += 1
				total_rooms += 1
				placed += 1
			tries += 1
	if all_room_positions.size() > 1:
		await find_delauney_and_mst()
	#print results 
	print_room_summary(total_rooms, room_count_by_type, room_positions_by_name)
#endregion

#region PLACE ROOM FUNCTIONS
#==ROOM PLACEMENT===============================================================
#defines area and shuffles posible positions then tries them
func try_place_room(room_type: RoomType) -> Vector3:
	var area_size = Vector3i(border_width, 1, border_height)
	var pos_list: Array[Vector3i] = room_type.get_room_positions(area_size)
	pos_list.shuffle()
	#for each possible position
	for start_pos in pos_list:
		var size = room_type.get_room_size()
		if start_pos.x + size.x > border_width or start_pos.z + size.z > border_height:
			continue
		#checks if empty and uses margin
		if can_place_room(start_pos, size, room_type.room_margin):
			#places room
			await place_room(start_pos, size, room_type)
			return Vector3(start_pos.x + size.x / 2.0, 0, start_pos.z + size.z / 2.0)
	#returns center of room
	return Vector3(-1, 0, -1) 

#checks every tile inside potential room plus margin, reject if occupied
func can_place_room(start_pos: Vector3i, size: Vector3i, margin: int) -> bool:
	for z in range(-margin, size.z + margin):
		for x in range(-margin, size.x + margin):
			var pos = start_pos + Vector3i(x, 0, z)
			#check if within area & if cell is free
			if pos.x < 0 or pos.x >= border_width or pos.z < 0 or pos.z >= border_height:
				return false
			if grid_map.get_cell_item(pos) != -1:
				return false
	return true

#places tiles and appends data
func place_room(start_pos: Vector3i, size: Vector3i, room_type: RoomType) -> void:
	var t : int = 0
	var room: PackedVector3Array = PackedVector3Array()
	for z in range(size.z):
		for x in range(size.x):
			var pos = start_pos + Vector3i(x, 0, z)
			grid_map.set_cell_item(pos, room_type.tile_id)
			t +=1
			#add to arrays
			room.append(pos)
			if t%10 == 9 : 
				await get_tree().create_timer(generation_speed).timeout
	all_room_tiles.append(room)
	all_room_positions.append(Vector3(start_pos.x + size.x / 2.0, 0, start_pos.z + size.z / 2.0))
	room_type_for_room.append(room_type)

#used for room priority of room types
func cmp_room_priority(a, b) -> int:
	if a.priority < b.priority:
		return -1
	elif a.priority > b.priority:
		return 1
	return 0
#endregion

#region DELAUNEY & MST ALGORITHIMS
#===DELAUNEY & MST==============================================================
#creates a Delaunay triangulation of all rooms & finds MST
func find_delauney_and_mst():
	var del_graph : AStar2D = AStar2D.new()
	var mst_graph : AStar2D = AStar2D.new()
	rpv2 = PackedVector2Array()
	#convert all room positions to 2D points
	for i in range(all_room_positions.size()):
		var p = all_room_positions[i]
		rpv2.append(Vector2(p.x, p.z))
		del_graph.add_point(i, Vector2(p.x, p.z))
		mst_graph.add_point(i, Vector2(p.x, p.z))
	#generate delaunay
	var delaunay := Geometry2D.triangulate_delaunay(rpv2)
	for i in range(0, delaunay.size(), 3):
		var p1 = int(delaunay[i])
		var p2 = int(delaunay[i + 1])
		var p3 = int(delaunay[i + 2])
		if not del_graph.are_points_connected(p1, p2):
			del_graph.connect_points(p1, p2)
		if not del_graph.are_points_connected(p2, p3):
			del_graph.connect_points(p2, p3)
		if not del_graph.are_points_connected(p1, p3):
			del_graph.connect_points(p1, p3)
	#build MST
	var visited := [0]
	while visited.size() < mst_graph.get_point_count():
		var shortest_edge = null
		var shortest_dist := INF
		for v in visited:
			for c in del_graph.get_point_connections(v):
				if not visited.has(c):
					var d = rpv2[v].distance_squared_to(rpv2[c])
					if d < shortest_dist:
						shortest_dist = d
						shortest_edge = [v, c]
		if shortest_edge == null:
			break
		mst_graph.connect_points(shortest_edge[0], shortest_edge[1])
		visited.append(shortest_edge[1])
		if del_graph.are_points_connected(shortest_edge[0], shortest_edge[1]):
			del_graph.disconnect_points(shortest_edge[0], shortest_edge[1])
	for p in del_graph.get_point_ids():
		for c in del_graph.get_point_connections(p):
			#add edges back from delauney with corridor_amount 
			if c > p and randf() < corridor_amount:
				if not mst_graph.are_points_connected(p, c):
					mst_graph.connect_points(p, c)
	#create doors & corridors
	await create_doors(mst_graph)
	await create_corridors(mst_graph)
#endregion

#region PLACE DOOR & CORRIDOR FUNCTIONS
#returns the room's origin (the top left tile) (used for static door placement)
func get_room_origin(room: PackedVector3Array) -> Vector3i:
	var min_x: int = 999999
	var min_z: int = 999999
	#find smallest x and z values in room's tiles (origin)
	for t: Vector3 in room:
		var tx: int = int(t.x)
		var tz: int = int(t.z)
		if tx < min_x:
			min_x = tx
		if tz < min_z:
			min_z = tz
	return Vector3i(min_x, 0, min_z)

#checks if a tile is a perimeter tile of its own room (used for door placement)
func is_perimeter_tile(tile: Vector3i, room_tile_id: int) -> bool:
	#cardinal directions
	var neighbors: Array[Vector3i] = [
		Vector3i(1,0,0), Vector3i(-1,0,0),
		Vector3i(0,0,1), Vector3i(0,0,-1)
	]
	#loop through each neighbor
	for n: Vector3i in neighbors:
		var p: Vector3i = tile + n
		#check if tile touches area border
		if p.x < 0 or p.x >= border_width or p.z < 0 or p.z >= border_height:
			return true
		#check if neighbor belongs to different room
		var neighbor_id: int = grid_map.get_cell_item(p)
		if neighbor_id != room_tile_id:
			return true
	return false

#given a list of two tiles finds the two tiles with the smallest distance between them 
func find_closest_pair(points_a: Array[Vector3i], points_b: Array[Vector3i]) -> Array[Vector3i]:
	var best_a = points_a[0]
	var best_b = points_b[0]
	var min_dist = INF
	#loop over pairs
	for a in points_a:
		for b in points_b:
			var d = float(a.distance_squared_to(b))
			#update best pair
			if d < min_dist:
				min_dist = d
				best_a = a
				best_b = b
	return [best_a, best_b]

#places hallway tiles 
func place_door(a: Vector3i, b: Vector3i) -> void:
	var hallway = PackedVector3Array([a, b])
	hallways.append(hallway)
	grid_map.set_cell_item(a, 15)
	grid_map.set_cell_item(b, 15)
	await get_tree().create_timer(generation_speed).timeout

#finds pairs of tiles where rooms should connect  (doors)
func create_doors(hallway_graph: AStar2D) -> void:
	hallways.clear()
	for p_id in hallway_graph.get_point_ids():
		for c_id in hallway_graph.get_point_connections(p_id):
			if c_id <= p_id:
				continue
			#grab room data
			var rt_from = room_type_for_room[p_id]
			var rt_to = room_type_for_room[c_id]
			var room_from = all_room_tiles[p_id]
			var room_to = all_room_tiles[c_id]
			var from_static = rt_from.door_mode == RoomType.DoorMode.STATIC
			var to_static = rt_to.door_mode == RoomType.DoorMode.STATIC
			#BOTH ROOMS STATIC
			if from_static and to_static:
				var max_i = min(rt_from.static_doors.size(), rt_to.static_doors.size())
				var origin_a = get_room_origin(room_from)
				var origin_b = get_room_origin(room_to)
				for i in range(max_i):
					#place static doors
					var global_a = origin_a + rt_from.static_doors[i]
					var global_b = origin_b + rt_to.static_doors[i]
					if global_a.x < 0 or global_a.z < 0 or global_a.x >= border_width or global_a.z >= border_height:
						continue
					await place_door(global_a, global_b)
				continue
			#STATIC TO DYNAMIC OR DYNAMIC TO DYNAMIC
			var points_from: Array[Vector3i] = []
			if from_static:
				#use static position
				for sd in rt_from.static_doors:
					points_from.append(get_room_origin(room_from) + sd)
			else:
				#use perimeter tiles only
				for t in room_from:
					var tile = Vector3i(int(t.x), 0, int(t.z))
					if is_perimeter_tile(tile, rt_from.tile_id):
						points_from.append(tile)
			var points_to: Array[Vector3i] = []
			if to_static:
				for sd in rt_to.static_doors:
					points_to.append(get_room_origin(room_to) + sd)
			else:
				for t in room_to:
					var tile = Vector3i(int(t.x), 0, int(t.z))
					if is_perimeter_tile(tile, rt_to.tile_id):
						points_to.append(tile)
			#fallback
			if points_from.is_empty():
				for t in room_from:
					points_from.append(Vector3i(int(t.x), 0, int(t.z)))
			if points_to.is_empty():
				for t in room_to:
					points_to.append(Vector3i(int(t.x), 0, int(t.z)))
			var best_pair = find_closest_pair(points_from, points_to)
			await place_door(best_pair[0], best_pair[1])

#creates corridors using AStar
func create_corridors(_hallway_graph: AStar2D):
	var astar: AStarGrid2D = AStarGrid2D.new()
	astar.size = Vector2i(border_width, border_height)
	astar.update()
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	#mark blocked tiles & doors
	for x: int in range(border_width):
		for z: int in range(border_height):
			var posi: Vector3i = Vector3i(x,0,z)
			var cell_id: int = grid_map.get_cell_item(posi)
			if cell_id >= 0 and cell_id != 15:
				astar.set_point_solid(Vector2i(x, z))
	#run Astar for each hallway pair
	for h: PackedVector3Array in hallways:
		var pos_from: Vector2i = Vector2i(int(h[0].x), int(h[0].z))
		var pos_to: Vector2i = Vector2i(int(h[1].x), int(h[1].z))
		var hall: PackedVector2Array = astar.get_point_path(pos_from, pos_to)
		if hall.size() == 0:
			continue
		#create corridor tiles
		for t: Vector2 in hall:
			var pos: Vector3i = Vector3i(int(t.x),0,int(t.y))
			if grid_map.get_cell_item(pos) < 0:
				grid_map.set_cell_item(pos, 14)
				await get_tree().create_timer(generation_speed).timeout
#endregion

#region PRINT 
#===PRINT ROOM SUMMARY==========================================================
@warning_ignore("shadowed_variable")
func print_room_summary(total_rooms: int, room_count_by_type: Dictionary, room_positions_by_name: Dictionary) -> void:
	print("\n===ROOM SUMMARY===")
	print("\n--Room Amounts--")
	print("Total rooms generated: ", total_rooms)
	for room_name in room_count_by_type.keys():
		print("  %s: %d" % [room_name, room_count_by_type[room_name]])
	print("\n--Room Positions--")
	for room_name in room_positions_by_name.keys():
		print("%s positions:" % room_name)
		for pos in room_positions_by_name[room_name]:
			print(pos)
	print("===END ROOM SUMMARY===\n")

func print_cancelled():
	print("Generation cancelled!")

func print_finished():
	print("Generation finished!")
#endregion
