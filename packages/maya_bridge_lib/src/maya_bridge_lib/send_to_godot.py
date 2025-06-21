import socket
import json
from maya.api import OpenMaya as om
from typing import Optional
from maya import cmds

GODOT_HOST = "127.0.0.1"
GODOT_PORT = 55431

def main():
    payload = build_mesh_payload()
    send_payload_to_godot(payload)

def get_mesh_data_from_name(node_name: str):
    sel = om.MSelectionList()
    sel.add(node_name)
    dag = sel.getDagPath(0)
    return get_mesh_data_from_dag(dag)

def get_mesh_data_from_dag(dag_path: om.MDagPath):
    mesh = om.MFnMesh(dag_path)

    vertices = [list(p) for p in mesh.getPoints(om.MSpace.kWorld)]
    normals = [list(n) for n in mesh.getNormals(om.MSpace.kWorld)]
    u_array, v_array = mesh.getUVs()
    uvs = list(zip(u_array, v_array))

    triangles = []
    face_iterator = om.MItMeshPolygon(dag_path)
    while not face_iterator.isDone():
        _, ids = face_iterator.getTriangles()
        face_verts = face_iterator.getVertices()
        full_to_relative = {v: idx for idx, v in enumerate(face_verts)}
        for i in range(0, len(ids), 3):
            triangle = []
            triangle_vertex_ids = ids[i:i+3]
            for vertex_id in triangle_vertex_ids:
                relative_idx = full_to_relative[vertex_id]
                uv = face_iterator.getUVIndex(relative_idx)
                normal = face_iterator.normalIndex(relative_idx)
                triangle.append({
                    "v": vertex_id,
                    "uv": uv,
                    "n": normal
                })
            triangles.append(triangle)
        face_iterator.next()
        
    return {
        "vertices": vertices,
        "uvs": uvs,
        "normals": normals,
        "triangles": triangles
    }


def send_payload_to_godot(payload: dict):
    data = json.dumps(payload)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((GODOT_HOST, GODOT_PORT))
        s.sendall(data.encode("utf-8"))

def get_node_type(node: Optional[str]):
    if cmds.nodeType(node) == 'transform':
        if children := cmds.listRelatives(node, children=True, shapes=True, fullPath=True):
            return cmds.nodeType(children[0])
    return cmds.nodeType(node)

def get_material_color_from_mesh(node_name: str):
    shapes = cmds.listRelatives(node_name, shapes=True, fullPath=True) or []
    for shape in shapes:
        sg_nodes = cmds.listConnections(shape, type='shadingEngine') or []
        for sg in sg_nodes:
            shaders = cmds.listConnections(f'{sg}.surfaceShader', destination=False) or []
            for shader in shaders:
                if cmds.nodeType(shader) == 'usdPreviewSurface' and cmds.objExists(f'{shader}.diffuseColor'):
                    return cmds.getAttr(f'{shader}.diffuseColor')[0]
    return [0.5, 0.5, 0.5]


def build_mesh_payload():
    selection = cmds.ls(selection=True, long=True)
    node_type = None if not selection else selection[0]

    if len(selection) != 1 and get_node_type(selection[0]) != "mesh":
        return
    
    node = selection[0]
    short_name = node.split('|')[-1]

    payload = {
        "name": short_name,
        "type": "mesh",
        "mesh_data": get_mesh_data_from_name(node),
        "material_color": get_material_color_from_mesh(node)
    }
    return payload