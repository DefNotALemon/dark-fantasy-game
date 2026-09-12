extends SceneTree
## A marching-squares border is a TRUE 90-degree staircase, not the diagonal ramp
## the first probe used. And the thing you can SEE is not the turn angle, it is
## the FACET LENGTH in view pixels at the deepest zoom the panel allows.
const CELL_PX_AT_1 := 4.0
const ZOOM_MAX := 10.0
func _init() -> void:
	var stair := PackedVector2Array()
	for i in range(12):
		stair.append(Vector2(float(i), float(i)))
		stair.append(Vector2(float(i) + 1.0, float(i)))
	for passes: int in [1, 2, 3, 4, 5]:
		var cur := MapLayers.chaikin(stair, passes)
		var worst := 0.0
		for q: Vector2 in cur:
			var best := INF
			for i2 in range(stair.size() - 1):
				var a := stair[i2]
				var b := stair[i2 + 1]
				var t := clampf((q - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
				best = minf(best, q.distance_to(a.lerp(b, t)))
			worst = maxf(worst, best)
		var sharp := 0.0
		var longest := 0.0
		for i3 in range(cur.size() - 1):
			longest = maxf(longest, cur[i3].distance_to(cur[i3 + 1]))
		for i4 in range(1, cur.size() - 1):
			var u := (cur[i4] - cur[i4 - 1]).normalized()
			var v := (cur[i4 + 1] - cur[i4]).normalized()
			sharp = maxf(sharp, rad_to_deg(acos(clampf(u.dot(v), -1.0, 1.0))))
		## the sagitta of one facet pair: how far the drawn line sits from the
		## smooth curve it is approximating, in VIEW PIXELS at max zoom
		var facet_px := longest * CELL_PX_AT_1 * ZOOM_MAX
		var sag := facet_px * 0.5 * tan(deg_to_rad(sharp) * 0.5)
		print("passes=%d pts=%4d off_wall=%.4f cell  sharpest=%5.1f deg  longest facet=%6.2f px at 10x  sagitta=%.3f px" % [
			passes, cur.size(), worst, sharp, facet_px, sag])
	quit()
