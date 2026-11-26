extends TestCase
## The jump gates in space (JumpGate): the painted ring around the vortex
## (data/sprites/gate_*), the vortex turning through its frames, the opening
## sized to sit under the ring's rim, and the burst a jump plays.

func test_jump_gate_is_painted() -> void:
	for k in ["gate_ring", "gate_ring_lit", "gate_vortex1", "gate_vortex2", "gate_vortex3", "gate_sparkle", "gate_burst"]:
		check(ProcArt.has_sprite(k), "the sprite %s is cut" % k)
	var g := JumpGate.new()
	g.target_name = "Test"
	tree.root.add_child(g)
	await tree.process_frame
	check(g._ring_lit != null and g._vortex.size() == 3, "the gate draws the painted ring and its three vortex frames")
	# The vortex fills the ring's opening, under its rim: bigger than the
	# opening, smaller than the ring.
	var k := g._k()
	var vortex_r: float = g._vortex[0].get_width() * 0.5 * k * 1.1
	var ring_r: float = g._ring_lit.get_width() * 0.5 * k
	check(vortex_r > ring_r * 0.6 and vortex_r < ring_r * 0.75, "the vortex sits in the opening (%.0f of a %.0f ring)" % [vortex_r, ring_r])
	check(ring_r > JumpGate.USE_RADIUS, "flying into the ring uses the gate")
	g.flash()
	await tree.process_frame
	check(g._burst >= 0.0, "a jump starts the burst")
	g._process(JumpGate.BURST_TIME + 0.1)
	check(g._burst < 0.0, "and it ends")
	g.queue_free()
