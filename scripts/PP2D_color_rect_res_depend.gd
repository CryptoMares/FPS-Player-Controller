extends ColorRect

func _ready():
	# Call this function to set the initial size
	_update_size()
	# Connect the size_changed signal to update the size when the window is resized
	get_viewport().connect("size_changed", self._update_size.bind(self))

# Remove the _notification function

func _update_size():
	var viewport_size = get_viewport().size
	custom_minimum_size = viewport_size
