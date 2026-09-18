class_name ShotBallistics
extends RefCounted

const RANGE := 120.0

## Damage is resolved by the host; wound effects never change health.
const ZONE_MULTIPLIER := {
	"head":      3.5,
	"neck":      2.8,
	"torso":     1.0,   # centre-mass, armour zone
	"torso_low": 1.15,  # abdomen/pelvis
	"arm_upper": 0.65,
	"arm_lower": 0.45,
	"leg_upper": 0.80,  # thigh
	"leg_lower": 0.50,
	# Legacy fallback so old callers that still pass "limbs" don't break.
	"limbs":     0.65,
}

static func damage_at(weapon: int, zone: String, distance: float) -> float:
	var base := 34.0 if weapon == 0 else 25.0
	var falloff_start := 35.0 if weapon == 0 else 15.0
	var minimum := 0.65 if weapon == 0 else 0.4
	var fraction := clampf((distance - falloff_start) / (RANGE - falloff_start), 0.0, 1.0)
	return base * float(ZONE_MULTIPLIER.get(zone, 1.0)) * lerpf(1.0, minimum, fraction)

static func ray(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3, excluded: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | SoldierHitboxes.layer_mask(), excluded)
	query.collide_with_areas = true
	query.hit_from_inside = true
	return space.intersect_ray(query)

# Aim at what the camera sees, but deliver the bullet from the actual barrel.
# The connecting segment prevents a barrel pushed through thin cover from firing
# out the other side. A low wall can expose the camera without exposing the gun.
static func trace(space: PhysicsDirectSpaceState3D, eye: Vector3, direction: Vector3, muzzle: Vector3, excluded: Array[RID]) -> Dictionary:
	var obstruction := ray(space, eye, muzzle, excluded)
	if not obstruction.is_empty():
		return obstruction
	var end := eye + direction.normalized() * RANGE
	var sight := ray(space, eye, end, excluded)
	if not sight.is_empty():
		end = sight.position
	var path := (end - muzzle).normalized()
	# Extend slightly beyond the sight hit to avoid losing a surface to rounding.
	return ray(space, muzzle, muzzle + path * minf(muzzle.distance_to(end) + 0.01, RANGE), excluded)
