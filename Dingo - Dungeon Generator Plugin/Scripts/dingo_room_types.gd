@tool
extends Resource
class_name RoomType
##This script holds variables for room types & customizes the inspector to change dynamically based
##on what modes are selected, it also contains helper functions for generating rooms

#region VARIABLES
#===BASIC CUSTOMIZATION VARS====================================================

#the name of the type of room
var name: String = ""
#the priority to generate this type of room (0 is highest priority)
var priority: = 1
#the amount of rooms to generate
var room_amount: int = 5
#the amount of times a room will try to find a spot 
var recursion: int = 10
#the ID from the mesh library to be used
var tile_id: int = 3
#how close the rooms can be to eachother
var room_margin: int = 1


#===SCENE MODES VARS============================================================

#SCENE MODES (Static & dynamic)
#statically placed scenes are for prebuilt rooms
#dynamically placed scenes are for dynamically built rooms
var scene_index : int = 0
enum SceneMode { STATIC, DYNAMIC }
var scene_mode: SceneMode = SceneMode.DYNAMIC:
	set(value):
		scene_mode = value
		notify_property_list_changed()
var static_scenes : Array[PackedScene] = []
var dynamic_scenes : Array[PackedScene] = []

#DOOR MODES (Static & dynamic)
#statically placed doors are helpful for prebuilt rooms 
#dynamically placed doors are randomly placed
enum DoorMode { STATIC, DYNAMIC }
var door_mode: DoorMode = DoorMode.DYNAMIC:
	set(value):
		door_mode = value
		notify_property_list_changed()
var static_doors : Array[Vector3i] = []

#PLACEMENT MODES (Static dynamic & ranged) 
#static placement places rooms at specific coordinates
#dynamic placement places rooms in a random location within the area
#ranged placement places rooms within a defined range within the area
enum PlacementMode { STATIC, DYNAMIC, RANGED }
var placement_mode: PlacementMode = PlacementMode.DYNAMIC:
	set(value):
		placement_mode = value
		notify_property_list_changed()
var static_positions: Array[Vector3i] = []
var range_min: Vector3i = Vector3i.ZERO
var range_max: Vector3i = Vector3i(10, 0, 10)

#SIZE(Static & dynamic) 
#static sizes nodes specific dimensions
#dynamic sizes nodes within a defined range 
enum SizeMode { STATIC, DYNAMIC }
var size_mode: SizeMode = SizeMode.DYNAMIC:
	set(value):
		size_mode = value
		notify_property_list_changed()
var static_sizes: Array[Vector3i] = []
var min_size: Vector3i = Vector3i(2, 1, 2)
var max_size: Vector3i = Vector3i(4, 1, 4)
#endregion

#region INSPECTOR SETUP
#this customizes the inspector & shows/hides properties depending on selected modes
#called when inspector is displayed 
func _get_property_list() -> Array:
	var props: Array = []
#===SCENE MODE INSPECTOR SETUP==================================================
	#each dictionary is a property in the inspector
	props.append({
		"name" : "scene_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Static,Dynamic"
	})
	match scene_mode:
		SceneMode.STATIC:
			props.append({
				"name": "static_scenes",
				"type": TYPE_ARRAY,
				"hint": PROPERTY_HINT_TYPE_STRING,
				"hint_string": "PackedScene",
				"default_value": []
			})
		SceneMode.DYNAMIC:
			props.append({
				"name": "dynamic_scenes",
				"type": TYPE_ARRAY,
				"hint": PROPERTY_HINT_TYPE_STRING,
				"hint_string": "PackedScene",
				"default_value": []
			})
	#===BASIC CUSTOMIZATION INSPECTOR SETUP=====================================
	#basic customization
	props.append({ "name": "name", "type": TYPE_STRING })
	props.append({ "name": "priority", "type": TYPE_INT })
	props.append({ "name": "room_amount", "type": TYPE_INT })
	props.append({ "name": "recursion", "type": TYPE_INT })
	props.append({ "name": "tile_id", "type": TYPE_INT })
	props.append({ "name": "room_margin", "type": TYPE_INT })
	
	#===DOOR MODE INSPECTOR SETUP===============================================
	props.append({
		"name" : "door_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Static,Dynamic"
	})
	match door_mode:
		DoorMode.STATIC:
			props.append({"name": "static_doors", "type": TYPE_ARRAY })
	
	#===PLACEMENT MODE INSPECTOR SETUP==========================================
	props.append({
		"name": "placement_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Static,Dynamic,Ranged"
	})
	match placement_mode:
		PlacementMode.STATIC:
			props.append({ "name": "static_positions", "type": TYPE_ARRAY })
		PlacementMode.RANGED:
			props.append({ "name": "range_min", "type": TYPE_VECTOR3I })
			props.append({ "name": "range_max", "type": TYPE_VECTOR3I })
	
	#===SIZE MODE INSPECTOR SETUP==============================================
	props.append({
		"name": "size_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Static,Dynamic"
	})
	match size_mode:
		SizeMode.STATIC:
			props.append({ "name": "static_sizes", "type": TYPE_ARRAY })
		SizeMode.DYNAMIC:
			props.append({ "name": "min_size", "type": TYPE_VECTOR3I })
			props.append({ "name": "max_size", "type": TYPE_VECTOR3I })
			
	return props
#endregion

#region HELPER FUNCTIONS
#===HELPER FUNCTIONS============================================================
#returns static door positions
func get_door_positions() -> Array[Vector3i]:
	return static_doors

#returns room positions depending on the placement mode
func get_room_positions(area_size: Vector3i) -> Array[Vector3i]:
	match placement_mode:
		#returns set static position
		PlacementMode.STATIC:
			return static_positions
		PlacementMode.RANGED:
			#returns position within range
			return [Vector3i(
				randi_range(range_min.x, range_max.x),
				0,
				randi_range(range_min.z, range_max.z)
			)]
		_:
			#returns position within area
			return [Vector3i(
				randi_range(0, area_size.x - 1),
				0,
				randi_range(0, area_size.z - 1)
			)]

#returns size depending on the size mode
func get_room_size() -> Vector3i:
	match size_mode:
		SizeMode.STATIC:
			#return defined sizes
			if static_sizes.size() > 0:
				return static_sizes.pick_random()
			return Vector3i(3, 1, 3)
		_:
			#return size within range
			return Vector3i(
				randi_range(min_size.x, max_size.x),
				1,
				randi_range(min_size.z, max_size.z)
			)

#gets room size then places tiles within rectangle 
func make_room(grid_map: GridMap, start_pos: Vector3i) -> void:
	var size = get_room_size()
	for x in range(size.x):
		for z in range(size.z):
			grid_map.set_cell_item(start_pos + Vector3i(x, 0, z), tile_id)

#get next scene in array (for room mesh)
func get_next_scene() -> PackedScene:
	#use static or dynamic
	var arr: Array = static_scenes if scene_mode == SceneMode.STATIC else dynamic_scenes
	if arr.is_empty():
		return null
	scene_index = int(scene_index)
	#get next scene
	var scene = arr[scene_index % arr.size()]
	scene_index += 1
	return scene
#endregion
