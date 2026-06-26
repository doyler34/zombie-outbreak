# event_bus.gd - Global signal bus for decoupled communication
extends Node

# Game state signals
signal day_passed(day: int)
signal night_started
signal day_started

# Resource signals
signal resource_changed(resource: String, amount: int, total: int)
signal resource_low(resource: String)

# Survivor signals
signal survivor_added(survivor: Dictionary)
signal survivor_died(name: String)
signal survivor_hungry(survivor: Dictionary)
signal survivor_healed(survivor: Dictionary)

# Building signals
signal building_built(building_id: String, level: int)
signal building_upgraded(building_id: String, new_level: int)

# Mission signals
signal mission_started(mission_data: Dictionary)
signal mission_completed(mission_data: Dictionary, loot: Dictionary)
signal mission_failed(mission_data: Dictionary, reason: String)
signal survivors_returned(count: int)

# Combat signals
signal zombie_attack_started(horde_size: int)
signal zombie_killed(zombie_type: String)
signal zombie_attack_ended(survivors_lost: int)
signal base_defense_triggered(defense_value: int)

# UI signals
signal notification(text: String, color: String)
signal game_over(reason: String)
signal game_saved
signal game_loaded
