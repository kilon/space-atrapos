// The trees (CosmosFlora: their crowns and near meshes) - flora.gdshaderinc
// with LEAF_CARDS: their leaf cards cut into leaves (discard - only here, not
// for the grass and flowers: flora.gdshader).
shader_type spatial;
render_mode cull_disabled;

#define LEAF_CARDS
#include "res://shaders/world/flora.gdshaderinc"
