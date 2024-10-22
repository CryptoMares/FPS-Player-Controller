extends PanelContainer

func _process(_delta):
	var viewport_size = get_viewport_rect().size
	position = viewport_size / 2 - size / 2
