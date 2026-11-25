extends Node
## Dedicated server idle screen (headless): logs the lobby. Rounds load world.tscn.

func _ready() -> void:
	Net.connect("chat", self, "_on_chat")
	Net.connect("countdown", self, "_on_count")
	print("[sahur-net] lobby open · %d/%d operatives · everyone ready starts the countdown" % [Net.players.size(), Net.MAX_PLAYERS])


func _on_chat(t: String) -> void:
	print("[lobby] ", t)


func _on_count(n: int) -> void:
	if n > 0:
		print("[sahur-net] starting in %d" % n)
	elif n < 0:
		print("[sahur-net] countdown cancelled")
