# Bear Contact Specials & The Charge-Past Contract

Shipped 2026-08-29 (Lemon's brief): chargers must carry PAST the player and
circle back instead of grinding a downed body, and the bear gets two
manhandling attacks — the jaw grab-and-toss and the rear-up press. Spec
mirror lives in the Myrkfell project (claude/bear-moves-charge-past.md).

## The mercy rule (Enemy.gd — every mob)

`Enemy._target_down(t)`: a target with a non-empty `kd_phase` (players,
including the rise) or `knocked` (ragdolled creatures) is DOWN, and nothing
starts a NEW attack on it:

- `_do_combat` melee branch: swings hold (`attack_cd` floored at 0.35) while
  the target is down — the mob keeps shuffling/jockeying instead.
- `_start_strong` is never entered on a downed target (both call sites).
- An in-flight charge deals no damage to an already-downed target — it just
  barrels past.
- The pending melee hit (damage lands mid-swing) also checks.

## The charge-past (side-throw chargers, i.e. the boar)

In the side-throw branch of the active strong attack:

- After the hit, `strong_dir` VEERS ~17 deg opposite the side the player was
  flung (`-_throw_side * 0.30` tangent blend), so the runpast clears the
  player's capsule instead of grinding against it.
- `_face(strong_dir)` now runs during the charge, so the nose follows the
  veer.
- Boar `strong_runpast` 0.55 -> 0.80 (~9 m of committed follow-through at
  charge speed 12), then the duelist machinery swings it wide and back into
  its circling orbit (duel_range 11, lean 1.1) until the next charge window.

Result: charge -> hit flings you aside -> boar thunders past -> wheels around
-> circles -> charges again. It never stands on you.

## The bear's hands (Critter.gd contact specials)

Dex flags `grab` / `press` (black_bear carries both; any species with a jaw
pivot can). Rolled in `_pick_move()` at contact range inside a BLUFFER
charge: press 34%, grab 34%, plain swipe otherwise — all gated on cooldowns
(`_grab_cd` 16 s, `_press_cd` 22 s), on the target being a player, standing,
and unmounted, and on the player actually exposing the manhandle surface
(has_method guards keep LabPlayer suites green by construction).

A move runs as its own frame-owner (`_move_tick`), riding the signature clip
as its clock (`_move_t = _sig_t`), so brain and body cannot drift.

### bear_grab (2.5 s)

Lunge (nose drops, jaw gapes) -> clamp check at t=0.14 (2.6 m) ->
`Player.creature_grab()`: dash i-frames DODGE it, a perfect guard PARRIES it
(bear staggers via on_parried), a shield does not stop it (strong bite,
guard-break). On a catch: clamp bite 0.9x attack_power, the player's body
hangs off `grab_anchor()` (live jaw-pivot position, read player-side every
frame), two wrench ticks (0.16x each), then at t=0.70 the head whips LEFT
and the player is thrown to the bear's left (7.5 m/s lateral + up) into a
real knockdown. The bear then walks off to its right for 1.6 s.

Escape: hit the bear — ANY damage while a move runs calls `_move_abort()`
and it drops you on the spot (gentle release, no fling). Knockdown, parry,
and `peace_settle` (flipping to Peaceful mid-grab) abort the same way.

### bear_press (3.6 s)

Rear (0-0.26, the window to get out from under) -> lean check at 2.9 m ->
`Player.creature_press()`: movement crushed to 12%, no jumping; a dash out
past 3.4 m tears free (the bear comes down on nothing). Otherwise the bear
bends over the player — front hip pivots ride the bear_stand arc up, then
reach FORWARD onto them — bites at t=0.48 (guard-break) and t=0.64
(0.55x / 0.45x), then the shove at t=0.78: `creature_press_end(fling)` puts
the player flat (knockdown away from the bear), and the bear walks off to a
random side for 2.2 s before re-engaging.

### While the player is down

The bear (any bluffer in CHARGE) prowls a ~3.8 m half-circle at amble speed,
huffing (`_warn_sig`), attack_cd floored — the fight resumes when the player
finds their feet. Combined with `_move_recover` (the walk-aside), the bear
never wails on a grounded player.

## Player-side states (Player.gd)

- `grabbed_by` / `grab_t`: physics early-out `_update_grabbed` — position
  lerped hard onto `grab_anchor().pos`, velocity zeroed, body_col disabled
  (no capsule fights with the bear's box), camera rolls with the shaking,
  body_rig dangles at 38 deg; mouse-look stays live. Safety: releases itself
  if the holder dies/vanishes or after 4.5 s.
- `grab_release(vel)`: re-enables collision, restores rig/camera, and with a
  real vector runs `_start_knockdown` + a vertical kick — the throw.
- `pressed_by` / `press_t`: not an early-out — movement continues at 12%
  (struggling), no jump; auto-clears if the bear dies, leaves 4.2 m, or
  after 3.4 s.
- `_stand_up_hard()` clears BOTH states + re-enables body_col — death and
  load can never leave you hanging off a jaw that no longer has you (same
  class of bug as the body_rig respawn shift, claude/bugfix-respawn-camera).

## Suite

`tests/GameModeTests.gd` (landed 2026-08-29, was previously only a project
doc) — sections `t_bear_moves` (flags, pick gating, mercy, cooldowns,
abort, pose math for both clips) plus the cave rule and surface amnesty.
Run: `godot --headless --path . --script res://tests/GameModeTests.gd`.
Not yet executed headless (no device shell this session) — parse-verified
in-editor, behaviors verified in the live game.
