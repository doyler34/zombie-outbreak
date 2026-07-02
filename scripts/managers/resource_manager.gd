extends Node
## ResourceManager — the player's stockpile (autoload).
##
## Amounts are keyed by ResourceDefinition.id. The set of resources in the
## game is defined entirely by the .tres files in data/resources/ — this
## manager has no knowledge of specific resource types.
##
## All mutations go through add() / spend() so that caps are enforced and
## EventBus.resource_changed fires exactly once per change; UI and other
## systems must never write amounts directly.

var _amounts: Dictionary = {}  # id -> int


func _ready() -> void:
	SaveManager.register_section("resources", self)


## Reset the stockpile to each definition's starting_amount (new game).
func reset() -> void:
	_amounts.clear()
	for def in DataManager.all_resource_defs():
		_amounts[def.id] = def.starting_amount
		EventBus.resource_changed.emit(def.id, def.starting_amount, 0)


func get_amount(id: String) -> int:
	return int(_amounts.get(id, 0))


## Add (or with a negative amount, subtract) a single resource.
## Respects the definition's max_storage cap. Returns the applied change.
func add(id: String, amount: int) -> int:
	var def := DataManager.get_resource_def(id)
	if def == null:
		push_warning("[ResourceManager] Unknown resource id: %s" % id)
		return 0
	var current := get_amount(id)
	var target := maxi(current + amount, 0)
	if def.max_storage > 0:
		target = mini(target, def.max_storage)
	if target == current:
		return 0
	_amounts[id] = target
	EventBus.resource_changed.emit(id, target, target - current)
	return target - current


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if get_amount(id) < int(cost[id]):
			return false
	return true


## Atomically pay a multi-resource cost. Returns false (and changes
## nothing) if any part is unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for id in cost:
		add(id, -int(cost[id]))
	EventBus.resources_spent.emit(cost)
	return true


## Grant a bundle of resources, e.g. daily production or mission rewards.
func grant(bundle: Dictionary) -> void:
	for id in bundle:
		add(id, int(bundle[id]))


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return _amounts.duplicate()


func apply_save_data(data: Dictionary) -> void:
	_amounts.clear()
	for id in data:
		_amounts[id] = int(data[id])
		EventBus.resource_changed.emit(id, _amounts[id], 0)
