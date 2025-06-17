@tool
extends EditorPlugin

var listener := TCPServer.new()
var client: StreamPeerTCP
var thread: Threa

const GODOT_PORT = 55431

func _enter_tree():
	if listener.listen(GODOT_PORT) != OK:
		push_error("Failed to start TCP listener")
		return
	thread = Thread.new()
	thread.start(Callable(self, "_poll_socket"))

func _exit_tree():
	if thread:
		thread.wait_to_finish()
		thread = null
	if client:
		client.close()
		client = null
	if listener.is_listening():
		listener.stop()

func _poll_socket():
	while listener.is_listening():
		if listener.is_connection_available():
			client = listener.take_connection()
			var msg = client.get_utf8_string(client.get_available_bytes())
			var data = JSON.parse_string(msg)
			if typeof(data) == TYPE_DICTIONARY:
				call_deferred("_add_node_to_scene", data)
			else:
				push_warning("Invalid JSON received")
		OS.delay_msec(100)
		
		
func _add_node_to_scene(data: Dictionary) -> void:
	var scene_root = get_editor_interface().get_edited_scene_root()
	if not scene_root:
		push_warning("No scene open")
		return

	var vertices = to_vec3_array(data.get("vertices", []))
	var uvs = to_vec2_array(data.get("uvs", []))
	var indices = PackedInt32Array(data.get("indices", []))
	var name = data.get("name", "Mesh")

	var mesh_instance = build_mesh(name, vertices, uvs, indices)
	scene_root.add_child(mesh_instance)
	mesh_instance.set_owner(scene_root)

func to_vec3_array(arr: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for v in arr:
		if v.size() == 3:
			result.append(Vector3(v[0], v[1], v[2]))
		else:
			push_warning("Invalid Vector3 format: %s" % v)
	return result

func to_vec2_array(arr: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for v in arr:
		if v.size() == 2:
			result.append(Vector2(v[0], v[1]))
		else:
			push_warning("Invalid Vector2 format: %s" % v)
	return result

func build_mesh(name: String, vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays = []
	var normals = compute_flat_normals(vertices, indices)
	
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 0)
	mesh.surface_set_material(0, material)

	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance

func compute_flat_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i + 1]
		var i2 = indices[i + 2]
		var v0 = vertices[i0]
		var v1 = vertices[i1]
		var v2 = vertices[i2]
		var normal = Plane(v0, v1, v2).normal
		normals[i0] = normal
		normals[i1] = normal
		normals[i2] = normal
	return normals
