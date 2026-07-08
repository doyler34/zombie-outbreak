class_name ItemSlotButton
extends Button
## One inventory/hotbar slot: item icon, stack count, selection ring.
##
## A dumb view — it renders whatever slot Dictionary it is given
## ({} = empty, {"id","count"} = filled) and reports taps through its
## normal pressed signal. The hotbar and the inventory screen both build
## their grids out of these, so slots look and behave identically
## everywhere.

const SLOT_SIZE := Vector2(58, 58)

## Where this slot lives, for InventoryManager calls
## (InventoryManager.AREA_INVENTORY / AREA_HOTBAR) and which index.
var area: String = InventoryManager.AREA_INVENTORY
var index: int = 0

var _count_label: Label
var _selected: bool = false


func _init(slot_area: String, slot_index: int) -> void:
	area = slot_area
	index = slot_index


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	add_theme_font_size_override("font_size", 26)
	_apply_style()

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", UIStyle.TEXT_WARM)
	_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_count_label.add_theme_constant_override("outline_size", 4)
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count_label.offset_right = -5
	_count_label.offset_bottom = -3
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	refresh()


## Re-read this slot's contents from the InventoryManager and redraw.
func refresh() -> void:
	var slot := InventoryManager.slot(area, index)
	if slot.is_empty():
		text = ""
		_count_label.text = ""
		tooltip_text = ""
		return
	var def := DataManager.get_item(slot["id"])
	text = def.icon if def != null else "❔"
	_count_label.text = str(int(slot["count"])) if int(slot["count"]) > 1 else ""
	tooltip_text = def.display_name if def != null else String(slot["id"])


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_apply_style()


func _apply_style() -> void:
	var border := UIStyle.BRASS_BRIGHT if _selected else UIStyle.BRASS
	var bg := UIStyle.BUTTON_BG.lightened(0.12) if _selected else UIStyle.BUTTON_BG
	add_theme_stylebox_override("normal", _slot_style(bg, border))
	add_theme_stylebox_override("hover", _slot_style(bg.lightened(0.06), border))
	add_theme_stylebox_override("pressed", _slot_style(bg.darkened(0.25), border))


func _slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := UIStyle.button_style(bg, border)
	# Square slots need tighter padding than text buttons.
	s.set_content_margin_all(4)
	if _selected:
		s.set_border_width_all(3)
	return s
