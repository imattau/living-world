extends Control

func _ready() -> void:
	var title := Label.new()
	title.text = "Living World"
	title.add_theme_font_size_override("font_size", 32)
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.position.x -= title.size.x / 2.0
	title.position.y -= title.size.y / 2.0
