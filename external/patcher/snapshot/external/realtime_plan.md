# Real-time, modular architecture - the plan (working document)

Goal (the user, 2026-11-20): nothing ever blocks the player. Everything is made of small
components assembled into bigger ones; every operation takes a fraction of a second of a frame
(time-sliced on the main thread, the heavy part on worker threads); what isn't ready yet shows as
a placeholder and is replaced as soon as it is - chunk by chunk, for planets and solar systems.

## Principles
1. Work units: a job is small (a chunk, a region's plan, a picture) - < ~30 ms on a worker in a
   browser, its result taken in on the main thread within a per-frame budget (a few ms).
2. Streaming by need: what's near the player first, outward; far things later or never.
3. Placeholders everywhere: a sprite (ProcArt.sprite), ground (a flat plate of the planet's
   ground colour), a building or a creature not out yet - the real thing replaces it in place.
4. Nothing waits: no loading screen, no "wait for all X"; gameplay works on what's there
   (ungenerated ground isn't walkable yet; it's generated before you can reach it).
5. Deterministic per unit: a chunk or a region generates the same from its seed, in any order.

## Stage 1 - the planet surface, chunked (done 2026-11-20)
Units:
- Planet constants (once, fast): noise objects, the water shape's parameters (drawn from the
  planet's rng), the height normalisation (lo/hi from a coarse 1/8 sample of the whole planet),
  the site height (commonest walkable band, same coarse sample).
- Region plan (REGION 110 tiles; the pad's own plan first): raw terrain of the region (+margin),
  then its village (palace, houses, plots levelled, citizens), pirate band, wild gate, industry
  sites (gas giant), fauna - each from a seed of (planet, region). Its edits (levelled plots,
  discs, clear spots) are what chunks apply.
- Gen chunk (GEN 32 tiles = 2 scenery chunks): raw terrain of chunk + margin, the edits of the
  regions it overlaps, terrain bands, crags closed, tile levels (smoothed 3x3 twice), plots and
  spots levelled, natural ramps (hash), linking ramps inside the chunk (BFS: every level component
  linked where a ramp fits), islands' causeways (a deterministic lattice), the chunk's tiles
  (TileMapLayer cells per level), its map pixels (hill-shaded), its ground_data. On a worker;
  returned as chunk-local arrays; copied into the planet's N x N arrays on the main thread.
- Streaming: chunks ordered by distance to the pilot (the pad's first); a few on workers at once;
  taken in within ~3 ms a frame; scenery, buildings, gates, creatures and people only where their
  chunk is in; the ground pictures (GroundChunks) redrawn where a chunk lands.
- Placeholder ground: the planet's ground colour as a plate under everything, real tiles over it
  as their chunks come.
- The surface opens at once (no build to wait for); landing = the animation only.

## Later stages
2. Solar systems: every system piece (planets, stations, belts, ships) a component made in slices
   as it comes into range; nothing built whole on arrival.
3. Other heavy one-off work (Ship Computer pages, Talos screens, galaxy generation) - the same
   pattern: a job queue with a frame budget.

## Progress log
- 2026-11-20: plan written; reading the surface's consumers of the planet arrays.
- 2026-11-20: stage 1 done - SurfacePlanner + streaming in planet_surface.gd; full suite green (stream_all in the
  whole-planet tests). Next: the asset memory pool (priority by use, budget 2x need, unloads reported) and the
  loading console; then stage 2.
- 2026-11-20: memory pool (AssetPool) + loading console done; suite 298 green. Next: stage 2 (solar systems in
  slices), then the heavy one-offs (Ship Computer first open, Talos, galaxy generation); re-measure FPS on a quiet
  machine (the last tour ran beside another game: surfaces 20-35% under baseline, not trustworthy).
- 2026-11-20: stage 2 done - a system's pieces stream in nearest first (main.gd _piece queue), the scene live
  after ~150 ms; every landable surface built ahead and pooled; console scrolls/folds, memory map. Another
  session works on ui.gd dismantle, warmup.gd, the Ship Computer / Talos first opens (stage 3) - main.gd and
  event_log.gd are this session's.
