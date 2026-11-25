class_name TestCase
extends RefCounted
## Base class for test suites (tests/test_*.gd). Every method named test_*
## is run by tests/run_tests.gd; it may await. Use the check helpers - a
## failed check is recorded and the test goes on.

var failures: Array = []
var tree: SceneTree
## Engine errors a test causes on purpose (substrings) - not failures.
var expect_errors: Array = []


func check(cond: bool, what: String) -> bool:
	if not cond:
		failures.append(what)
	return cond


func check_eq(a: Variant, b: Variant, what: String) -> bool:
	return check(a == b, "%s: expected %s, got %s" % [what, str(b), str(a)])


func check_lt(a: float, limit: float, what: String) -> bool:
	return check(a < limit, "%s: %.3f is not below %.3f" % [what, a, limit])


## Before / after each test (override when needed).
func setup() -> void:
	pass


func teardown() -> void:
	pass
