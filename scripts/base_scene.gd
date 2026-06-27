# base_scene.gd - Main game scene controller
extends Node2D

@onready var day_night_overlay: ColorRect = $DayNightOverlay
@onready var ground_bg: ColorRect = $BgLayer/GrassBackground
@onready var ui_layer: Control = $UILayer
@onready var top_bar: HBoxContainer = $UILayer/TopBar
@onready var day_label: Label = $UILayer/TopBar/DayLabel
@onready var wood_label: Label = $UILayer/TopBar/WoodLabel
@onready var stone_label: Label = $UILayer/TopBar/StoneLabel
@onready var metal_label: Label = $UILayer/TopBar/MetalLabel
@onready var gold_label: Label = $UILayer/TopBar/GoldLabel
@onready var notification_label: Label = $UILayer/NotificationLabel
@onready var notification_timer: Timer = $NotificationTimer

@onready var buildings_btn: Button = $UILayer/BuildingsBtn
@onready var survivors_btn: Button = $UILayer/SurvivorsBtn
@onready var mission_btn: Button = $UILayer/MissionBtn
@onready var menu_btn: Button = $UILayer/MenuBtn

var building_panel: Control
var building_list: VBoxContainer
var buildings_data: Array = []

var day_night_timer: float = 0.0
const FULL_CYCLE := 120.0

# Tutorial state
var outpost_sprite: TextureRect
var outpost_repaired_tex: Texture2D
var repair_panel: Control
var build_timer_label: Label
var build_countdown: float = 0.0
var building_active: bool = false
var glow_tween: Tween

func _ready() -> void:
	# Hide tscn bottom bar; _build_bottom_bar() creates the correctly-positioned one
	$UILayer/BottomBg.visible = false
	buildings_btn.visible = false
	survivors_btn.visible = false
	mission_btn.visible = false
	menu_btn.visible = false

	_build_bottom_bar()
	_make_building_panel()
	_make_menu_panel()

	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.notification.connect(_show_notification)
	EventBus.game_over.connect(_on_game_over)
	notification_timer.timeout.connect(_on_notification_timeout)

	_refresh_resource_display()
	_refresh_day_display()
	day_night_timer = GameState.day_timer
	_adjust_day_night_overlay()

	if GameState.tutorial_active and GameState.tutorial_step == 0:
		_setup_tutorial()

# ── BOTTOM BAR ─────────────────────────────────────────────────────────────────

func _build_bottom_bar() -> void:
	# Background — full viewport width, anchored to the bottom edge
	var bar = ColorRect.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -80
	bar.offset_bottom = 0
	bar.color = Color(0.10, 0.09, 0.07, 0.97)
	ui_layer.add_child(bar)

	# Brass accent line at the top of the bar
	var accent = ColorRect.new()
	accent.anchor_left = 0.0
	accent.anchor_right = 1.0
	accent.anchor_top = 1.0
	accent.anchor_bottom = 1.0
	accent.offset_top = -80
	accent.offset_bottom = -78
	accent.color = Color(0.72, 0.52, 0.18, 1.0)
	ui_layer.add_child(accent)

	# Button row — fixed 515 px wide, horizontally centred, anchored to bottom
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	hbox.anchor_left = 0.5
	hbox.anchor_right = 0.5
	hbox.anchor_top = 1.0
	hbox.anchor_bottom = 1.0
	hbox.offset_left = -257
	hbox.offset_right = 258
	hbox.offset_top = -71
	hbox.offset_bottom = -9
	ui_layer.add_child(hbox)

	for item: Array in [
		["BUILD",   _show_building_panel],
		["CREW",    func(): _show_notification("Crew panel coming soon", "#C8A84B")],
		["MISSION", func(): _show_notification("Mission panel coming soon", "#C8A84B")],
		["MENU",    func(): menu_panel.visible = true],
	]:
		var btn := Button.new()
		btn.text = item[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 17)
		btn.add_theme_color_override("font_color", Color(0.92, 0.78, 0.42, 1))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.14, 0.08, 1.0)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.65, 0.47, 0.15, 1.0)
		style.corner_radius_top_left = 5
		style.corner_radius_top_right = 5
		style.corner_radius_bottom_left = 5
		style.corner_radius_bottom_right = 5
		btn.add_theme_stylebox_override("normal", style)
		btn.pressed.connect(item[1])
		hbox.add_child(btn)


# ── TUTORIAL ────────────────────────────────────────────────────────────────────

func _setup_tutorial() -> void:
	# Broken building sprite — centred on the map, no shader so it is always visible
	outpost_sprite = TextureRect.new()
	outpost_sprite.texture = load("res://assets/buildings/outpost_broken.jpg")
	outpost_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outpost_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	outpost_sprite.set_size(Vector2(360, 360))
	outpost_sprite.set_position(Vector2(360 - 180, 560 - 180))
	outpost_sprite.mouse_filter = Control.MOUSE_FILTER_STOP
	outpost_sprite.gui_input.connect(_on_outpost_clicked)
	ui_layer.add_child(outpost_sprite)

	# Load repaired texture for later
	outpost_repaired_tex = load("res://assets/buildings/outpost_repaired.jpg")

	# Pulsing amber glow
	_start_glow_pulse()

	# Tutorial hint arrow + label
	_make_tutorial_hint()

func _start_glow_pulse() -> void:
	if glow_tween:
		glow_tween.kill()
	glow_tween = create_tween()
	glow_tween.set_loops()
	glow_tween.tween_property(outpost_sprite, "modulate", Color(1.55, 1.20, 0.40, 1.0), 0.9)\
		.set_ease(Tween.EASE_IN_OUT)
	glow_tween.tween_property(outpost_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.9)\
		.set_ease(Tween.EASE_IN_OUT)

func _make_tutorial_hint() -> void:
	var hint = Label.new()
	hint.name = "TutorialHint"
	hint.text = "⬆  TAP TO REPAIR"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.95, 0.78, 0.28, 1))
	hint.set_position(Vector2(272, 910))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(176, 0)
	ui_layer.add_child(hint)

	# Fade the hint in and out slowly
	var ht = create_tween()
	ht.set_loops()
	ht.tween_property(hint, "modulate:a", 0.2, 1.1)
	ht.tween_property(hint, "modulate:a", 1.0, 1.1)

func _on_outpost_clicked(event: InputEvent) -> void:
	if building_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_repair_panel()

# ── REPAIR PANEL (steampunk) ────────────────────────────────────────────────────

func _show_repair_panel() -> void:
	if repair_panel and repair_panel.visible:
		return
	if repair_panel:
		repair_panel.queue_free()

	repair_panel = Control.new()
	repair_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	repair_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim overlay
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			repair_panel.visible = false
	)
	repair_panel.add_child(dim)

	# Panel box — 580×520, centered
	var bw = 580
	var bh = 520
	var box = Panel.new()
	box.set_position(Vector2((720 - bw) / 2.0, (1280 - bh) / 2.0))
	box.set_size(Vector2(bw, bh))

	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.06, 0.04, 0.98)
	ps.border_width_left = 3
	ps.border_width_right = 3
	ps.border_width_top = 3
	ps.border_width_bottom = 3
	ps.border_color = Color(0.72, 0.52, 0.18, 1)
	ps.corner_radius_top_left = 6
	ps.corner_radius_top_right = 6
	ps.corner_radius_bottom_left = 6
	ps.corner_radius_bottom_right = 6
	box.add_theme_stylebox_override("panel", ps)
	repair_panel.add_child(box)

	# Inner brass accent border (inset 6px)
	var inner = Panel.new()
	inner.set_position(Vector2(8, 8))
	inner.set_size(Vector2(bw - 16, bh - 16))
	var inner_s = StyleBoxFlat.new()
	inner_s.bg_color = Color(0, 0, 0, 0)
	inner_s.border_width_left = 1
	inner_s.border_width_right = 1
	inner_s.border_width_top = 1
	inner_s.border_width_bottom = 1
	inner_s.border_color = Color(0.55, 0.38, 0.10, 0.6)
	inner.add_theme_stylebox_override("panel", inner_s)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)

	# Header bar
	var header = ColorRect.new()
	header.set_position(Vector2(0, 0))
	header.set_size(Vector2(bw, 52))
	header.color = Color(0.14, 0.10, 0.04, 1.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)

	var header_line = ColorRect.new()
	header_line.set_position(Vector2(0, 51))
	header_line.set_size(Vector2(bw, 2))
	header_line.color = Color(0.72, 0.52, 0.18, 1)
	header_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header_line)

	# Title
	var title = Label.new()
	title.text = "⚙  SURVIVOR OUTPOST"
	title.set_position(Vector2(18, 12))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.25, 1))
	box.add_child(title)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.set_position(Vector2(bw - 48, 8))
	close_btn.set_size(Vector2(36, 36))
	close_btn.add_theme_font_size_override("font_size", 16)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.30, 0.12, 0.04, 1)
	cs.border_width_left = 1
	cs.border_width_right = 1
	cs.border_width_top = 1
	cs.border_width_bottom = 1
	cs.border_color = Color(0.65, 0.35, 0.10, 1)
	cs.corner_radius_top_left = 4
	cs.corner_radius_top_right = 4
	cs.corner_radius_bottom_left = 4
	cs.corner_radius_bottom_right = 4
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3, 1))
	close_btn.pressed.connect(func(): repair_panel.visible = false)
	box.add_child(close_btn)

	# Lore text
	var lore = Label.new()
	lore.text = "Eight years since the first outbreak.\nThe city fell silent. The pipes went cold.\n\nThis old outpost still stands — barely.\nRestore it. Light the furnaces.\nThis is where survivors make their stand."
	lore.set_position(Vector2(20, 66))
	lore.set_size(Vector2(bw - 40, 170))
	lore.add_theme_font_size_override("font_size", 16)
	lore.add_theme_color_override("font_color", Color(0.80, 0.70, 0.52, 1))
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lore)

	# Divider
	var div = ColorRect.new()
	div.set_position(Vector2(20, 250))
	div.set_size(Vector2(bw - 40, 1))
	div.color = Color(0.55, 0.38, 0.10, 0.5)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(div)

	# Cost header
	var cost_header = Label.new()
	cost_header.text = "MATERIALS REQUIRED"
	cost_header.set_position(Vector2(20, 262))
	cost_header.add_theme_font_size_override("font_size", 13)
	cost_header.add_theme_color_override("font_color", Color(0.55, 0.45, 0.28, 1))
	box.add_child(cost_header)

	# Cost row
	var costs = {"wood": 20, "stone": 10, "gold": 50}
	var cost_icons = {"wood": "🪵", "stone": "🪨", "gold": "🪙"}
	var cost_colors = {
		"wood":  Color(0.72, 0.50, 0.22, 1),
		"stone": Color(0.75, 0.72, 0.68, 1),
		"gold":  Color(0.95, 0.78, 0.18, 1)
	}
	var cx = 20
	for res in ["wood", "stone", "gold"]:
		var can = ResourceManager.has(res, costs[res])
		var lbl = Label.new()
		lbl.text = "%s %s: %d" % [cost_icons[res], res.capitalize(), costs[res]]
		lbl.set_position(Vector2(cx, 288))
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color",
			cost_colors[res] if can else Color(0.8, 0.2, 0.1, 1))
		box.add_child(lbl)
		cx += 178

	# Stock label
	var stock = Label.new()
	stock.text = "You have:  🪵 %d   🪨 %d   🪙 %d" % [
		ResourceManager.get_resource("wood"),
		ResourceManager.get_resource("stone"),
		ResourceManager.get_resource("gold")
	]
	stock.set_position(Vector2(20, 320))
	stock.add_theme_font_size_override("font_size", 14)
	stock.add_theme_color_override("font_color", Color(0.60, 0.58, 0.48, 1))
	box.add_child(stock)

	# Divider 2
	var div2 = ColorRect.new()
	div2.set_position(Vector2(20, 356))
	div2.set_size(Vector2(bw - 40, 1))
	div2.color = Color(0.55, 0.38, 0.10, 0.5)
	div2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(div2)

	# Build timer label (hidden until repair starts)
	build_timer_label = Label.new()
	build_timer_label.text = ""
	build_timer_label.set_position(Vector2(20, 370))
	build_timer_label.set_size(Vector2(bw - 40, 60))
	build_timer_label.add_theme_font_size_override("font_size", 22)
	build_timer_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.25, 1))
	build_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_timer_label.visible = false
	box.add_child(build_timer_label)

	# REPAIR button
	var can_afford = ResourceManager.can_afford(costs)
	var repair_btn = Button.new()
	repair_btn.text = "⚙  REPAIR OUTPOST"
	repair_btn.set_position(Vector2((bw - 320) / 2.0, 420))
	repair_btn.set_size(Vector2(320, 64))
	repair_btn.add_theme_font_size_override("font_size", 20)
	var bs = StyleBoxFlat.new()
	bs.bg_color = Color(0.38, 0.24, 0.05, 1) if can_afford else Color(0.18, 0.16, 0.14, 1)
	bs.border_width_left = 2
	bs.border_width_right = 2
	bs.border_width_top = 2
	bs.border_width_bottom = 2
	bs.border_color = Color(0.82, 0.60, 0.18, 1) if can_afford else Color(0.35, 0.32, 0.28, 1)
	bs.corner_radius_top_left = 6
	bs.corner_radius_top_right = 6
	bs.corner_radius_bottom_left = 6
	bs.corner_radius_bottom_right = 6
	repair_btn.add_theme_stylebox_override("normal", bs)
	repair_btn.add_theme_color_override("font_color",
		Color(1.0, 0.88, 0.45, 1) if can_afford else Color(0.45, 0.42, 0.38, 1))
	repair_btn.disabled = not can_afford
	repair_btn.pressed.connect(_on_repair_pressed)
	box.add_child(repair_btn)

	ui_layer.add_child(repair_panel)

func _on_repair_pressed() -> void:
	var costs = {"wood": 20, "stone": 10, "gold": 50}
	if not ResourceManager.pay(costs):
		_show_notification("Not enough materials!", "#FF4444")
		return

	building_active = true
	if glow_tween:
		glow_tween.kill()
	outpost_sprite.modulate = Color(1, 1, 1, 1)

	# Close the detail panel — building stays visible on the ground
	if repair_panel:
		repair_panel.visible = false

	# Small countdown badge centred on the building sprite
	var badge = Panel.new()
	badge.name = "RepairBadge"
	var cx = outpost_sprite.position.x + outpost_sprite.size.x * 0.5
	var cy = outpost_sprite.position.y + outpost_sprite.size.y * 0.5
	badge.set_position(Vector2(cx - 90, cy - 28))
	badge.set_size(Vector2(180, 56))
	var bs2 = StyleBoxFlat.new()
	bs2.bg_color = Color(0.07, 0.06, 0.04, 0.90)
	bs2.border_width_left = 2
	bs2.border_width_right = 2
	bs2.border_width_top = 2
	bs2.border_width_bottom = 2
	bs2.border_color = Color(0.72, 0.52, 0.18, 1)
	bs2.corner_radius_top_left = 6
	bs2.corner_radius_top_right = 6
	bs2.corner_radius_bottom_left = 6
	bs2.corner_radius_bottom_right = 6
	badge.add_theme_stylebox_override("panel", bs2)
	ui_layer.add_child(badge)

	build_timer_label = Label.new()
	build_timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	build_timer_label.add_theme_font_size_override("font_size", 18)
	build_timer_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.25, 1))
	build_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	build_timer_label.text = "⚙ REPAIRING  10s"
	badge.add_child(build_timer_label)

	build_countdown = 10.0

	# Pulse the building while repairing
	var rep_tween = create_tween()
	rep_tween.set_loops()
	rep_tween.tween_property(outpost_sprite, "modulate", Color(1.2, 1.0, 0.6, 1.0), 0.5)
	rep_tween.tween_property(outpost_sprite, "modulate", Color(0.8, 0.8, 0.8, 1.0), 0.5)

func _finish_repair() -> void:
	if repair_panel:
		repair_panel.queue_free()
		repair_panel = null
	var badge = ui_layer.find_child("RepairBadge", true, false)
	if badge:
		badge.queue_free()
	build_timer_label = null

	# Swap to repaired building
	outpost_sprite.texture = outpost_repaired_tex

	# Flash bright on completion
	outpost_sprite.modulate = Color(2.0, 1.8, 0.8, 1.0)
	var flash = create_tween()
	flash.tween_property(outpost_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.2)

	# Remove hint label
	var hint = ui_layer.find_child("TutorialHint", true, false)
	if hint:
		hint.queue_free()

	# Update game state
	GameState.buildings["ruined_outpost"] = 1
	GameState.tutorial_active = false
	GameState.tutorial_step = 2
	GameState._recalculate_base_stats()
	GameState.save_game()

	EventBus.building_built.emit("ruined_outpost", 1)
	_show_notification("Outpost restored! The lights are on.", "#C8A84B")

# ── BUILDING PANEL ──────────────────────────────────────────────────────────────

func _make_building_panel() -> void:
	var file = FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			buildings_data = json.get_data().buildings
		file.close()

	building_panel = Control.new()
	building_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_panel.visible = false
	building_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			building_panel.visible = false
	)
	building_panel.add_child(dim)

	var bw = 600
	var bh = 700
	var box = Panel.new()
	box.set_position(Vector2((720 - bw) / 2, (1280 - bh) / 2))
	box.set_size(Vector2(bw, bh))
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.06, 0.04, 0.98)
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.72, 0.52, 0.18, 1)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	box.add_theme_stylebox_override("panel", panel_style)
	building_panel.add_child(box)

	var header = ColorRect.new()
	header.set_position(Vector2(0, 0))
	header.set_size(Vector2(bw, 52))
	header.color = Color(0.14, 0.10, 0.04, 1.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)

	var hline = ColorRect.new()
	hline.set_position(Vector2(0, 51))
	hline.set_size(Vector2(bw, 2))
	hline.color = Color(0.72, 0.52, 0.18, 1)
	hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hline)

	var title = Label.new()
	title.set_position(Vector2(18, 12))
	title.set_size(Vector2(bw - 70, 30))
	title.text = "⚙  CONSTRUCTIONS"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.25, 1))
	box.add_child(title)

	var close = Button.new()
	close.set_position(Vector2(bw - 50, 8))
	close.set_size(Vector2(38, 36))
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 16)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.30, 0.12, 0.04, 1)
	close_style.border_width_left = 1
	close_style.border_width_right = 1
	close_style.border_width_top = 1
	close_style.border_width_bottom = 1
	close_style.border_color = Color(0.65, 0.35, 0.10, 1)
	close_style.corner_radius_top_left = 4
	close_style.corner_radius_top_right = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	close.add_theme_stylebox_override("normal", close_style)
	close.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3, 1))
	close.pressed.connect(func(): building_panel.visible = false)
	box.add_child(close)

	var scroll = ScrollContainer.new()
	scroll.set_position(Vector2(10, 60))
	scroll.set_size(Vector2(bw - 20, bh - 70))
	box.add_child(scroll)

	building_list = VBoxContainer.new()
	building_list.layout_mode = 2
	building_list.add_theme_constant_override("separation", 10)
	scroll.add_child(building_list)

	ui_layer.add_child(building_panel)

func _show_building_panel() -> void:
	_populate_building_list()
	building_panel.visible = true

func _populate_building_list() -> void:
	for child in building_list.get_children():
		child.queue_free()

	for bld in buildings_data:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 54)

		var current_level = GameState.buildings.get(bld.id, 0)
		var is_placed = GameState.buildings.has(bld.id)
		var is_broken = is_placed and current_level == 0

		var name_label = Label.new()
		if is_broken:
			name_label.text = "%s  (Broken)" % bld.name
		else:
			name_label.text = "%s  Lv %d" % [bld.name, current_level]
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.90, 0.78, 0.52, 1))
		row.add_child(name_label)

		var btn = Button.new()
		if is_broken:
			btn.text = "Repair"
		elif not is_placed:
			btn.text = "Build"
		elif current_level < bld.max_level:
			btn.text = "Upgrade Lv%d" % (current_level + 1)
		else:
			btn.text = "MAX"
			btn.disabled = true
		btn.custom_minimum_size = Vector2(140, 44)
		btn.add_theme_font_size_override("font_size", 14)
		var bld_ref = bld
		var lvl = current_level
		btn.pressed.connect(func(): _do_build(bld_ref, lvl))
		var bstyle = StyleBoxFlat.new()
		bstyle.bg_color = Color(0.22, 0.16, 0.06, 1)
		bstyle.border_width_left = 2
		bstyle.border_width_right = 2
		bstyle.border_width_top = 2
		bstyle.border_width_bottom = 2
		bstyle.border_color = Color(0.65, 0.47, 0.15, 1)
		bstyle.corner_radius_top_left = 4
		bstyle.corner_radius_top_right = 4
		bstyle.corner_radius_bottom_left = 4
		bstyle.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", bstyle)
		btn.add_theme_color_override("font_color", Color(0.92, 0.78, 0.42, 1))
		row.add_child(btn)

		var costs = _get_cost_for_level(bld, current_level + 1)
		var parts = []
		for key in costs:
			if costs[key] > 0:
				parts.append("%s:%d" % [key, costs[key]])
		var cost_label = Label.new()
		cost_label.text = "  ".join(parts)
		cost_label.custom_minimum_size = Vector2(160, 0)
		cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_label.add_theme_font_size_override("font_size", 12)
		cost_label.add_theme_color_override("font_color", Color(0.60, 0.52, 0.35, 1))
		row.add_child(cost_label)

		building_list.add_child(row)

func _get_cost_for_level(bld: Dictionary, target_level: int) -> Dictionary:
	var costs = bld.base_cost.duplicate()
	for i in range(target_level - 1):
		for key in bld.cost_per_level:
			costs[key] = costs.get(key, 0) + bld.cost_per_level[key]
	return costs

func _do_build(bld: Dictionary, current_level: int) -> void:
	var target_level = current_level + 1
	if target_level > bld.max_level:
		return
	var costs = _get_cost_for_level(bld, target_level)
	if ResourceManager.pay(costs):
		GameState.buildings[bld.id] = target_level
		GameState._recalculate_base_stats()
		EventBus.building_built.emit(bld.id, target_level)
		if current_level == 0:
			_show_notification("%s repaired!" % bld.name, "#C8A84B")
		else:
			_show_notification("%s upgraded to Lv%d!" % [bld.name, target_level], "#C8A84B")
		_populate_building_list()
	else:
		_show_notification("Not enough materials!", "#FF4444")

# ── MENU PANEL ──────────────────────────────────────────────────────────────────

var menu_panel: Control

func _make_menu_panel() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.visible = false

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.78)
	menu_panel.add_child(bg)

	var box = Panel.new()
	var bw = 300
	var bh = 220
	box.set_position(Vector2((720 - bw) / 2.0, (1280 - bh) / 2.0))
	box.set_size(Vector2(bw, bh))
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.06, 0.04, 0.98)
	ps.border_width_left = 3
	ps.border_width_right = 3
	ps.border_width_top = 3
	ps.border_width_bottom = 3
	ps.border_color = Color(0.72, 0.52, 0.18, 1)
	ps.corner_radius_top_left = 6
	ps.corner_radius_top_right = 6
	ps.corner_radius_bottom_left = 6
	ps.corner_radius_bottom_right = 6
	box.add_theme_stylebox_override("panel", ps)
	menu_panel.add_child(box)

	var vbox = VBoxContainer.new()
	vbox.set_position(Vector2(20, 20))
	vbox.set_size(Vector2(bw - 40, bh - 40))
	vbox.add_theme_constant_override("separation", 14)
	box.add_child(vbox)

	for item in [["Save Game", func(): GameState.save_game(); _show_notification("Game saved.", "#C8A84B")],
				 ["Main Menu", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
				 ["Close",     func(): menu_panel.visible = false]]:
		var b = Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(bw - 40, 52)
		b.add_theme_font_size_override("font_size", 17)
		var bs = StyleBoxFlat.new()
		bs.bg_color = Color(0.18, 0.14, 0.08, 1)
		bs.border_width_left = 2
		bs.border_width_right = 2
		bs.border_width_top = 2
		bs.border_width_bottom = 2
		bs.border_color = Color(0.65, 0.47, 0.15, 1)
		bs.corner_radius_top_left = 5
		bs.corner_radius_top_right = 5
		bs.corner_radius_bottom_left = 5
		bs.corner_radius_bottom_right = 5
		b.add_theme_stylebox_override("normal", bs)
		b.add_theme_color_override("font_color", Color(0.92, 0.78, 0.42, 1))
		b.pressed.connect(item[1])
		vbox.add_child(b)

	ui_layer.add_child(menu_panel)

# ── GAME LOOP ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if building_active and build_countdown > 0:
		build_countdown -= delta
		if build_timer_label and is_instance_valid(build_timer_label):
			build_timer_label.text = "⚙ REPAIRING  %ds" % ceili(build_countdown)
		if build_countdown <= 0:
			building_active = false
			_finish_repair()
		return

	day_night_timer += delta
	if day_night_timer >= FULL_CYCLE:
		day_night_timer -= FULL_CYCLE
		_advance_day()
	_adjust_day_night_overlay()
	GameState.day_timer = day_night_timer

func _advance_day() -> void:
	GameState.current_day += 1
	GameState.is_night = false
	GameState.process_daily_production()
	_check_zombie_attack()
	GameState.save_game()
	EventBus.day_passed.emit(GameState.current_day)
	_refresh_day_display()

func _adjust_day_night_overlay() -> void:
	var fraction = day_night_timer / FULL_CYCLE
	var alpha: float
	if fraction < 0.55:
		var df = fraction / 0.55
		if df < 0.1:
			alpha = lerpf(0.3, 0.0, df / 0.1)
		elif df > 0.9:
			alpha = lerpf(0.0, 0.3, (df - 0.9) / 0.1)
		else:
			alpha = 0.0
		GameState.is_night = false
	else:
		var nf = (fraction - 0.55) / 0.45
		alpha = lerpf(0.3, 0.55, nf)
		GameState.is_night = true
	day_night_overlay.color = Color(0.0, 0.0, 0.1, alpha)

func _check_zombie_attack() -> void:
	var data = _load_json("res://data/zombies.json")
	if data == null: return
	var chance = data.attack_triggers.daily_chance + GameState.noise_level
	if randf() < chance:
		var key = "small"
		if GameState.current_day > 7: key = "medium"
		if GameState.current_day > 14: key = "large"
		var horde = data.horde_sizes[key]
		_trigger_zombie_attack(key, randi_range(horde.min, horde.max))

func _trigger_zombie_attack(_key: String, size: int) -> void:
	var data = _load_json("res://data/zombies.json")
	if data == null: return
	EventBus.zombie_attack_started.emit(size)
	var def = GameState.base_defense
	var killed = 0
	var lost = 0
	for i in range(size):
		if randi() % 100 < def * 2:
			killed += 1
		else:
			var alive = []
			for s in GameState.survivors:
				if s.alive: alive.append(s)
			if alive.size() > 0:
				var t = alive[randi() % alive.size()]
				var zt = data.zombie_types[randi() % data.zombie_types.size()]
				t.health -= zt.damage
				if t.health <= 0:
					t.alive = false
					lost += 1
					EventBus.survivor_died.emit(t.name)
	EventBus.zombie_attack_ended.emit(lost)
	_show_notification("Attack! %d zoms. Killed: %d. Lost: %d." % [size, killed, lost],
		"#FF4444" if lost > 0 else "#FFAA00")
	GameState.noise_level = max(0, GameState.noise_level - 0.15)
	if GameState.alive_count() <= 0 and GameState.survivors.size() > 0:
		EventBus.game_over.emit("All survivors lost.")

# ── DISPLAY ──────────────────────────────────────────────────────────────────────

func _refresh_resource_display() -> void:
	wood_label.text  = "🪵 %d" % ResourceManager.get_resource("wood")
	stone_label.text = "🪨 %d" % ResourceManager.get_resource("stone")
	metal_label.text = "⚙ %d"  % ResourceManager.get_resource("metal")
	gold_label.text  = "🪙 %d" % ResourceManager.get_resource("gold")

func _refresh_day_display() -> void:
	var nt = "🌙" if GameState.is_night else "☀"
	day_label.text = "%s Day %d" % [nt, GameState.current_day]

func _show_notification(text: String, color: String = "#FFFFFF") -> void:
	notification_label.text = text
	notification_label.modulate = Color(color)
	notification_label.visible = true
	notification_timer.start()

func _on_notification_timeout() -> void:
	notification_label.visible = false

func _on_resource_changed(_r, _a, _t) -> void:
	_refresh_resource_display()

func _on_day_passed(_d) -> void:
	_refresh_day_display()

func _on_game_over(reason: String) -> void:
	_show_notification("GAME OVER: " + reason, "#FF0000")
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK: return null
	return json.get_data()
