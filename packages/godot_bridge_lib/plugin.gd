@tool
extends EditorPlugin

var listener := TCPServer.new()
var client: StreamPeerTCP
var thread: Thread

const GODOT_PORT = 55431

func _enter_tree():
	print("Godot Plugin: Starting listener on port %d..." % GODOT_PORT)
	if listener.listen(GODOT_PORT) != OK:
		push_error("Failed to start TCP listener")
		return
	thread = Thread.new()
	thread.start(Callable(self, "_poll_socket"))

func _exit_tree():
	print("Godot Plugin: Cleaning up listener and thread...")
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
			print("Godot Plugin: Connection accepted.")
			client = listener.take_connection()
			var msg = client.get_utf8_string(client.get_available_bytes())
			var data = JSON.parse_string(msg)
			if typeof(data) == TYPE_DICTIONARY:
				call_deferred("_add_payload_to_scene", data)
			else:
				push_warning("Invalid JSON received")
		OS.delay_msec(100)

func _add_payload_to_scene(data: Dictionary) -> void:
	print("Godot Plugin: Adding payload to scene...")
	var scene_root = get_editor_interface().get_edited_scene_root()
	if not scene_root:
		push_warning("No scene open.")
		return

	var mesh_name = data.get("name", "ImportedMesh")
	var mesh_data = data.get("mesh_data", {})
	var material_color = data.get("material_color", [0.4, 0.4, 0.4])
	if mesh_data.is_empty():
		push_warning("No mesh_data in payload.")
		return

	var mesh_instance = _build_mesh(mesh_name, mesh_data)
	_create_material(mesh_instance, material_color)

	scene_root.add_child(mesh_instance)
	mesh_instance.set_owner(scene_root)
	print("MeshInstance3D added to scene.")

func _build_mesh(name: String, data: Dictionary) -> MeshInstance3D:
	print("Godot Plugin: Building mesh...")

	var index_map = {}
	var unique_vertices = []
	var final_uvs = []
	var final_normals = []

	var vertices = PackedVector3Array()
	for v in data["vertices"]:
		vertices.append(Vector3(v[0], v[1], v[2]))
	print("Parsed %d vertices." % vertices.size())

	var uvs = PackedVector2Array()
	for uv in data["uvs"]:
		uvs.append(Vector2(uv[0], uv[1]))
	print("Parsed %d UVs." % uvs.size())

	var normals = PackedVector3Array()
	for n in data["normals"]:
		normals.append(Vector3(n[0], n[1], n[2]))
	print("Parsed %d normals." % normals.size())

	var indices = PackedInt32Array()

	for t_idx in data["triangles"].size():
		var tri = data["triangles"][t_idx]
		if tri.size() != 3:
			push_warning("Triangle %d does not have 3 vertices." % t_idx)
			continue
		var reversed = [tri[0], tri[2], tri[1]]
		for p in reversed:
			if not p.has("v") or not p.has("uv"):
				push_warning("Missing v or uv in triangle point.")
				continue
			var idx = _get_or_add_index(p["v"], p["uv"], p["n"], vertices, uvs, normals, unique_vertices, final_uvs, final_normals, index_map)
			indices.append(idx)

	print("Final unique vertices: %d" % unique_vertices.size())
	print("Final indices: %d" % indices.size())

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(unique_vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(final_normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(final_uvs)
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	print("Mesh created with 1 surface.")

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = mesh
	return mesh_instance

func _create_material(mesh_instance: MeshInstance3D, material_color):
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(material_color[0], material_color[1], material_color[2])
	mesh_instance.mesh.surface_set_material(0, material)
	return material

func _get_or_add_index(v_id, uv_id, n_id, vertices, uvs, normals, unique_vertices, final_uvs, final_normals, index_map):
	var key = "%s|%s|%s" % [v_id, uv_id, n_id]
	if index_map.has(key):
		return index_map[key]
	if v_id >= vertices.size() or uv_id >= uvs.size() or n_id >= normals.size():
		push_warning("Invalid index in mesh data: v=%d uv=%d n=%d" % [v_id, uv_id, n_id])
		return 0
	var i = unique_vertices.size()
	unique_vertices.append(vertices[v_id])
	final_uvs.append(uvs[uv_id])
	final_normals.append(normals[n_id])
	index_map[key] = i
	return i
