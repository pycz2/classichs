class_name Transport
extends Node
## A message channel to the other player. Messages are Dictionaries sent as JSON.

signal opened
signal received(msg)  # Dictionary, or null for a broken packet
signal closed(reason: String)


func send(_msg: Dictionary) -> void:
	push_error("Transport.send not implemented")


func close(_reason := "") -> void:
	pass
