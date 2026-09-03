#!/usr/bin/env python3
"""Reads the axis-aligned boxes out of a blockout glTF.

The parking blockout leaves Blender merged per material - every pillar, every wall segment and
every floor slab of one material lands in a single mesh - so the scene generator has no idea
where the solid parts of the level actually are, and props end up inside pillars or a metre
under a raised floor. This walks the mesh, splits it into connected components (a box shares no
vertices with its neighbours coming out of Blender) and hands back one world-space box each.

Only useful for a blockout of axis-aligned boxes, which is exactly what the garage is.
"""
import json
import struct
from pathlib import Path

COMPONENT_TYPE_FORMAT = {5121: "B", 5123: "H", 5125: "I"}


class Box:
    __slots__ = ("mesh", "low", "high")

    def __init__(self, mesh: str, low: list[float], high: list[float]) -> None:
        self.mesh = mesh
        self.low = low
        self.high = high

    @property
    def size(self) -> tuple[float, float, float]:
        return tuple(self.high[i] - self.low[i] for i in range(3))

    def top(self) -> float:
        return self.high[1]

    # Inflated in X/Z only: a prop standing on a slab must not count as intersecting it.
    def overlaps_column(self, x: float, z: float, radius: float) -> bool:
        return (self.low[0] - radius <= x <= self.high[0] + radius
                and self.low[2] - radius <= z <= self.high[2] + radius)

    def covers(self, x: float, z: float) -> bool:
        return self.low[0] <= x <= self.high[0] and self.low[2] <= z <= self.high[2]

    def __repr__(self) -> str:
        return "Box(%s, x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f])" % (
            self.mesh, self.low[0], self.high[0], self.low[1], self.high[1], self.low[2], self.high[2])


def _read_accessor(gltf: dict, buffer: bytes, index: int) -> list:
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    if accessor["type"] == "VEC3":
        stride = view.get("byteStride") or 12
        return [struct.unpack_from("<3f", buffer, start + i * stride) for i in range(accessor["count"])]
    code = COMPONENT_TYPE_FORMAT[accessor["componentType"]]
    size = struct.calcsize(code)
    stride = view.get("byteStride") or size
    return [struct.unpack_from("<" + code, buffer, start + i * stride)[0] for i in range(accessor["count"])]


def _find(parent: list[int], item: int) -> int:
    while parent[item] != item:
        parent[item] = parent[parent[item]]
        item = parent[item]
    return item


def boxes(gltf_path: str | Path) -> list[Box]:
    path = Path(gltf_path)
    gltf = json.loads(path.read_text(encoding="utf-8"))
    buffer = (path.parent / gltf["buffers"][0]["uri"]).read_bytes()
    result: list[Box] = []
    for node in gltf["nodes"]:
        if "mesh" not in node:
            continue
        # Rotated nodes exist (the services duct), but they are not solid and not wanted here.
        if node.get("rotation") not in (None, [0.0, 0.0, 0.0, 1.0]):
            continue
        offset = node.get("translation", [0.0, 0.0, 0.0])
        for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
            positions = _read_accessor(gltf, buffer, primitive["attributes"]["POSITION"])
            indices = _read_accessor(gltf, buffer, primitive["indices"])
            # Welded by position, not by index. Blender splits vertices per face for flat
            # shading, so index connectivity alone would return one component per quad, while
            # merging by touching bounds would fuse the four perimeter walls into one box
            # covering the whole interior.
            welded: dict[tuple[float, float, float], int] = {}
            vertex_group: list[int] = []
            for point in positions:
                key = (round(point[0], 5), round(point[1], 5), round(point[2], 5))
                vertex_group.append(welded.setdefault(key, len(welded)))
            parent = list(range(len(welded)))
            for triangle in range(0, len(indices), 3):
                a = vertex_group[indices[triangle]]
                for corner in (1, 2):
                    b = vertex_group[indices[triangle + corner]]
                    root_a, root_b = _find(parent, a), _find(parent, b)
                    if root_a != root_b:
                        parent[root_b] = root_a
            groups: dict[int, list[int]] = {}
            for vertex in range(len(positions)):
                groups.setdefault(_find(parent, vertex_group[vertex]), []).append(vertex)
            for members in groups.values():
                low = [min(positions[v][i] for v in members) + offset[i] for i in range(3)]
                high = [max(positions[v][i] for v in members) + offset[i] for i in range(3)]
                result.append(Box(node["name"], low, high))
    return result


def bounds(gltf_path: str | Path) -> tuple[list[float], list[float]]:
    """World-space AABB of a whole glTF, node transforms applied.

    Used on the props: how tall a crate is decides nothing, but how wide it is decides whether it
    fits between two pillars, and where its lowest point sits decides whether it floats.
    """
    path = Path(gltf_path)
    gltf = json.loads(path.read_text(encoding="utf-8"))
    buffer = (path.parent / gltf["buffers"][0]["uri"]).read_bytes()
    low = [float("inf")] * 3
    high = [float("-inf")] * 3

    def matrix(node: dict) -> list[list[float]]:
        if "matrix" in node:
            m = node["matrix"]
            return [[m[0], m[4], m[8], m[12]], [m[1], m[5], m[9], m[13]], [m[2], m[6], m[10], m[14]]]
        translation = node.get("translation", [0.0, 0.0, 0.0])
        scale = node.get("scale", [1.0, 1.0, 1.0])
        x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        rotation = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
        return [[rotation[i][j] * scale[j] for j in range(3)] + [translation[i]] for i in range(3)]

    def combine(outer: list[list[float]], inner: list[list[float]]) -> list[list[float]]:
        return [[sum(outer[i][k] * inner[k][j] for k in range(3)) for j in range(3)]
                + [sum(outer[i][k] * inner[k][3] for k in range(3)) + outer[i][3]] for i in range(3)]

    def walk(index: int, parent: list[list[float]]) -> None:
        node = gltf["nodes"][index]
        world = combine(parent, matrix(node))
        if "mesh" in node:
            for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                accessor = gltf["accessors"][primitive["attributes"]["POSITION"]]
                # Every exporter writes min/max on a POSITION accessor, so the corners are
                # enough and the vertex data never has to be touched.
                corner_low, corner_high = accessor.get("min"), accessor.get("max")
                if corner_low is None or corner_high is None:
                    continue
                for cx in (corner_low[0], corner_high[0]):
                    for cy in (corner_low[1], corner_high[1]):
                        for cz in (corner_low[2], corner_high[2]):
                            for axis in range(3):
                                value = (world[axis][0] * cx + world[axis][1] * cy
                                         + world[axis][2] * cz + world[axis][3])
                                low[axis] = min(low[axis], value)
                                high[axis] = max(high[axis], value)
        for child in node.get("children", []):
            walk(child, world)

    identity = [[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0]]
    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        walk(root, identity)
    return low, high


if __name__ == "__main__":
    import sys
    source = sys.argv[1] if len(sys.argv) > 1 else "assets/environment/parking/parking_garage.gltf"
    found = boxes(source)
    print("%d boxes" % len(found))
    for box in sorted(found, key=lambda b: (b.mesh, b.low[0], b.low[2])):
        print("  %-16s x[%7.2f,%7.2f] y[%6.2f,%6.2f] z[%7.2f,%7.2f]  size %5.2f x %5.2f x %5.2f" % (
            box.mesh, box.low[0], box.high[0], box.low[1], box.high[1], box.low[2], box.high[2],
            box.size[0], box.size[1], box.size[2]))
