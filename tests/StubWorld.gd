extends Node
## Minimal stand-in for World.gd so SkyMenu has something to find.
var _sky: SkyRig
var _daynight: DayNight
var _weather: Weather
var cloud_calls: Array[int] = []
func weather() -> Weather: return _weather
func set_cloud_mode(idx: int) -> void:
	cloud_calls.append(idx)
	if _sky: _sky.set_cloud_mode(idx)
