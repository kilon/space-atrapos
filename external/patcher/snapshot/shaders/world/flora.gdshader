// A planet's plants (CosmosFlora, scattered by CosmosPlanet) - all but the
// trees' leaf cards (leaf_flora.gdshader): no cut-outs, so no discard - the
// meadows' grass and flowers keep the GPU's early depth test. The body:
// flora.gdshaderinc.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/world/flora.gdshaderinc"
