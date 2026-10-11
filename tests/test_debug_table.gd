extends TestCase


func test_example_position_builds() -> void:
	var j := JSON.new()
	eq(j.parse(FileAccess.get_file_as_string("res://data/debug_example.json")), OK, "valid JSON")
	var r := Scenario.build(j.data)
	eq(r.error, "", "the example builds")
