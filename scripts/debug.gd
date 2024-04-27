extends PanelContainer

@onready var property_container = %VBoxContainer

#var property
var frames_per_second : String

func _ready():
	# Set global reference to to self in Global Singleton
	GlobalScript.debug = self

	visible = false
	#add_debug_property("FPS",frames_per_second)

func _process(delta):
	frames_per_second = "%.2f" % (1.0/delta)
	#property.text = property.name + ": " + frames_per_second

func _input(event):
	if event.is_action_pressed("debug"):
		visible = !visible

func add_property(title : String, value, order):
	var target
	target = property_container.find_child(title,true,false) # Try to find label with the same name
	if !target: # If there's no current Label node for property (i.e. initial load)
		target = Label.new() # Create new Label node
		property_container.add_child(target) # Add new node as child to Vbox container
		target.name = title # Set name to title
		target.text = target.name + ": " + str(value) # Set text value
	elif visible:
		target.text = title + ": " + str(value) # Set text value
		property_container.move_child(target,order) # Reorder property based on given order value
