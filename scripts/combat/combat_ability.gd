class_name CombatAbility
extends RefCounted
## Base class for player abilities used during battle.
##
## The battle scene builds a button per ability and manages cooldowns;
## an ability only implements execute(). Future abilities (Focus Fire,
## Molotov, Barricade Drop, ...) are one small subclass each — add them
## to BattleScene.ABILITIES and they appear in the bar.

var id: String = ""
var display_name: String = ""
var icon: String = "✦"
## Seconds between uses.
var cooldown: float = 10.0
## Total uses per battle (-1 = unlimited).
var max_uses: int = -1


## Perform the effect. Return true if the ability actually fired (false
## leaves the cooldown/uses untouched, e.g. nothing valid to target).
func execute(_battle: Node) -> bool:
	return false
