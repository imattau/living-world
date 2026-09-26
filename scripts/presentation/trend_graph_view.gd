class_name TrendGraphView
extends Control

var _point_years: PackedInt32Array = PackedInt32Array()
var _points: PackedFloat32Array = PackedFloat32Array()
var _war_years: PackedInt32Array = PackedInt32Array()
var _famine_years: PackedInt32Array = PackedInt32Array()
var _max_year: int = 1

func set_data(
	point_years: PackedInt32Array,
	points: PackedFloat32Array,
	war_years: PackedInt32Array,
	famine_years: PackedInt32Array,
	max_year: int
) -> void:
	_point_years = point_years
	_points = points
	_war_years = war_years
	_famine_years = famine_years
	_max_year = maxi(1, max_year)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.09, 0.35))
	if _points.size() < 2 or size.x <= 0.0 or size.y <= 0.0:
		return

	var bottom_margin := 14.0
	var top_margin := 4.0
	var chart_height := maxf(1.0, size.y - top_margin - bottom_margin)

	var max_value := _points[0]
	var min_value := _points[0]
	for value in _points:
		max_value = maxf(max_value, value)
		min_value = minf(min_value, value)
	if is_equal_approx(max_value, min_value):
		max_value += 1.0

	var previous_point := Vector2.ZERO
	var has_previous := false
	for index in _points.size():
		var x_fraction := float(_point_years[index]) / float(_max_year)
		var y_fraction := (_points[index] - min_value) / (max_value - min_value)
		var point := Vector2(x_fraction * size.x, top_margin + (1.0 - y_fraction) * chart_height)
		if has_previous:
			draw_line(previous_point, point, Color("9fd4ff"), 2.0)
		previous_point = point
		has_previous = true

	var tick_top := size.y - bottom_margin + 3.0
	for year in _famine_years:
		var x := (float(year) / float(_max_year)) * size.x
		draw_line(Vector2(x, tick_top), Vector2(x, tick_top + 4.0), Color("d8b25c"), 2.0)
	for year in _war_years:
		var x := (float(year) / float(_max_year)) * size.x
		draw_line(Vector2(x, tick_top + 5.0), Vector2(x, size.y - 1.0), Color("c96a5a"), 2.0)
