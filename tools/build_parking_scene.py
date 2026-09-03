#!/usr/bin/env python3
"""Writes scenes/levels/parking_garage.tscn.

The level is a generated file rather than a hand-placed one: forty props, a dozen cars and
twenty-odd lights are not worth dragging around by hand, and a seeded layout can be re-rolled
without losing the tuning. The output is a normal Godot scene - open it, move anything, save.

Where things may stand is not guessed at: tools/blockout_boxes.py reads the real boxes out of the
glTF and tools/prop_layout.py rejects any position that is inside a pillar, across a doorway or
straddling the edge of the raised dock, then reports the floor height so nothing floats.

Usage: python3 tools/build_parking_scene.py [seed]
"""
import math
import random
import sys
from pathlib import Path

import blockout_boxes
from prop_layout import Footprint, Layout, Placer, PropShape

ROOT = Path(__file__).resolve().parent.parent
SCENE = ROOT / "scenes/levels/parking_garage.tscn"
GARAGE_GLTF = "assets/environment/parking/parking_garage.gltf"

# Geometry constants have to match tools' Blender blockout (see the .blend beside the glTF).
PARK_X, PARK_Y, PARK_H = 60.0, 40.0, 3.1
ANNEX_X, ANNEX_H = 26.0, 3.0
ANNEX_X0 = PARK_X * 0.5 + 0.3
CORRIDOR_X = ANNEX_X0 + 6.0
ANNEX_CX = ANNEX_X0 + ANNEX_X * 0.5

TEXTURES = {
    "floor_damaged": "concrete_floor_damaged_01",
    "concrete_layers": "concrete_layers",
    "plaster": "worn_plaster_wall",
    # Second sets, blended in over large patches by shaders/dev_grid.gdshader: patched pour on the
    # deck, old tiling left in the back-of-house rooms, plaster come off over brick.
    "tile": "worn_tile_floor",
    "brick": "brick_wall_006",
    "concrete_wall": "concrete_wall_008",
}
PROPS = {
    "car": "assets/props/covered_car_1k/covered_car_1k.gltf",
    "cardboard": "assets/props/cardboard_box_01_1k/cardboard_box_01_1k.gltf",
    "barrel": "assets/props/barrel_03_1k/barrel_03_1k.gltf",
    "cement": "assets/props/cement_bag_1k/cement_bag_1k.gltf",
    "ladder": "assets/props/ladder_sectioned_01_1k/ladder_sectioned_01_1k.gltf",
    "toolchest": "assets/props/metal_tool_chest_1k/metal_tool_chest_1k.gltf",
    "container": "assets/props/industrial_pastic_container_1k/industrial_pastic_container_1k.gltf",
    "cart": "assets/props/industrial_storage_cart_1k/industrial_storage_cart_1k.gltf",
    "crate": "assets/props/old_military_crate_1k/old_military_crate_1k.gltf",
    "barrier": "assets/props/concrete_road_barrier_1k/concrete_road_barrier_1k.gltf",
    "fence": "assets/props/modular_chainlink_fence_1k/modular_chainlink_fence_1k.gltf",
    "shelves": "assets/props/painted_wooden_shelves_1k/painted_wooden_shelves_1k.gltf",
    "extinguisher": "assets/props/korean_fire_extinguisher_01_1k/korean_fire_extinguisher_01_1k.gltf",
}
# Doorway openings through the two annex partitions, from the box extraction: 2.6 m wide gaps
# under a lintel at 2.15 m. Left walkable - the shutters went on the vehicle entrance instead.
DOOR_Z = [-18.7, -10.7, -2.7, 5.3, 13.3]
# Props big enough to hide behind get a body; the rest are dressing and stay walk-through.
COVER = {"car", "barrel", "container", "crate", "barrier", "shelves", "cart", "fence", "toolchest"}

# Regions the blockout leaves open, measured off the box extraction rather than guessed:
# the deck, the hall along the annex's west edge, the service corridor between the two
# partitions, and the storerooms east of it. Each one is already inset off its walls.
DECK = (-29.4, 29.4, -19.4, 19.4)
ANNEX_HALL = (30.9, 34.5, -19.4, 19.4)
CORRIDOR = (35.6, 37.0, -19.4, 19.4)
# The rooms in z order. The blockout's cross walls sit at z = -8, 0, 8 and 16, and the doorways
# through the x = 37.6 partition serve the first four. The strip beyond z = 16 has no door at
# all, so nothing is put in it - it cannot be reached or seen into.
ROOMS = [
    (38.4, 55.6, -19.2, -8.7),
    (38.4, 55.6, -7.4, -0.8),
    (38.4, 55.6, 0.8, 7.4),
    (38.4, 55.6, 8.8, 15.5),
]
# The 10 x 6 m loading dock inside the first room, 1.1 m up. Props here are placed on top of it.
DOCK = (43.0, 51.6, -18.4, -13.6)
RIGHT_ANGLES = [0.0, math.pi * 0.5, math.pi, math.pi * 1.5]


def yaw(angle: float, position: tuple[float, float, float], scale: float = 1.0) -> str:
    c, s = math.cos(angle) * scale, math.sin(angle) * scale
    return "Transform3D(%.4f, 0, %.4f, 0, %.4f, 0, %.4f, 0, %.4f, %.3f, %.3f, %.3f)" % (
        c, -s, scale, s, c, position[0], position[1], position[2])


def against_wall(placer: Placer, rng: random.Random, shape: PropShape,
                 region: tuple[float, float, float, float], count: int,
                 gap: float = 0.12) -> list[Footprint]:
    """Puts a prop's back against one of the region's four walls, facing into the room."""
    low_x, high_x, low_z, high_z = region
    made: list[Footprint] = []
    for _ in range(count):
        for _attempt in range(90):
            side = rng.randrange(4)
            # Facing into the room from that wall: the prop's depth runs along the wall normal.
            angle = RIGHT_ANGLES[side] + rng.uniform(-0.05, 0.05)
            if side == 0:
                x, z = low_x + shape.depth_along(angle, 0) + gap, rng.uniform(low_z, high_z)
            elif side == 1:
                x, z = rng.uniform(low_x, high_x), low_z + shape.depth_along(angle, 1) + gap
            elif side == 2:
                x, z = high_x - shape.depth_along(angle, 0) - gap, rng.uniform(low_z, high_z)
            else:
                x, z = rng.uniform(low_x, high_x), high_z - shape.depth_along(angle, 1) - gap
            spot = placer.accept(shape.footprint(x, z, angle))
            if spot is not None:
                made.append(spot)
                break
    return made


def main(seed: int = 7) -> int:
    rng = random.Random(seed)
    # The blockout's own boxes drive both the lights and the prop placement, so they are read
    # once here rather than guessed at twice.
    layout_boxes = blockout_boxes.boxes(ROOT / GARAGE_GLTF)
    ext: list[str] = []
    ids: dict[str, str] = {}

    def resource(kind: str, path: str, key: str) -> str:
        ident = "%d_%s" % (len(ext) + 1, key)
        ext.append('[ext_resource type="%s" path="res://%s" id="%s"]' % (kind, path, ident))
        ids[key] = ident
        return ident

    resource("PackedScene", "assets/environment/parking/parking_garage.gltf", "garage")
    resource("Script", "scripts/environment/photoreal_environment.gd", "env")
    resource("Script", "scripts/environment/level_mesh_collision.gd", "collision")
    resource("Script", "scripts/environment/surface_materials.gd", "surfaces")
    resource("Script", "scripts/environment/prop_body.gd", "propbody")
    resource("Shader", "shaders/dev_grid.gdshader", "grid")
    resource("Shader", "shaders/rain_puddles.gdshader", "puddles")
    resource("Script", "scripts/environment/fullscreen_mesh.gd", "fullscreen")
    resource("Shader", "shaders/graffiti.gdshader", "graffiti")
    resource("Shader", "shaders/bay_paint.gdshader", "baypaint")
    resource("PackedScene", "scenes/player/player.tscn", "player")
    for key, slug in TEXTURES.items():
        for suffix in ("diff", "nor_gl", "arm"):
            resource("Texture2D", "assets/polyhaven/textures/%s/%s_%s_2k.jpg" % (slug, slug, suffix),
                     "%s_%s" % (key, suffix))
    for key, path in PROPS.items():
        resource("PackedScene", path, "prop_" + key)

    subs: list[str] = []

    def surface(name: str, texture_key: str, scale: float, roughness: float, wetness: float,
                variant: str | None = None, amount: float = 0.0, patch: float = 9.0,
                variant_scale: float | None = None) -> str:
        subs.append("""[sub_resource type="ShaderMaterial" id="Material_%s"]
shader = ExtResource("%s")
shader_parameter/cell_color_a = Color(0.32, 0.32, 0.33, 1)
shader_parameter/cell_color_b = Color(0.26, 0.26, 0.27, 1)
shader_parameter/minor_line_color = Color(0.2, 0.2, 0.21, 1)
shader_parameter/major_line_color = Color(0.15, 0.15, 0.16, 1)
shader_parameter/cell_size = 1.0
shader_parameter/major_cells = 8.0
shader_parameter/minor_line_width = 0.016
shader_parameter/major_line_width = 0.04
shader_parameter/surface_roughness = %s
shader_parameter/wetness = %s
shader_parameter/texture_blend = 1.0
shader_parameter/texture_scale = %s
shader_parameter/normal_strength = 1.0
shader_parameter/albedo_texture = ExtResource("%s")
shader_parameter/normal_texture = ExtResource("%s")
shader_parameter/arm_texture = ExtResource("%s")
""" % (name, ids["grid"], roughness, wetness, scale,
            ids[texture_key + "_diff"], ids[texture_key + "_nor_gl"], ids[texture_key + "_arm"]))
        if variant is not None:
            # Appended to the block just written rather than pushed as a new one, so the
            # load_steps count in the header still matches the number of resources.
            subs[-1] += """shader_parameter/variant_amount = %s
shader_parameter/variant_patch_size = %s
shader_parameter/variant_scale = %s
shader_parameter/variant_albedo_texture = ExtResource("%s")
shader_parameter/variant_normal_texture = ExtResource("%s")
shader_parameter/variant_arm_texture = ExtResource("%s")
""" % (amount, patch, variant_scale if variant_scale is not None else scale,
                ids[variant + "_diff"], ids[variant + "_nor_gl"], ids[variant + "_arm"])
        return "Material_" + name

    # The second texture is what stops one tiling sheet from being the whole surface: patched
    # concrete on the deck, tiling left over in the back rooms, brick where the plaster came off.
    floor_material = surface("floor", "floor_damaged", 0.35, 0.72, 1.0,
                             variant="concrete_layers", amount=0.45, patch=11.0, variant_scale=0.4)
    annex_material = surface("annexfloor", "floor_damaged", 0.5, 0.75, 0.35,
                             variant="tile", amount=0.7, patch=6.5, variant_scale=0.55)
    concrete_material = surface("concrete", "concrete_layers", 0.4, 0.8, 0.15,
                                variant="concrete_wall", amount=0.5, patch=9.0, variant_scale=0.45)
    plaster_material = surface("plaster", "plaster", 0.45, 0.85, 0.0,
                               variant="brick", amount=0.4, patch=5.0, variant_scale=0.5)
    ceiling_material = surface("ceiling", "concrete_layers", 0.5, 0.85, 0.0)

    subs.append("""[sub_resource type="Environment" id="Environment_garage"]
background_mode = 0
background_color = Color(0.015, 0.017, 0.022, 1)
ambient_light_source = 2
ambient_light_color = Color(0.42, 0.46, 0.58, 1)
ambient_light_energy = 0.05
reflected_light_source = 1
tonemap_mode = 4
tonemap_exposure = 0.8
ssao_enabled = true
ssao_radius = 0.6
ssao_intensity = 1.7
ssil_enabled = true
ssr_enabled = true
ssr_max_steps = 64
ssr_fade_in = 0.1
ssr_depth_tolerance = 0.1
glow_enabled = true
glow_intensity = 0.55
glow_strength = 1.1
glow_bloom = 0.12
glow_blend_mode = 0
glow_hdr_threshold = 0.85
glow_hdr_scale = 2.4
fog_enabled = true
fog_light_color = Color(0.34, 0.35, 0.42, 1)
fog_density = 0.0012
volumetric_fog_enabled = true
volumetric_fog_density = 0.006
volumetric_fog_albedo = Color(0.82, 0.85, 0.95, 1)
volumetric_fog_anisotropy = 0.3
volumetric_fog_length = 55.0
volumetric_fog_gi_inject = 0.4
volumetric_fog_ambient_inject = 0.08
""")
    subs.append("""[sub_resource type="CameraAttributesPhysical" id="CameraAttributes_garage"]
auto_exposure_enabled = false
exposure_multiplier = 0.8
exposure_sensitivity = 160.0
""")
    subs.append("""[sub_resource type="ShaderMaterial" id="Material_puddles"]
shader = ExtResource("%s")
shader_parameter/puddle_color = Color(0.012, 0.014, 0.02, 0.82)
shader_parameter/puddle_reflectivness = 2.0
shader_parameter/puddle_micro_mask_size = 2.4
shader_parameter/puddle_macro_mask_size = 11.0
shader_parameter/puddle_mask_threshold = 0.46
shader_parameter/ssr_resolution = 0.35
shader_parameter/ssr_max_travel = 26.0
shader_parameter/ssr_max_diff = 0.6
shader_parameter/ssr_screen_border_fadeout = 0.2
shader_parameter/ripple_max_radius = 0.0
shader_parameter/ripple_scale = 0.5
shader_parameter/ripple_speed = 0.3
""" % ids["puddles"])

    nodes: list[str] = ['[node name="ParkingGarage" type="Node3D"]', ""]
    nodes.append("""[node name="PhotorealEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_garage")
camera_attributes = SubResource("CameraAttributes_garage")
script = ExtResource("%s")
use_hdr_panorama = false
sky_energy = 0.1
ambient_energy = 0.05
exposure_multiplier = 0.8
shaft_density = 0.006
fill_light_energy = 0.05
weather = 1
standing_water = 0.9
""" % ids["env"])
    nodes.append("""[node name="Garage" parent="." instance=ExtResource("%s")]
script = ExtResource("%s")
solid_mesh_names = PackedStringArray("Floor_Parking", "Floor_Annex", "Walls_Concrete", "Walls_Plaster", "Ceiling", "Entrance_Shutter")
""" % (ids["garage"], ids["collision"]))
    nodes.append("""[node name="Surfaces" type="Node3D" parent="Garage"]
script = ExtResource("%s")
materials = {
"Ceiling": SubResource("%s"),
"Floor_Annex": SubResource("%s"),
"Floor_Parking": SubResource("%s"),
"Walls_Concrete": SubResource("%s"),
"Walls_Plaster": SubResource("%s")
}
""" % (ids["surfaces"], ceiling_material, annex_material, floor_material, concrete_material, plaster_material))

    # ---- lights ------------------------------------------------------------------------
    # Every lamp is a baked light. The shell of the garage carries a lightmap (its glTF is
    # imported with UV2), the props are left out of the bake and read the probes instead, and
    # `shadowmask_mode` keeps the lamps lighting the player and the cars in real time while
    # their shadows on the concrete come from the bake. The bake itself is a button in the
    # editor - Godot does not expose it to scripting - so this only sets the scene up for it.
    lightmap = ROOT / "scenes/levels/parking_garage.lmbake"
    if lightmap.exists():
        resource("LightmapGIData", "scenes/levels/parking_garage.lmbake", "lightmap")
    nodes.append('[node name="Lights" type="Node3D" parent="."]\n')
    lamp = """[node name="%s" type="OmniLight3D" parent="Lights"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, %.2f, %.2f)
light_color = Color(%s)
light_energy = %s
light_volumetric_fog_energy = %s
light_specular = 0.5
shadow_enabled = %s
shadow_bias = 0.045
light_bake_mode = 1
omni_range = %s
omni_attenuation = 1.5
"""
    index = 0
    # One light per fixture in the blockout, taken off the geometry rather than typed in: the
    # deck has forty strips at 7.4 m spacing and the lights used to sit at four hand-written x
    # positions, so half the fixtures glowed without lighting anything and the last four metres
    # before each end wall were black.
    fixtures = [box for box in layout_boxes if box.mesh == "Fixtures"]
    fixtures.sort(key=lambda box: (round(box.low[0], 2), round(box.low[2], 2)))
    for box in fixtures:
        index += 1
        centre_x = (box.low[0] + box.high[0]) * 0.5
        centre_z = (box.low[2] + box.high[2]) * 0.5
        height = box.low[1] - 0.06
        if centre_x < PARK_X * 0.5:
            zone, colour, energy, fog, reach = "Deck", "0.85, 0.9, 1, 1", 3.4, 1.1, 13.0
        elif centre_x < CORRIDOR_X + 1.5:
            zone, colour, energy, fog, reach = "Corridor", "0.88, 0.92, 1, 1", 2.6, 1.0, 9.0
        else:
            zone, colour, energy, fog, reach = "Room", "1, 0.94, 0.82, 1", 2.6, 0.9, 9.0
        # Every third one casts shadows. All of them would mean fifty shadow cubemaps in the
        # atlas for a level where the light is meant to be flat and cheap anyway.
        shadowed = "true" if index % 3 == 1 else "false"
        nodes.append(lamp % ("%s%02d" % (zone, index), centre_x, height, centre_z,
                             colour, energy, fog, shadowed, reach))
    # Fill where the blockout has no fixture at all: the hall along the annex's west edge, and
    # the storeroom with the loading dock, whose only strip sits on the wall between two rooms.
    for fill_index, (x, z) in enumerate([(32.6, -16.0), (32.6, -8.0), (32.6, 0.0), (32.6, 8.0),
                                         (32.6, 16.0), (43.0, -15.0), (51.5, -14.0)]):
        nodes.append(lamp % ("AnnexFill%d" % fill_index, x, ANNEX_H - 0.35, z,
                             "0.9, 0.92, 0.98, 1", 2.3, 0.8, "false", 9.0))
    nodes.append(lamp % ("NeonAccent", -12.0, 1.95, 12.0, "0.98, 0.2, 0.62, 1", 6.5, 3.4, "false", 9.0))
    nodes.append(lamp % ("NeonAccent2", 18.0, 1.95, -14.0, "0.35, 0.55, 1, 1", 5.0, 3.0, "false", 8.0))
    nodes.append(lamp % ("ExitParking", 0.0, 2.45, -20.0, "1, 0.15, 0.1, 1", 3.0, 2.0, "false", 5.0))
    nodes.append(lamp % ("ExitAnnex", CORRIDOR_X, 2.4, 19.0, "1, 0.15, 0.1, 1", 2.6, 1.8, "false", 4.5))

    # ---- reflection probes ----------------------------------------------------------------
    # Screen-space reflections can only reflect what is already on screen, which is why the wet
    # floor lost the lamps as soon as they left the frame and banded at grazing angles. A grid of
    # box-projected probes gives the floor something to reflect everywhere; SSR then only refines
    # it up close. `interior` keeps the near-black sky out of the capture, and PhotorealEnvironment
    # hides every probe on the PERFORMANCE preset, so this costs nothing there.
    nodes.append('[node name="Reflections" type="Node3D" parent="."]\n')
    probe = """[node name="%s" type="ReflectionProbe" parent="Reflections"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, %.2f, %.2f)
update_mode = 0
intensity = 1.0
blend_distance = 2.0
max_distance = 44.0
size = Vector3(%.2f, %.2f, %.2f)
box_projection = true
interior = true
enable_shadows = true
"""
    probes = 0
    # Deck: overlapping boxes on a 15 x 13 m grid, sized larger than their spacing so the blend
    # bands meet instead of leaving seams between them.
    for column, centre_x in enumerate((-22.5, -7.5, 7.5, 22.5)):
        for row, centre_z in enumerate((-13.3, 0.0, 13.3)):
            probes += 1
            nodes.append(probe % ("Deck%d_%d" % (column, row), centre_x, PARK_H * 0.5, centre_z,
                                  17.0, PARK_H, 16.0))
    for index, centre_z in enumerate((-10.0, 10.0)):
        probes += 1
        nodes.append(probe % ("Hall%d" % index, 32.6, ANNEX_H * 0.5, centre_z, 5.0, ANNEX_H, 22.0))
        probes += 1
        nodes.append(probe % ("Corridor%d" % index, CORRIDOR_X, ANNEX_H * 0.5, centre_z,
                              2.6, ANNEX_H, 22.0))
    for index, room in enumerate(ROOMS):
        probes += 1
        centre_z = (room[2] + room[3]) * 0.5
        depth = room[3] - room[2] + 3.0
        nodes.append(probe % ("Room%d" % index, 47.0, ANNEX_H * 0.5, centre_z,
                              19.5, ANNEX_H, depth))
    print("placed %d reflection probes" % probes)

    # ---- cars, then everything else that stands on the floor ------------------------------
    layout = Layout(layout_boxes)
    shapes = {key: PropShape(*blockout_boxes.bounds(ROOT / path)) for key, path in PROPS.items()}
    placer = Placer(layout, rng)
    plan: list[tuple[str, Footprint]] = []

    def scatter(key: str, region: tuple[float, float, float, float], count: int,
                angles: list[float] | None = None) -> None:
        for _ in range(count):
            spot = placer.place(shapes[key], region, angles)
            if spot is not None:
                plan.append((key, spot))

    def line_up(key: str, region: tuple[float, float, float, float], count: int,
                gap: float = 0.12) -> None:
        for spot in against_wall(placer, rng, shapes[key], region, count, gap):
            plan.append((key, spot))

    def transform_of(key: str, spot: Footprint) -> str:
        x, z = spot.origin_xz()
        return yaw(spot.angle, (x, spot.y - shapes[key].base, z))

    # Cars first, because they claim the most floor and everything else has to fit around them:
    # nose-in along both long walls, then a few abandoned across the middle rows.
    nodes.append('[node name="Cars" type="Node3D" parent="."]\n')
    cars: list[Footprint] = []
    for wall_z, facing in ((-17.0, 0.0), (17.0, math.pi)):
        x = -26.0
        while x < 27.0:
            angle = facing + math.radians(rng.uniform(-6.0, 6.0))
            spot = placer.place_at(shapes["car"], x, wall_z + rng.uniform(-0.4, 0.4), angle,
                                   nudges=[(1.2, 0.0), (-1.2, 0.0), (2.4, 0.0), (0.0, 0.9)])
            if spot is not None:
                cars.append(spot)
            x += rng.uniform(6.2, 8.4)
    for row_z in (-13.4, -4.6, 4.6, 13.4):
        angle = math.pi * 0.5 + math.radians(rng.uniform(-24.0, 24.0))
        spot = placer.place(shapes["car"], (-25.0, 25.0, row_z - 0.9, row_z + 0.9), [angle])
        if spot is not None:
            cars.append(spot)
    for number, spot in enumerate(cars):
        nodes.append("""[node name="Car%02d" type="StaticBody3D" parent="Cars"]
transform = %s
script = ExtResource("%s")

[node name="Model" parent="Cars/Car%02d" instance=ExtResource("%s")]
""" % (number, transform_of("car", spot), ids["propbody"], number, ids["prop_car"]))

    # ---- props: storerooms, corridor and deck clutter -----------------------------------
    nodes.append('[node name="Props" type="Node3D" parent="."]\n')
    # Storerooms: shelving against the walls, then stock on the floor in front of it.
    for room in ROOMS:
        line_up("shelves", room, rng.randint(2, 4))
        scatter("cardboard", room, rng.randint(3, 5))
        scatter("crate", room, rng.randint(1, 2), RIGHT_ANGLES)
        scatter("container", room, rng.randint(1, 3))
        scatter("cement", room, rng.randint(1, 3))
        scatter("barrel", room, rng.randint(1, 2))
    line_up("toolchest", ROOMS[1], 1)
    line_up("cart", ROOMS[2], 1)
    line_up("cart", ROOMS[0], 1)
    # The loading dock is 1.1 m up, which the level lookup reports for anything standing on it.
    scatter("crate", DOCK, 3, RIGHT_ANGLES)
    scatter("cement", DOCK, 3)
    scatter("cardboard", DOCK, 2)
    # Service corridor: boxes shoved against the partitions, never into a doorway - the lintels
    # above the openings count as solid, so a candidate there is rejected.
    line_up("cardboard", CORRIDOR, 5, gap=0.05)
    scatter("barrel", CORRIDOR, 2)
    # The hall along the annex's west edge, where the deck opening comes through.
    line_up("shelves", ANNEX_HALL, 2)
    scatter("barrel", ANNEX_HALL, 3)
    scatter("cardboard", ANNEX_HALL, 3)
    scatter("crate", ANNEX_HALL, 1, RIGHT_ANGLES)
    # Deck: cover in the aisles between the pillar rows. Barriers and fences are straight things
    # and read wrong at a random angle, so those are square to the level.
    scatter("barrier", DECK, 7, RIGHT_ANGLES)
    scatter("fence", DECK, 3, RIGHT_ANGLES)
    scatter("crate", DECK, 4, RIGHT_ANGLES)
    scatter("barrel", DECK, 9)
    scatter("container", DECK, 4)
    scatter("cart", DECK, 2)
    scatter("toolchest", DECK, 2)
    # Ladders lean on something; free-standing in the middle of a deck they look dropped.
    line_up("ladder", DECK, 4, gap=0.04)
    line_up("ladder", ROOMS[3], 1, gap=0.04)

    for number, (key, spot) in enumerate(plan):
        name = "Prop%02d_%s" % (number, key)
        transform = transform_of(key, spot)
        if key in COVER:
            nodes.append("""[node name="%s" type="StaticBody3D" parent="Props"]
transform = %s
script = ExtResource("%s")

[node name="Model" parent="Props/%s" instance=ExtResource("%s")]
""" % (name, transform, ids["propbody"], name, ids["prop_" + key]))
        else:
            nodes.append("""[node name="%s" parent="Props" instance=ExtResource("%s")]
transform = %s
""" % (name, ids["prop_" + key], transform))

    # Wall-mounted, so these get a height rather than a floor and are not run through the placer.
    for index, (x, z, angle) in enumerate(((-29.6, 6.0, math.pi * 0.5), (31.0, -6.0, math.pi * 0.5),
                                           (37.2, 4.0, math.pi * 1.5))):
        bracket = shapes["extinguisher"].footprint(x, z, angle)
        bracket.y = 1.1
        nodes.append("""[node name="Extinguisher%d" parent="Props" instance=ExtResource("%s")]
transform = %s
""" % (index, ids["prop_extinguisher"], transform_of("extinguisher", bracket)))

    print("placed %d cars, %d props" % (len(cars), len(plan)))

    # ---- paint: bay markings on the floor, tags on the walls -----------------------------
    # Both are drawn by shaders rather than by textures, because a photographed tag is somebody
    # else's artwork under somebody else's licence and one image on twenty pillars reads as
    # wallpaper. Every mark gets its own seed, so no two are the same.
    nodes.append('[node name="Paint" type="Node3D" parent="."]\n')
    marks = 0

    def paint_mesh(kind: str, size: tuple[float, float]) -> str:
        name = "Mesh_%s_%d" % (kind, marks)
        mesh_type = "PlaneMesh" if kind == "bay" else "QuadMesh"
        orientation = "\norientation = 1" if kind == "bay" else ""
        subs.append("""[sub_resource type="%s" id="%s"]
size = Vector2(%.3f, %.3f)%s
""" % (mesh_type, name, size[0], size[1], orientation))
        return name

    def bay_material(seed_value: float) -> str:
        name = "Material_bay%d" % marks
        subs.append("""[sub_resource type="ShaderMaterial" id="%s"]
shader = ExtResource("%s")
shader_parameter/mark_seed = %.2f
shader_parameter/paint_color = Color(0.82, 0.81, 0.76, 1)
shader_parameter/line_width = 0.6
shader_parameter/wear = %.2f
shader_parameter/patchiness = %.2f
shader_parameter/dirt = 0.4
shader_parameter/opacity = 0.95
""" % (name, ids["baypaint"], seed_value, rng.uniform(0.45, 0.75), rng.uniform(0.3, 0.6)))
        return name

    def tag_material(seed_value: float) -> str:
        name = "Material_tag%d" % marks
        # Muted: aerosol on damp concrete under fluorescent tubes is never a pure hue, and a
        # saturated tag in a dark garage reads as a decal someone pasted on.
        first = rng.choice([(0.62, 0.16, 0.32), (0.68, 0.44, 0.12), (0.24, 0.5, 0.28),
                            (0.7, 0.7, 0.68), (0.4, 0.22, 0.55)])
        second = rng.choice([(0.18, 0.44, 0.55), (0.66, 0.6, 0.24), (0.58, 0.22, 0.2),
                             (0.12, 0.12, 0.14)])
        subs.append("""[sub_resource type="ShaderMaterial" id="%s"]
shader = ExtResource("%s")
shader_parameter/mark_seed = %.2f
shader_parameter/primary_color = Color(%.2f, %.2f, %.2f, 1)
shader_parameter/secondary_color = Color(%.2f, %.2f, %.2f, 1)
shader_parameter/outline_color = Color(0.04, 0.04, 0.05, 1)
shader_parameter/stroke_count = %d
shader_parameter/stroke_thickness = %.3f
shader_parameter/outline_width = 0.026
shader_parameter/overspray = %.2f
shader_parameter/drip_amount = %.2f
shader_parameter/wear = %.2f
shader_parameter/opacity = %.2f
""" % (name, ids["graffiti"], seed_value, first[0], first[1], first[2],
                second[0], second[1], second[2], rng.randint(3, 6),
                rng.uniform(0.022, 0.045), rng.uniform(0.05, 0.16),
                rng.uniform(0.15, 0.7), rng.uniform(0.15, 0.5), rng.uniform(0.72, 0.92)))
        return name

    def emit_mark(kind: str, size: tuple[float, float], position: tuple[float, float, float],
                  angle: float) -> None:
        nonlocal marks
        mesh = paint_mesh(kind, size)
        material = bay_material(rng.uniform(0.0, 64.0)) if kind == "bay" \
            else tag_material(rng.uniform(0.0, 64.0))
        nodes.append("""[node name="%s%02d" type="MeshInstance3D" parent="Paint"]
transform = %s
mesh = SubResource("%s")
material_override = SubResource("%s")
cast_shadow = 0
gi_mode = 2
""" % ("Bay" if kind == "bay" else "Tag", marks, yaw(angle, position), mesh, material))
        marks += 1

    # Bay dividers: 5 m deep stalls off both long walls and back to back down the middle rows,
    # spaced 2.6 m. A line landing inside a pillar is dropped rather than left poking out of it.
    bay_bands = [(-20.0, 1.0), (20.0, -1.0), (-9.0, 1.0), (-9.0, -1.0), (9.0, 1.0), (9.0, -1.0)]
    for wall_z, direction in bay_bands:
        depth = 5.0
        line_x = -28.7
        while line_x < 29.0:
            centre_z = wall_z + direction * depth * 0.5
            probe = Footprint(line_x, centre_z, 0.11, depth * 0.5, 0.0)
            if layout.level(probe) is not None and not layout.blocked(probe, 0.0):
                emit_mark("bay", (0.22, depth), (line_x, 0.012, centre_z), 0.0)
            line_x += 2.6

    # Tags. The angle turns the quad's own +Z to face into the room off each surface.
    deck_walls = [
        (-29.96, None, math.pi * 1.5), (29.96, None, math.pi * 0.5),
        (None, -19.96, 0.0), (None, 19.96, math.pi),
    ]
    for _ in range(9):
        wall_x, wall_z, angle = rng.choice(deck_walls)
        width, height = rng.uniform(1.6, 2.6), rng.uniform(1.1, 1.7)
        x = wall_x if wall_x is not None else rng.uniform(-27.0, 27.0)
        z = wall_z if wall_z is not None else rng.uniform(-18.0, 18.0)
        emit_mark("tag", (width, height), (x, rng.uniform(1.1, 1.8), z), angle)
    # Pillar faces are only 0.8 m across, so those tags are tall and narrow.
    pillars = [box for box in layout_boxes
               if box.mesh == "Walls_Concrete" and box.size[0] < 1.0 and box.size[2] < 1.0]
    rng.shuffle(pillars)
    for box in pillars[:11]:
        centre_x = (box.low[0] + box.high[0]) * 0.5
        centre_z = (box.low[2] + box.high[2]) * 0.5
        face = rng.randrange(4)
        offset = 0.42
        if face == 0:
            position, angle = (centre_x - offset, 0.0, centre_z), math.pi * 1.5
        elif face == 1:
            position, angle = (centre_x + offset, 0.0, centre_z), math.pi * 0.5
        elif face == 2:
            position, angle = (centre_x, 0.0, centre_z - offset), 0.0
        else:
            position, angle = (centre_x, 0.0, centre_z + offset), math.pi
        emit_mark("tag", (0.72, rng.uniform(0.9, 1.4)),
                  (position[0], rng.uniform(1.0, 1.7), position[2]), angle)
    # Back of house gets tagged too, on the corridor partitions.
    for _ in range(5):
        partition_x = rng.choice([35.2, 37.4])
        angle = math.pi * 1.5 if partition_x > 36.0 else math.pi * 0.5
        emit_mark("tag", (rng.uniform(1.2, 2.0), rng.uniform(1.0, 1.5)),
                  (partition_x, rng.uniform(1.1, 1.8), rng.uniform(-18.0, 18.0)), angle)
    print("painted %d marks" % marks)

    # Two metres off the centreline: the pillar row runs down z = 0, and a spawn on it put the
    # player's face 0.6 m into concrete. Here the whole 56 m of deck is open straight ahead.
    nodes.append("""[node name="SpawnPoint3D" type="Marker3D" parent="." groups=["player_spawn_point"]]
transform = Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, -26, 0.1, -2)
""")
    nodes.append("""[node name="WetGround" type="MeshInstance3D" parent="."]
material_override = SubResource("Material_puddles")
gi_mode = 0
script = ExtResource("%s")
""" % ids["fullscreen"])
    lightmap_node = """[node name="LightmapGI" type="LightmapGI" parent="."]
quality = 2
bounces = 3
use_denoiser = true
denoiser_strength = 0.1
interior = true
environment_mode = 0
shadowmask_mode = 1
generate_probes_subdiv = 2
max_texture_size = 8192
"""
    if "lightmap" in ids:
        lightmap_node += 'light_data = ExtResource("%s")\n' % ids["lightmap"]
    nodes.append(lightmap_node)
    nodes.append("""[node name="Player" parent="." instance=ExtResource("%s")]
""" % ids["player"])

    header = "[gd_scene load_steps=%d format=3]\n" % (len(ext) + len(subs) + 1)
    SCENE.write_text("\n".join([header] + ext + [""] + subs + nodes) + "\n", encoding="utf-8")
    print("wrote %s: %d ext resources, %d sub resources, %d nodes" % (
        SCENE.relative_to(ROOT), len(ext), len(subs), sum(1 for n in nodes if n.startswith("[node"))))
    return 0


if __name__ == "__main__":
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else 7))
