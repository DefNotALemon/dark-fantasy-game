import io, sys
P = "/Users/lemon/dark-fantasy-game/scripts/Grass.gd"
s = io.open(P, encoding="utf-8").read()
orig = s
T = "\t"

def sub(old, new, label):
    global s
    if old not in s:
        print("MISS:", label); sys.exit(1)
    if s.count(old) != 1:
        print("AMBIGUOUS(%d):" % s.count(old), label); sys.exit(1)
    s = s.replace(old, new)
    print("ok:", label)

# 1 -------------------------------------------------------------- the flag
sub(
"const SHORT_KEEP := 0.94         ## short grass keeps nearly all of its draw",
"""const GPU_FESCUE := true         ## v3: RED FESCUE outside the valley is placed by
\t\t\t\t\t\t\t\t ## a particle process shader (scripts/GrassGPU.gd) and
\t\t\t\t\t\t\t\t ## never touches this file's chunks. `std` was 284,653
\t\t\t\t\t\t\t\t ## of 429,116 tufts — 66% of the meadow and effectively
\t\t\t\t\t\t\t\t ## all of the _fill_mm cost. Flip false for the pure
\t\t\t\t\t\t\t\t ## v2.7 MultiMesh meadow; everything else is unchanged
\t\t\t\t\t\t\t\t ## either way, and the valley is ALWAYS CPU-placed
\t\t\t\t\t\t\t\t ## because you can dig it.
const SHORT_KEEP := 0.94         ## short grass keeps nearly all of its draw""",
"const GPU_FESCUE")

# 2 -------------------------------------------------------------- the fields
sub(
"var _apply_q: Array = []         ## [key, placed] waiting for a main-thread fill",
"""var _apply_q: Array = []         ## [key, placed] waiting for a main-thread fill

## --- v3: the GPU fescue field ------------------------------------------------
var _gpu: GrassGPU = null        ## null when GPU_FESCUE is off or there is no bake
var _gpu_on := false             ## read from WORKER THREADS in _place_chunk, so it
\t\t\t\t\t\t\t\t ## is a plain bool set once on the main thread and never
\t\t\t\t\t\t\t\t ## touched again — do not make this a property lookup""",
"var _gpu")

# 3 -------------------------------------------------------------- setup
sub(
"""\t_ow = Overworld.inst
\tif _ow != null:
\t\t_sea = _ow.sea_level
\tset_draw_distance(draw_dist)""",
"""\t_ow = Overworld.inst
\tif _ow != null:
\t\t_sea = _ow.sea_level
\t## v3. The GPU field owns the fescue everywhere the baked heightfield is the
\t## ground; this system keeps the valley (voxel, diggable) and the other eight
\t## kinds. It has to exist BEFORE warm(), because _place_chunk asks it whether
\t## to skip `std` and _tall_noise_at reads its baked tile.
\tif GPU_FESCUE and _ow != null:
\t\tvar g := GrassGPU.new()
\t\tg.name = "GrassGPU"
\t\tadd_child(g)
\t\t## The rect the voxel field answers for — the same bounds _place_chunk's
\t\t## `on_field` test uses, so the two grounds meet exactly at the rim and
\t\t## neither leaves a bald metre for the other to have covered.
\t\tvar fmin := Vector2(field.origin.x + 2.0 * CaveField.VOX,
\t\t\tfield.origin.z + 2.0 * CaveField.VOX)
\t\tvar fmax := Vector2(field.origin.x + float(CaveField.SX - 3) * CaveField.VOX,
\t\t\tfield.origin.z + float(CaveField.SZ - 3) * CaveField.VOX)
\t\tif g.setup(_mat, _mesh["std"] as Array, seed_v, fmin, fmax):
\t\t\t_gpu = g
\t\t\t_gpu_on = true
\t\telse:
\t\t\tg.queue_free()
\tset_draw_distance(draw_dist)""",
"setup: build GrassGPU")

# 4 -------------------------------------------------------------- tall noise
sub(
"""func _tall_noise_at(wx: float, wz: float) -> bool:
\treturn _tall.get_noise_2d(wx, wz) > TALL_T""",
"""func _tall_noise_at(wx: float, wz: float) -> bool:
\t## v3: when the GPU field is up, BOTH sides read the SAME baked tile.
\t## FastNoiseLite here and a hand-rolled simplex in GLSL would agree to about
\t## three decimals and then disagree at the edge of every patch — and a
\t## disagreement here is a BALD RING: no fescue, because the shader thinks the
\t## patch is tall, and no bunchgrass, because this thinks it is not.
\tif _gpu != null:
\t\treturn _gpu.tall_noise(wx, wz)
\treturn _tall.get_noise_2d(wx, wz) > TALL_T""",
"_tall_noise_at")

# 5 -------------------------------------------------------------- the skip
sub(
"\t\tvar kind := _pick_kind(rng, in_tall, _cut_cells.has(_cut_cell(wx, wz)), moist, lush)",
"""\t\tvar kind := _pick_kind(rng, in_tall, _cut_cells.has(_cut_cell(wx, wz)), moist, lush)
\t\t## v3. Off the voxel field, RED FESCUE belongs to the GPU — it is placed by
\t\t## the particle shader from the same heightfield, the same noise tiles and
\t\t## the same draw roll, so dropping it here removes the instances and not the
\t\t## grass. Everything else on this square metre is still ours.
\t\tif _gpu_on and not on_field and kind == K_STD:
\t\t\tcontinue""",
"_place_chunk: skip std off-field")

# 6 -------------------------------------------------------------- draw distance
sub(
"\tdetail_dist = draw_dist * DETAIL_CULL_F",
"""\tdetail_dist = draw_dist * DETAIL_CULL_F
\tif _gpu != null:
\t\t_gpu.set_draw_distance(draw_dist)""",
"set_draw_distance forward")

# 7 -------------------------------------------------------------- stats
sub(
"""\t\t"in_flight": _pending.size(), "awaiting_fill": _apply_q.size(),
\t\t"streaming": _ow != null}""",
"""\t\t"in_flight": _pending.size(), "awaiting_fill": _apply_q.size(),
\t\t"streaming": _ow != null,
\t\t## v3: the tufts this system no longer carries. `tufts` above is the
\t\t## MultiMesh half only — add these for what is actually standing.
\t\t"gpu": {} if _gpu == null else _gpu.stats()}""",
"stats merge")

io.open(P, "w", encoding="utf-8").write(s)
print("WROTE %d -> %d bytes" % (len(orig), len(s)))
