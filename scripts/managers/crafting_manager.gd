extends Node
## CraftingManager — turns inventory items into other items (autoload).
##
## Pure rules over RecipeDefinitions; the crafting screen is a dumb view
## that calls can_craft()/missing()/craft() and redraws on
## EventBus.inventory_changed. Recipes live in data/recipes/ and item
## identities in data/items/, so new craftables are data drops.
##
## Ingredients are counted across the whole inventory (backpack +
## hotbar) via InventoryManager.total_count and consumed with
## remove_item; the result goes through add_item so every stacking and
## capacity rule applies unchanged. Future crafting stations only need
## to filter all_recipes() by RecipeDefinition.station.


## Ingredients still lacking for a recipe: {item_id: shortfall}.
## Empty means the recipe is affordable.
func missing(recipe: RecipeDefinition) -> Dictionary:
	var lack := {}
	for item_id in recipe.ingredients:
		var need := int(recipe.ingredients[item_id])
		var have := InventoryManager.total_count(item_id)
		if have < need:
			lack[item_id] = need - have
	return lack


func can_craft(recipe: RecipeDefinition) -> bool:
	return missing(recipe).is_empty()


## Craft once. Returns false (with a toast explaining why) when
## ingredients are missing or the result has no room.
func craft(recipe: RecipeDefinition) -> bool:
	var result := recipe.result_definition()
	if result == null:
		push_warning("[CraftingManager] Recipe '%s' makes unknown item '%s'"
			% [recipe.id, recipe.result_item])
		return false

	var lack := missing(recipe)
	if not lack.is_empty():
		EventBus.notify("Missing:  %s" % ingredients_text(lack), 1)
		return false
	# Checked before ingredients leave the bag: consuming them usually
	# frees space, so this can only be over-cautious, never wrong.
	if not InventoryManager.can_add(recipe.result_item, recipe.result_count):
		EventBus.notify("Inventory full!", 1)
		return false

	for item_id in recipe.ingredients:
		InventoryManager.remove_item(item_id, int(recipe.ingredients[item_id]))
	InventoryManager.add_item(recipe.result_item, recipe.result_count)

	EventBus.notify("Crafted %s %s%s" % [result.icon, result.display_name,
		" ×%d" % recipe.result_count if recipe.result_count > 1 else ""], 2)
	EventBus.item_crafted.emit(recipe, result)
	return true


## "2 🪵 Wood   1 ⚙ Scrap Metal" — shared by the screen and the toasts.
func ingredients_text(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id in amounts:
		var def := DataManager.get_item(item_id)
		parts.append("%d %s %s" % [int(amounts[item_id]),
			def.icon if def != null else "",
			def.display_name if def != null else String(item_id)])
	return "   ".join(parts)
