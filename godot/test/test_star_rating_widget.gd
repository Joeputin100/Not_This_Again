extends GutTest

const StarRating = preload("res://scripts/star_rating.gd")

func test_candy_path_by_difficulty():
	assert_string_ends_with(StarRating.candy_tex_path(1), "star_pepper.png")
	assert_string_ends_with(StarRating.candy_tex_path(2), "star_gold.png")
	assert_string_ends_with(StarRating.candy_tex_path(3), "star_gummy.png")
	assert_string_ends_with(StarRating.candy_tex_path(4), "star_sugar.png")

func test_candy_path_clamps_unknown_difficulty():
	assert_string_ends_with(StarRating.candy_tex_path(99), "star_pepper.png")

func test_slot_count_is_three():
	assert_eq(StarRating.SLOT_FRACS.size(), 3)
