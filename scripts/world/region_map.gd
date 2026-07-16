class_name RegionMap
extends RefCounted
## The handcrafted layout of a map region, loaded from
## data/tables/region_layout.json.
##
## Pure geometry queries — no scene nodes, no rendering. Everything that
## makes the world feel authored asks this one object the same
## questions: the ground painter ("what surface is here?"), the obstacle
## scatter ("which cells are forest?"), the foliage system ("how thick
## should grass grow here?"). Swapping the terrain renderer later
## (e.g. Terrain3D) changes none of this — the layout stays the design
## source of truth and a new backend just reads it.
##
## Zones are circles in cell space with a `type` ("forest", "rocky",
## "clearing", "campsite", "resource", "town", "reserved"); roads are
## painted segments with a surface ("asphalt", "dirt", "gravel"); the
## hq_pad is the concrete slab under the starting base.

var zones: Array = []      # {id, type, center: Vector2 (m), radius: float (m)}
var roads: Array = []      # {a: Vector2, b: Vector2, width: float, surface}
## Painted rectangles: {center: Vector2, half: Vector2, surface} — the
## HQ compound's construction-zone gravel pads live here.
var rect_pads: Array = []
var pad_center := Vector2.ZERO
var pad_radius := 0.0


## Build from the DataManager table (cell units → world meters).
static func load_default() -> RegionMap:
	var map := RegionMap.new()
	var table: Variant = DataManager.get_table("region_layout")
	if table == null or not (table is Dictionary):
		return map  # empty layout = plain grass everywhere, nothing breaks
	var cs := WorldManager.cell_size()

	for z in table.get("zones", []):
		zones_append(map, z, cs)
	for r in table.get("roads", []):
		map.roads.append({
			"a": _cell_to_world(r.get("from", [0, 0]), cs),
			"b": _cell_to_world(r.get("to", [0, 0]), cs),
			"width": float(r.get("width", 1.0)) * cs,
			"surface": String(r.get("surface", "dirt")),
		})
	var pad: Dictionary = table.get("hq_pad", {})
	if not pad.is_empty():
		map.pad_center = _cell_to_world(pad.get("center", [0, 0]), cs)
		map.pad_radius = float(pad.get("radius", 0.0)) * cs

	# The HQ compound's construction zones read as prepared gravel pads
	# on the ground — same data the zone markers are built from.
	var compound: Variant = DataManager.get_table("hq_compound")
	if compound is Dictionary:
		for z in compound.get("zones", []):
			var corner := _cell_to_world(z.get("cell", [0, 0]), cs)
			var size := Vector2(float(z.size[0]), float(z.size[1])) * cs
			map.rect_pads.append({
				"center": corner + size / 2.0,
				"half": size / 2.0,
				"surface": "gravel",
			})
	return map


static func zones_append(map: RegionMap, z: Dictionary, cs: float) -> void:
	map.zones.append({
		"id": String(z.get("id", "")),
		"type": String(z.get("type", "")),
		"center": _cell_to_world(z.get("center", [0, 0]), cs),
		"radius": float(z.get("radius", 1.0)) * cs,
	})


static func _cell_to_world(pair: Array, cs: float) -> Vector2:
	return Vector2(float(pair[0]) * cs, float(pair[1]) * cs)


# ── Queries (positions are world-space XZ) ───────────────────────────────

## Painted surface at a point: "concrete" (HQ pad), a road surface
## ("asphalt"/"dirt"/"gravel"), or "" for natural ground.
func surface_at(xz: Vector2) -> String:
	if pad_radius > 0.0 and xz.distance_to(pad_center) <= pad_radius:
		return "concrete"
	for rect in rect_pads:
		if _rect_distance(xz, rect.center, rect.half) <= 0.0:
			return rect.surface
	var best := ""
	var best_width := INF
	for road in roads:
		var d := _distance_to_segment(xz, road.a, road.b)
		if d <= road.width * 0.5 and road.width < best_width:
			best = road.surface
			best_width = road.width  # narrow paths win over the highway
	return best


## Zone type covering a point. Overlaps resolve to the zone whose centre
## is proportionally closest, so small zones read over big ones.
func zone_type_at(xz: Vector2) -> String:
	var best := ""
	var best_ratio := 1.0
	for zone in zones:
		var ratio: float = xz.distance_to(zone.center) / maxf(zone.radius, 0.01)
		if ratio <= best_ratio:
			best_ratio = ratio
			best = zone.type
	return best


func zones_of_type(type: String) -> Array:
	var out := []
	for zone in zones:
		if zone.type == type:
			out.append(zone)
	return out


## A uniformly-distributed random point inside a zone circle.
func random_point_in(zone: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randf() * TAU
	var radius: float = zone.radius * sqrt(rng.randf())
	return Vector2(zone.center) + Vector2(cos(angle), sin(angle)) * radius


## True when the point is on any painted surface — used to keep roads,
## paths and the HQ slab free of foliage and obstacles.
func is_paved(xz: Vector2) -> bool:
	return surface_at(xz) != ""


## Anti-aliased paint weights at a point: {surface: 0..1}. Full strength
## on the surface, feathering out over ~1.5 m — the splat map stays low
## resolution but edges rasterize smooth instead of stair-stepped.
func surface_coverage(xz: Vector2) -> Dictionary:
	var weights := {}
	if pad_radius > 0.0:
		# Chebyshev distance: the slab is a square pad, reads man-made.
		var d := maxf(absf(xz.x - pad_center.x), absf(xz.y - pad_center.y))
		var w := 1.0 - smoothstep(pad_radius - 0.5, pad_radius + 1.5, d)
		if w > 0.0:
			weights["concrete"] = w
	for road in roads:
		var dist := _distance_to_segment(xz, road.a, road.b)
		var half: float = road.width * 0.5
		var w := 1.0 - smoothstep(half - 0.4, half + 1.4, dist)
		if w > 0.0:
			weights[road.surface] = maxf(w, float(weights.get(road.surface, 0.0)))
	for rect in rect_pads:
		var d := _rect_distance(xz, rect.center, rect.half)
		var w := 1.0 - smoothstep(-0.2, 1.0, d)
		if w > 0.0:
			weights[rect.surface] = maxf(w, float(weights.get(rect.surface, 0.0)))
	return weights


## Signed-ish distance outside an axis-aligned rectangle (0 inside).
func _rect_distance(p: Vector2, center: Vector2, half: Vector2) -> float:
	var d := (p - center).abs() - half
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
