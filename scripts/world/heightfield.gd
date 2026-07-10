class_name Heightfield
extends RefCounted
## The region's elevation: gentle authored rolling hills that flatten
## out around the HQ clearing (buildable base ground stays level, the
## wilds get relief).
##
## Deterministic hash-noise — the same map always has the same hills,
## which is what "handcrafted" needs; nothing is stored in saves. Pure
## math with no scene dependencies: WorldDecorator builds the visual
## terrain mesh by sampling it, and WorldManager exposes it to gameplay
## as ground_height(), so characters, props, pickups and the camera all
## stand on the same ground the renderer draws. A future terrain
## backend (Terrain3D) replaces the sampling source, not the callers.

## Hill height range (m). Kept gentle: relief reads clearly at the
## LDoE camera angle without turning walking into mountaineering.
var amplitude := 2.4
## Fully flat within this distance of the HQ (m)...
var flat_radius := 34.0
## ...then hills fade in across this band (m).
var blend_band := 30.0
var flat_center := Vector2.ZERO


## Derive the flat zone from the region layout's HQ clearing so the
## design file stays the single source of truth.
static func create_default(region: RegionMap) -> Heightfield:
	var hf := Heightfield.new()
	hf.amplitude = DataManager.settings.terrain_amplitude
	hf.flat_center = region.pad_center
	for zone in region.zones_of_type("clearing"):
		hf.flat_center = zone.center
		hf.flat_radius = float(zone.radius) + 6.0
	return hf


func height_at(xz: Vector2) -> float:
	if amplitude <= 0.0:
		return 0.0
	var mask := smoothstep(flat_radius, flat_radius + blend_band,
		xz.distance_to(flat_center))
	if mask <= 0.0:
		return 0.0
	# Two octaves of value noise: broad ~60m swells + small undulation.
	var h := _noise(xz * 0.016) * 0.75 + _noise(xz * 0.055) * 0.25
	return (h - 0.5) * 2.0 * amplitude * mask


## Surface normal by central differences (for the terrain mesh).
func normal_at(xz: Vector2) -> Vector3:
	var e := 1.0
	var dx := height_at(xz + Vector2(e, 0)) - height_at(xz - Vector2(e, 0))
	var dz := height_at(xz + Vector2(0, e)) - height_at(xz - Vector2(0, e))
	return Vector3(-dx, 2.0 * e, -dz).normalized()


# ── Deterministic value noise ────────────────────────────────────────────

func _noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2.ONE * 3.0 - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


func _hash(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(163.9, 297.7)) + 17.13) * 43758.5453, 1.0)
