#!/usr/bin/env python3
"""Where a prop is allowed to stand in a box blockout.

The parking level is generated, so nothing is dragged into place by hand and nothing notices
when a crate ends up inside a pillar, half a metre under a raised floor or across a doorway.
This is the part that notices: it knows which boxes are floor you can stand on and which are
solid, it measures each prop's own footprint, and it rejects a position instead of writing it
out. Everything is 2D plus a floor height, because a blockout has no slopes.
"""
import math

from blockout_boxes import Box


class Footprint:
    """A prop's oriented footprint on the floor, and the level it stands on.

    ``x``/``z`` is the centre of the rectangle the prop actually occupies, which is not where its
    own origin is: a downloaded prop is modelled wherever the artist left it, and the chainlink
    fence sits two metres off its own pivot. ``offset`` carries that, so the test uses the real
    rectangle and ``origin_xz`` gives back the position to write into the scene.
    """

    __slots__ = ("x", "z", "half_x", "half_z", "angle", "y", "offset")

    def __init__(self, x: float, z: float, half_x: float, half_z: float, angle: float,
                 offset: tuple[float, float] = (0.0, 0.0)) -> None:
        self.x = x
        self.z = z
        self.half_x = half_x
        self.half_z = half_z
        self.angle = angle
        self.offset = offset
        self.y = 0.0

    def origin_xz(self) -> tuple[float, float]:
        cos_a, sin_a = math.cos(self.angle), math.sin(self.angle)
        offset_x, offset_z = self.offset
        return (self.x - (cos_a * offset_x - sin_a * offset_z),
                self.z - (sin_a * offset_x + cos_a * offset_z))

    def corners(self, margin: float = 0.0) -> list[tuple[float, float]]:
        cos_a, sin_a = math.cos(self.angle), math.sin(self.angle)
        half_x, half_z = self.half_x + margin, self.half_z + margin
        return [(self.x + cos_a * sx * half_x - sin_a * sz * half_z,
                 self.z + sin_a * sx * half_x + cos_a * sz * half_z)
                for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    def axes(self) -> list[tuple[float, float]]:
        cos_a, sin_a = math.cos(self.angle), math.sin(self.angle)
        return [(cos_a, sin_a), (-sin_a, cos_a)]

    def radius(self) -> float:
        return math.hypot(self.half_x, self.half_z)

    def overlaps(self, other: "Footprint", margin: float = 0.0) -> bool:
        # Cheap circle test first: most candidates are nowhere near each other.
        if math.hypot(self.x - other.x, self.z - other.z) > self.radius() + other.radius() + margin:
            return False
        return not _separated(self.corners(margin), other.corners(), self.axes() + other.axes())

    def hits_box(self, box: Box, margin: float = 0.0) -> bool:
        corners = [(box.low[0], box.low[2]), (box.high[0], box.low[2]),
                   (box.high[0], box.high[2]), (box.low[0], box.high[2])]
        return not _separated(self.corners(margin), corners, self.axes() + [(1.0, 0.0), (0.0, 1.0)])


def _separated(first: list, second: list, axes: list) -> bool:
    for axis in axes:
        first_low = min(x * axis[0] + z * axis[1] for x, z in first)
        first_high = max(x * axis[0] + z * axis[1] for x, z in first)
        second_low = min(x * axis[0] + z * axis[1] for x, z in second)
        second_high = max(x * axis[0] + z * axis[1] for x, z in second)
        if first_low > second_high or second_low > first_high:
            return True
    return False


class Layout:
    """Splits a blockout's boxes into floors you can stand on and solids you cannot."""

    # A wall box wider than this is the welded perimeter shell, whose bounds cover the whole
    # interior. Treating it as solid would make the entire level unplaceable.
    SHELL_SIZE = 45.0
    # Above this, a box is something you walk around rather than something you stand on.
    STANDABLE_TOP = 1.6
    DECORATIVE_MESHES = ("Ceiling", "Fixtures", "Services")
    FLOOR_PREFIX = "Floor"

    def __init__(self, boxes: list[Box]) -> None:
        self.floors: list[Box] = []
        self.solids: list[Box] = []
        for box in boxes:
            size_x, size_y, size_z = box.size
            # Zero-thickness faces survive welding where a box was left open; they are not volume.
            if size_y < 0.02 or box.mesh in self.DECORATIVE_MESHES:
                continue
            # Split by what the mesh is for, not by how big the box is: a floor slab and the
            # perimeter shell have almost the same footprint, and only one of them is solid.
            if box.mesh.startswith(self.FLOOR_PREFIX):
                if box.high[1] <= self.STANDABLE_TOP:
                    self.floors.append(box)
                continue
            if size_x > self.SHELL_SIZE and size_z > self.SHELL_SIZE * 0.6:
                continue
            self.solids.append(box)

    def level(self, footprint: Footprint, tolerance: float = 0.02) -> float | None:
        """Floor height under the whole footprint, or None if it straddles two levels or air."""
        heights = []
        for x, z in footprint.corners() + [(footprint.x, footprint.z)]:
            tops = [box.high[1] for box in self.floors if box.covers(x, z)]
            if not tops:
                return None
            heights.append(max(tops))
        if max(heights) - min(heights) > tolerance:
            return None
        return max(heights)

    def blocked(self, footprint: Footprint, margin: float, min_height: float = 0.0) -> bool:
        """Solids in the way. `min_height` ignores trim lower than that: a kerb or a pillar base
        guard has to keep a crate out, but line paint is allowed to run right up to it."""
        for box in self.solids:
            if box.high[1] - box.low[1] <= min_height:
                continue
            if footprint.hits_box(box, margin):
                return True
        return False


class PropShape:
    """What a downloaded prop's own glTF says about how much floor it takes and where its base is."""

    __slots__ = ("size", "offset", "base")

    def __init__(self, low: list[float], high: list[float]) -> None:
        self.size = tuple(high[i] - low[i] for i in range(3))
        self.offset = ((low[0] + high[0]) * 0.5, (low[2] + high[2]) * 0.5)
        # Whatever the prop's origin does, this is what has to end up on the floor.
        self.base = low[1]

    def footprint(self, x: float, z: float, angle: float) -> Footprint:
        return Footprint(x, z, self.size[0] * 0.5, self.size[2] * 0.5, angle, self.offset)

    def depth_along(self, angle: float, axis: int) -> float:
        """Half the prop's world-space depth along one axis, so its back can be put on a wall."""
        across, along = abs(math.cos(angle)), abs(math.sin(angle))
        if axis == 0:
            return self.size[0] * 0.5 * across + self.size[2] * 0.5 * along
        return self.size[0] * 0.5 * along + self.size[2] * 0.5 * across


class Placer:
    """Rejection sampling over a region, keeping every prop clear of solids and of each other."""

    def __init__(self, layout: Layout, rng, margin: float = 0.18, spacing: float = 0.12) -> None:
        self.layout = layout
        self.rng = rng
        self.margin = margin
        self.spacing = spacing
        self.placed: list[Footprint] = []

    def reserve(self, footprint: Footprint) -> None:
        self.placed.append(footprint)

    def fits(self, footprint: Footprint) -> float | None:
        height = self.layout.level(footprint)
        if height is None or self.layout.blocked(footprint, self.margin):
            return None
        if any(footprint.overlaps(other, self.spacing) for other in self.placed):
            return None
        return height

    def accept(self, footprint: Footprint) -> Footprint | None:
        height = self.fits(footprint)
        if height is None:
            return None
        footprint.y = height
        self.reserve(footprint)
        return footprint

    def place(self, shape: PropShape, region: tuple[float, float, float, float],
              angles: list[float] | None = None, tries: int = 120) -> Footprint | None:
        low_x, high_x, low_z, high_z = region
        for _ in range(tries):
            angle = self.rng.choice(angles) if angles else self.rng.uniform(0.0, math.tau)
            spot = self.accept(shape.footprint(
                self.rng.uniform(low_x, high_x), self.rng.uniform(low_z, high_z), angle))
            if spot is not None:
                return spot
        return None

    def place_at(self, shape: PropShape, x: float, z: float, angle: float,
                 nudges: list[tuple[float, float]] | None = None) -> Footprint | None:
        """An authored position, allowed to shuffle a little if it landed in something solid."""
        for offset_x, offset_z in [(0.0, 0.0)] + (nudges or []):
            spot = self.accept(shape.footprint(x + offset_x, z + offset_z, angle))
            if spot is not None:
                return spot
        return None
