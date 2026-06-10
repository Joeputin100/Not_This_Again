extends GutTest

# Soda-Crush flourish text helpers (owner notes 2026-06-10).

const FB = preload("res://scripts/flourish_banner.gd")

func test_first_letter_bbcode_enlarges_each_word():
	var out: String = FB.first_letter_bbcode("SUGAR CASCADE!", 100)
	assert_eq(out, "[font_size=118]S[/font_size]UGAR [font_size=118]C[/font_size]ASCADE!")

func test_first_letter_bbcode_single_word():
	var out: String = FB.first_letter_bbcode("ROLLED!", 100)
	assert_eq(out, "[font_size=118]R[/font_size]OLLED!")

func test_split_rows_two_words():
	assert_eq(FB.split_rows("PERFECT VOLLEY!"), ["PERFECT", "VOLLEY!"])

func test_split_rows_three_words():
	assert_eq(FB.split_rows("JELLY BEAN FRENZY!"), ["JELLY", "BEAN FRENZY!"])

func test_split_rows_single_word_gets_gold_rush_header():
	assert_eq(FB.split_rows("ROLLED!"), ["GOLD RUSH", "ROLLED!"])

func test_style_routing():
	assert_eq(FB.style_for("COUNT_3", 0.4), "count")
	assert_eq(FB.style_for("GO", 0.7), "count")
	assert_eq(FB.style_for("SUGAR_CASCADE", 0.85), "goldrush")
	assert_eq(FB.style_for("RAMPAGE!", 0.85), "divine")
	assert_eq(FB.style_for("TASTY!", 0.45), "rise")

func test_every_goldrush_key_is_a_preset():
	for k in FB.GOLDRUSH_KEYS:
		assert_true(FB.PRESETS.has(k), "%s preset exists" % k)
