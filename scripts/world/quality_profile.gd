class_name QualityProfile
extends RefCounted
## Answers "how much can this device afford?" in one place.
##
## PC gets full foliage density, shadows and draw distance; Android gets
## the reduced numbers from GameSettings. Every system that scales with
## hardware (foliage, shadows, future particles/post-fx) asks these
## static helpers instead of sniffing the platform itself, so adding a
## user-facing graphics menu later only means overriding these answers.

static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Multiplier applied to all decorative foliage instance counts.
static func foliage_density() -> float:
	var s := DataManager.settings
	return s.mobile_foliage_density if is_mobile() else s.desktop_foliage_density


static func shadows_enabled() -> bool:
	return DataManager.settings.mobile_shadows if is_mobile() else true


## Distance (m) beyond which instanced foliage stops rendering.
static func foliage_view_distance() -> float:
	var s := DataManager.settings
	return s.mobile_foliage_view_distance if is_mobile() else s.desktop_foliage_view_distance
