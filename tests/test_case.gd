class_name TestCase
extends RefCounted

var failures: Array[String] = []


func check(cond: bool, msg: String = "check failed") -> void:
	if not cond:
		failures.append(msg)


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, var_to_str(expected), var_to_str(actual)])
