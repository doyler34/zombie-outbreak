class_name UIStyle
extends RefCounted
## Shared UI styling — the game's "wasteland brass" look in one place.
##
## Every panel and button in the game builds its styles from these
## helpers, so a re-skin is a one-file change. If the art direction
## graduates to a full Godot Theme resource later, only this file and
## the theme swap out.

const BRASS := Color(0.72, 0.52, 0.18)
const BRASS_BRIGHT := Color(0.95, 0.78, 0.28)
const TEXT_WARM := Color(0.92, 0.78, 0.42)
const TEXT_DIM := Color(0.62, 0.55, 0.40)
const PANEL_BG := Color(0.07, 0.06, 0.04, 0.97)
const BUTTON_BG := Color(0.18, 0.14, 0.08)
const DANGER := Color(0.85, 0.25, 0.15)


static func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_border_width_all(3)
	s.border_color = BRASS
	s.set_corner_radius_all(8)
	s.set_content_margin_all(14)
	return s


static func button_style(bg: Color = BUTTON_BG, border: Color = BRASS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(6)
	s.set_content_margin_all(10)
	return s


## Apply the standard look (normal/hover/pressed/disabled) to a Button.
static func style_button(btn: Button, font_size: int = 18) -> void:
	btn.add_theme_stylebox_override("normal", button_style())
	btn.add_theme_stylebox_override("hover", button_style(BUTTON_BG.lightened(0.08)))
	btn.add_theme_stylebox_override("pressed", button_style(BUTTON_BG.darkened(0.3)))
	btn.add_theme_stylebox_override("disabled",
		button_style(Color(0.12, 0.11, 0.10), Color(0.3, 0.28, 0.24)))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", TEXT_WARM)
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.38, 0.34))


static func make_button(text: String, font_size: int = 18) -> Button:
	var btn := Button.new()
	btn.text = text
	style_button(btn, font_size)
	return btn
