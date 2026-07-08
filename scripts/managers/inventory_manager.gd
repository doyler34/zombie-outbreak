extends Node
## InventoryManager — the Commander's backpack and hotbar (autoload).
##
## Pure state + rules; every screen (inventory panel, hotbar) is a dumb
## view over this manager, redrawn on EventBus.inventory_changed /
## hotbar_changed. Items are identified by ItemDefinition.id — the
## manager knows nothing about specific items, so new content is a
## data/items/ .tres drop.
##
## Slots are a fixed-size Array of Dictionaries; an empty slot is {} and
## a filled one {"id": String, "count": int}. The hotbar is a second,
## smaller slot array with a type restriction (ItemDefinition.
## hotbar_allowed) — moving an item there REMOVES it from the backpack,
## like Minecraft/LDoE, so there is exactly one copy of the truth.
##
## Future systems plug in here:
##  - gathering/looting call add_item() and respect the false return
##  - combat reads equipped_weapon() / spend ammo via remove_item()
##  - crafting checks total_count() and calls remove_item()/add_item()

## Slot area names used by the move/drop API and save data.
const AREA_INVENTORY := "inventory"
const AREA_HOTBAR := "hotbar"

var _slots: Array[Dictionary] = []
var _hotbar: Array[Dictionary] = []
## Selected hotbar slot (-1 = nothing selected / hands empty).
var _active_index: int = -1


func _ready() -> void:
	SaveManager.register_section("inventory", self)
	_resize_arrays()


## New game: clear everything and grant the starting kit from settings.
func reset() -> void:
	_resize_arrays()
	for i in _slots.size():
		_slots[i] = {}
	for i in _hotbar.size():
		_hotbar[i] = {}
	_active_index = -1
	var kit: Dictionary = DataManager.settings.starting_items
	for id in kit:
		add_item(id, int(kit[id]), true)
	EventBus.inventory_changed.emit()
	EventBus.hotbar_changed.emit()
	EventBus.hotbar_selection_changed.emit(-1, null)


# ── Queries ──────────────────────────────────────────────────────────────

func inventory_size() -> int:
	return _slots.size()


func hotbar_size() -> int:
	return _hotbar.size()


## Slot contents by area/index: {} when empty, {"id","count"} otherwise.
func slot(area: String, index: int) -> Dictionary:
	var arr := _area(area)
	if index < 0 or index >= arr.size():
		return {}
	return arr[index]


func active_hotbar_index() -> int:
	return _active_index


## Definition of the item in the selected hotbar slot, or null.
func active_item() -> ItemDefinition:
	if _active_index < 0:
		return null
	var s := slot(AREA_HOTBAR, _active_index)
	return DataManager.get_item(s.get("id", "")) if not s.is_empty() else null


## The active WEAPON, if the selected hotbar item is one (else null).
func equipped_weapon() -> ItemDefinition:
	var item := active_item()
	return item if item != null and item.type == ItemDefinition.Type.WEAPON else null


## The active TOOL, if the selected hotbar item is one (else null).
func equipped_tool() -> ItemDefinition:
	var item := active_item()
	return item if item != null and item.type == ItemDefinition.Type.TOOL else null


## Total units of an item across backpack AND hotbar (for crafting/UI).
func total_count(id: String) -> int:
	var total := 0
	for s in _slots:
		if s.get("id", "") == id:
			total += int(s["count"])
	for s in _hotbar:
		if s.get("id", "") == id:
			total += int(s["count"])
	return total


## Would add_item(id, count) fit entirely? (Pickup checks this first.)
func can_add(id: String, count: int = 1) -> bool:
	var def := DataManager.get_item(id)
	if def == null:
		return false
	var space := 0
	for s in _slots:
		if s.is_empty():
			space += def.max_stack
		elif s.get("id", "") == id:
			space += def.max_stack - int(s["count"])
		if space >= count:
			return true
	return space >= count


# ── Mutations ────────────────────────────────────────────────────────────

## Add items to the backpack: top up existing stacks first, then fill
## empty slots. Returns how many units actually fit — callers that
## require all-or-nothing (pickups) should check can_add() first.
func add_item(id: String, count: int = 1, silent: bool = false) -> int:
	var def := DataManager.get_item(id)
	if def == null:
		push_warning("[InventoryManager] Unknown item id: %s" % id)
		return 0
	var remaining := count
	for s in _slots:  # stack pass
		if remaining <= 0:
			break
		if s.get("id", "") == id and int(s["count"]) < def.max_stack:
			var take: int = mini(remaining, def.max_stack - int(s["count"]))
			s["count"] = int(s["count"]) + take
			remaining -= take
	for i in _slots.size():  # empty-slot pass
		if remaining <= 0:
			break
		if _slots[i].is_empty():
			var take: int = mini(remaining, def.max_stack)
			_slots[i] = {"id": id, "count": take}
			remaining -= take
	var added := count - remaining
	if added > 0 and not silent:
		EventBus.inventory_changed.emit()
	if remaining > 0 and not silent:
		EventBus.notify("Inventory full!", 1)
	return added


## Remove units of an item (hotbar stacks last). Returns false — and
## removes nothing — if the total across all slots is insufficient.
func remove_item(id: String, count: int = 1) -> bool:
	if total_count(id) < count:
		return false
	var remaining := count
	remaining = _drain(_slots, id, remaining)
	remaining = _drain(_hotbar, id, remaining)
	EventBus.inventory_changed.emit()
	EventBus.hotbar_changed.emit()
	_validate_selection()
	return true


## Move/merge/swap between any two slots (backpack ↔ hotbar included).
## Merges when both sides hold the same item, swaps otherwise. Refuses
## (with a toast) items the hotbar doesn't accept. Returns success.
func move(from_area: String, from_index: int, to_area: String, to_index: int) -> bool:
	var from_arr := _area(from_area)
	var to_arr := _area(to_area)
	if from_index < 0 or from_index >= from_arr.size() \
			or to_index < 0 or to_index >= to_arr.size():
		return false
	if from_area == to_area and from_index == to_index:
		return false
	var src := from_arr[from_index]
	if src.is_empty():
		return false
	var dst := to_arr[to_index]

	if to_area == AREA_HOTBAR and not DataManager.get_item(src["id"]).hotbar_allowed():
		EventBus.notify("That can't go on the hotbar.", 1)
		return false
	# A swap pushes the destination item the other way — check it too.
	if not dst.is_empty() and dst.get("id") != src.get("id") \
			and from_area == AREA_HOTBAR and not DataManager.get_item(dst["id"]).hotbar_allowed():
		EventBus.notify("That can't go on the hotbar.", 1)
		return false

	if not dst.is_empty() and dst.get("id") == src.get("id"):
		# Same item: merge into the destination stack.
		var def := DataManager.get_item(src["id"])
		var take: int = mini(int(src["count"]), def.max_stack - int(dst["count"]))
		if take <= 0:
			return false
		dst["count"] = int(dst["count"]) + take
		src["count"] = int(src["count"]) - take
		if int(src["count"]) <= 0:
			from_arr[from_index] = {}
	else:
		to_arr[to_index] = src
		from_arr[from_index] = dst

	EventBus.inventory_changed.emit()
	EventBus.hotbar_changed.emit()
	_validate_selection()
	return true


## Throw away a whole slot (there is no ground-drop entity yet — dropped
## items are simply gone; a world pickup can replace this later).
func drop(area: String, index: int) -> void:
	var arr := _area(area)
	if index < 0 or index >= arr.size() or arr[index].is_empty():
		return
	var s := arr[index]
	var def := DataManager.get_item(s["id"])
	var label := def.display_name if def != null else String(s["id"])
	arr[index] = {}
	EventBus.notify("Dropped %d× %s." % [int(s["count"]), label], 0)
	EventBus.inventory_changed.emit()
	EventBus.hotbar_changed.emit()
	_validate_selection()


# ── Hotbar ───────────────────────────────────────────────────────────────

## Tap/press a hotbar slot. Selecting an equippable makes it the active
## weapon/tool; selecting a usable item prepares it, and selecting it
## AGAIN uses one. Selecting the active slot of a non-usable deselects
## (hands empty). Empty slots just deselect.
func select_hotbar(index: int) -> void:
	if index < 0 or index >= _hotbar.size() or _hotbar[index].is_empty():
		_set_active(-1)
		return
	if index == _active_index:
		var def := DataManager.get_item(_hotbar[index]["id"])
		if def != null and def.is_usable():
			use_hotbar(index)
		else:
			_set_active(-1)
		return
	_set_active(index)


## Consume/activate one unit of a usable hotbar item.
func use_hotbar(index: int) -> void:
	if index < 0 or index >= _hotbar.size() or _hotbar[index].is_empty():
		return
	var s := _hotbar[index]
	var def := DataManager.get_item(s["id"])
	if def == null or not def.is_usable():
		return
	s["count"] = int(s["count"]) - 1
	if int(s["count"]) <= 0:
		_hotbar[index] = {}
	_apply_use_effect(def)
	EventBus.item_used.emit(def)
	EventBus.hotbar_changed.emit()
	_validate_selection()


## What using an item does. Health lands with the combat/health system;
## until then the effect is reported so the loop is testable end-to-end.
func _apply_use_effect(def: ItemDefinition) -> void:
	if def.heal_amount > 0:
		EventBus.notify("%s %s used  (+%d HP)" % [def.icon, def.display_name, def.heal_amount], 2)
	else:
		EventBus.notify("%s %s used." % [def.icon, def.display_name], 0)


# ── Save contract ────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {
		"slots": _pack(_slots),
		"hotbar": _pack(_hotbar),
		"active": _active_index,
	}


func apply_save_data(data: Dictionary) -> void:
	_resize_arrays()
	_unpack(data.get("slots", []), _slots)
	_unpack(data.get("hotbar", []), _hotbar)
	_active_index = int(data.get("active", -1))
	_validate_selection()
	EventBus.inventory_changed.emit()
	EventBus.hotbar_changed.emit()
	EventBus.hotbar_selection_changed.emit(_active_index, active_item())


# ── Internal ─────────────────────────────────────────────────────────────

func _area(area: String) -> Array[Dictionary]:
	return _hotbar if area == AREA_HOTBAR else _slots


func _resize_arrays() -> void:
	_ensure_size(_slots, DataManager.settings.inventory_slots)
	_ensure_size(_hotbar, DataManager.settings.hotbar_slots)


func _ensure_size(arr: Array[Dictionary], size: int) -> void:
	while arr.size() < size:
		arr.append({})
	while arr.size() > size:
		arr.pop_back()


func _set_active(index: int) -> void:
	if index == _active_index:
		return
	_active_index = index
	EventBus.hotbar_selection_changed.emit(index, active_item())


## After any mutation: an emptied active slot means empty hands again.
func _validate_selection() -> void:
	if _active_index >= 0 and slot(AREA_HOTBAR, _active_index).is_empty():
		_set_active(-1)


## Take up to [param remaining] units of an item out of an array;
## returns what is still owed.
func _drain(arr: Array[Dictionary], id: String, remaining: int) -> int:
	for i in arr.size():
		if remaining <= 0:
			break
		if arr[i].get("id", "") == id:
			var take: int = mini(remaining, int(arr[i]["count"]))
			arr[i]["count"] = int(arr[i]["count"]) - take
			remaining -= take
			if int(arr[i]["count"]) <= 0:
				arr[i] = {}
	return remaining


func _pack(arr: Array[Dictionary]) -> Array:
	var out := []
	for s in arr:
		out.append({} if s.is_empty() else {"id": s["id"], "count": int(s["count"])})
	return out


func _unpack(data: Array, target: Array[Dictionary]) -> void:
	for i in target.size():
		var entry: Dictionary = data[i] if i < data.size() else {}
		if entry.is_empty() or DataManager.get_item(String(entry.get("id", ""))) == null:
			target[i] = {}
		else:
			target[i] = {"id": String(entry["id"]), "count": int(entry["count"])}
