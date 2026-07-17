class_name BuildingPiece
extends Resource
## One modular base-building piece (wall, foundation, door...), fully
## data-driven.
##
## To add a piece, create a .tres in data/building_pieces/ using this
## script — DataManager discovers it and the build-mode menu, preview,
## validator and save system all work from this data. The placement
## system NEVER references individual assets; everything it needs to
## snap, validate and spawn a piece is declared here.
##
## Connection model (see BaseManager for the validator):
##  - `provides` are sockets a placed piece offers to its neighbours.
##  - `requires` are sockets a piece needs at its spot to be placeable.
## Tokens used by the v1 rules:
##   "terrain"       (req)  placeable on bare ground inside the build zone
##   "surface"       (prov) walkable top other pieces can sit on
##   "edge_support"  (prov) cell piece that shoulders wall-type pieces
##                   (req)  edge piece that needs a foundation/floor beside
##                          it, or a stackable piece directly below
##   "stack"         (prov) edge piece that another edge piece may stand on
##   "roof_support"  (prov) edge piece that can carry a floor/roof above
##                   (req)  cell piece that needs such support underneath
##   "doorway"       (prov) edge piece with an opening a door can fill
##                   (req)  door-type piece that only fits those openings
## New tokens can be added without touching existing pieces.

## Unique id used in save files and lookups.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

## Menu grouping and connection semantics ("foundation", "wall",
## "doorway", "door", "window", "floor", "roof", "gate", "fence",
## "stairs", "prop"). Purely data — the validator keys off sockets, and
## the menu builds one tab per category present.
@export var category: String = "wall"

## Where the piece lives on the build grid:
##  "cell" — occupies whole grid cells (foundations, floors, roofs)
##  "edge" — occupies one cell border (walls, doors, windows, fences)
@export var placement: String = "edge"

## Path to the 3D model, loaded lazily (a broken model falls back to a
## bright placeholder instead of dropping the piece from the data).
@export var model_path: String = ""
## Baked model correction applied before fitting (e.g. stand a flat
## board upright for a door leaf).
@export var mesh_rotation_degrees: Vector3 = Vector3.ZERO
## Explicit non-uniform scale. ZERO = auto-fit from `fit_mode`.
@export var mesh_scale: Vector3 = Vector3.ZERO
## Auto-fit rule when mesh_scale is ZERO:
##  "tile"    — stretch X/Z exactly onto the footprint (tiling floors)
##  "contain" — uniform scale to fit inside the footprint (props, stairs)
##  "edge"    — stretch X to the edge length, keep height/thickness
@export var fit_mode: String = "edge"

## Footprint in grid cells (cell pieces only; edge pieces span 1 edge).
@export var grid_size: Vector2i = Vector2i.ONE

## Optional authored snap connectors in local space. Empty = derived
## automatically from the placement type (v1 derives everything; the
## field is honoured by future free-form snapping).
@export var snap_points: PackedVector3Array = PackedVector3Array()
## Sockets this piece offers to neighbours once placed.
@export var provides: PackedStringArray = PackedStringArray()
## Sockets this piece needs at its spot to be placeable.
@export var requires: PackedStringArray = PackedStringArray()

## Whether the preview responds to the rotate control (90° steps).
@export var rotatable: bool = true

@export_group("Economy")
## Build cost, e.g. {"wood": 10}. Empty = free.
@export var cost: Dictionary = {}
## Upgrade ladder hooks (wood → reinforced → metal → concrete).
@export var tier: int = 0
@export var upgrades_to: String = ""

@export_group("Combat / physics")
@export var max_health: int = 200
## "box" = auto box collider from the fitted bounds; "none" = no body.
@export var collision: String = "box"
## Placed piece blocks ground movement across its edge (walls do,
## doorways/gates don't — keeps the nav grid honest).
@export var blocks_movement: bool = true

@export_group("Menu")
@export var sort_order: int = 100
## Placeholder/menu accent color (also used when the model is missing).
@export var color: Color = Color(0.72, 0.55, 0.3)


func offers(token: String) -> bool:
	return provides.has(token)


func needs(token: String) -> bool:
	return requires.has(token)
