@tool
extends EditorPlugin

const MAYA_PORT = 55432
const GODOT_PORT = 55431

var listener: TCPServer
var client: StreamPeerTCP
var thread: Thread

func _enter_tree():
	print("Godot Bridge Plugin: Starting listener on port %d..." % GODOT_PORT)
	listener = TCPServer.new()
	var result := listener.listen(GODOT_PORT)
	if result != OK:
		push_error("Failed to start TCP listener on port %d" % GODOT_PORT)
		return
	thread = Thread.new()
	thread.start(Callable(self, "_poll_socket"))

func _exit_tree():
	print("Godot Bridge Plugin: Shutting down.")
	if thread:
		thread.wait_to_finish()
		thread = null
	if client:
		client.close()
		client = null
	if listener:
		listener.stop()

func _poll_socket():
	print("Godot Bridge Plugin: Polling socket...")
	while listener.is_listening():
		if listener.is_connection_available():
			print("Client connected.")
			client = listener.take_connection()
			var msg = client.get_utf8_string(client.get_available_bytes())
			print("Raw message received:\n", msg)

			var data = JSON.parse_string(msg)
			if typeof(data) != TYPE_DICTIONARY:
				push_warning("Invalid JSON format or not a dictionary.")
				continue

			var name = data.get("name", "Mesh")
			var vertices = to_vec3_array(data.get("vertices", []))
			var uvs = to_vec2_array(data.get("uvs", []))
			var indices = PackedInt32Array(data.get("indices", []))
			
			print("Parsed mesh data — Name: %s | Vertices: %d | UVs: %d | Indices: %d" %
				[name, vertices.size(), uvs.size(), indices.size()])
			
			var mesh_node = build_mesh(name, vertices, uvs, indices)
			var scene = get_editor_interface().get_edited_scene_root()
			
			print(scene)
			if scene:
				print("ADDING NOW!!!!")
				scene.add_child(mesh_node)
				mesh_node.set_owner(scene)
				print("Mesh added to scene: ", scene.name)
			else:
				push_warning("No edited scene root — cannot add mesh.")

		OS.delay_msec(100)

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
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 0)
	mesh.surface_set_material(0, material)

	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	return instance
