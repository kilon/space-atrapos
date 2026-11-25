class_name SmoothTurn
extends RefCounted
## A body turning to face a new way the way a body does: its turn speeding up,
## held at a top rate, easing off as it comes round - never snapped round. A
## reversal (the new way straight behind) goes round one side, the side it was
## already turning (else the right) - not flickering between the two. One for
## each walker, citizen, creature (its turn speed kept between frames).

var rate := 9.0     # how hard it turns toward the new way (1/s: the remaining angle times this)
var top := 7.5      # rad/s at most (a half turn in about half a second)
var accel := 16.0   # how quickly its turn speed follows (1/s)
var w := 0.0        # its turn speed now (rad/s, about `up`)


func _init(p_rate := 9.0, p_top := 7.5, p_accel := 16.0) -> void:
	rate = p_rate
	top = p_top
	accel = p_accel


## `facing` turned toward `to` about `up` over `delta` (both level: across `up`).
func step(facing: Vector3, to: Vector3, up: Vector3, delta: float) -> Vector3:
	var f := (facing - up * facing.dot(up))
	var t := (to - up * to.dot(up))
	if f.length() < 0.001 or t.length() < 0.001:
		w = 0.0
		return facing
	f = f.normalized()
	t = t.normalized()
	var a := f.signed_angle_to(t, up)
	if absf(a) > PI - 0.15 and absf(w) > 0.01:
		a = absf(a) * signf(w)   # (straight behind: on round the way it's turning)
	elif absf(a) > PI - 0.15:
		a = -absf(a)   # (from standing: round to the right)
	var want := clampf(a * rate, -top, top)
	w = lerpf(w, want, 1.0 - exp(-delta * accel))
	var stepped := w * delta
	if absf(a) < 0.002 or (signf(stepped) == signf(a) and absf(stepped) >= absf(a)):
		w = 0.0
		return t   # (come round: there)
	return f.rotated(up, stepped).normalized()
