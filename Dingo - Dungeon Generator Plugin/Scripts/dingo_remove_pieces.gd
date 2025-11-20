@tool
extends Node3D
##This script controls what mesh variations should be removed, it contains functions to remove
##all children (for building room structures) and hiding randomized variations 
##(for placing randomized meshes) 

#region REMOVE FUNCTIONS CALLERS
#===REMOVE ALL CHILDREN=========================================================
#removes all children
func remove_wall_up():
	remove_all_children(get_node_or_null("wall_up"))

func remove_wall_down():
	remove_all_children(get_node_or_null("wall_down"))

func remove_wall_left():
	remove_all_children(get_node_or_null("wall_left"))

func remove_wall_right():
	remove_all_children(get_node_or_null("wall_right"))

func remove_door_up():
	remove_all_children(get_node_or_null("door_up"))

func remove_door_down():
	remove_all_children(get_node_or_null("door_down"))

func remove_door_left():
	remove_all_children(get_node_or_null("door_left"))

func remove_door_right():
	remove_all_children(get_node_or_null("door_right"))

#===KEEP RANDOM CHILD===========================================================
#hides all children but one
func keep_random_wall_up():
	keep_one_random_child(get_node_or_null("wall_up"))

func keep_random_wall_down():
	keep_one_random_child(get_node_or_null("wall_down"))

func keep_random_wall_left():
	keep_one_random_child(get_node_or_null("wall_left"))

func keep_random_wall_right():
	keep_one_random_child(get_node_or_null("wall_right"))

func keep_random_door_up():
	keep_one_random_child(get_node_or_null("door_up"))

func keep_random_door_down():
	keep_one_random_child(get_node_or_null("door_down"))

func keep_random_door_left():
	keep_one_random_child(get_node_or_null("door_left"))

func keep_random_door_right():
	keep_one_random_child(get_node_or_null("door_right"))

func keep_random_floor():
	keep_one_random_child(get_node_or_null("floor"))

func keep_random_ceiling():
	keep_one_random_child(get_node_or_null("ceiling"))
#endregion

#region REMOVE HELPER FUNCTIONS
#===REMOVE FUNCTIONS============================================================

#remove all immediate children (mesh variations)
func remove_all_children(node: Node):
	if not node:
		return
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

#keep one random child & hide the others
func keep_one_random_child(node: Node):
	if not node:
		return
	var children = node.get_children()
	var count = children.size()
	if count == 0:
		return
	#count children & choose random index, loop through & unhide chosen one
	var keep_index = randi() % count
	for i in range(children.size()):
		if i == keep_index:
			children[i].visible = true
		else:
			children[i].visible = false
#endregion
