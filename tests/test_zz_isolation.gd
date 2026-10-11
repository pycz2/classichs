extends TestCase
## Runs last (file order): no earlier test may leave a path at the player's real file.


func test_tests_never_use_the_real_files() -> void:
	for pair in [[Settings.path, Settings.DEFAULT_PATH], [Profile.path, Profile.DEFAULT_PATH],
			[DeckStore.path, DeckStore.DEFAULT_PATH], [Progress.path, Progress.DEFAULT_PATH]]:
		check(pair[0] != pair[1], "test path in use, not " + pair[1])
