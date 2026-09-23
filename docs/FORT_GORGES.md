# Fort Gorges

A six-bastion granite star on a **built island** in Portland Harbor, due east
of the Old Port quay. Real Fort Gorges sits on Hog Island Ledge; Knox already
owns the Penobscot pentagon — this is a different work, smaller, and it does
not punch the sea.

Files: `scripts/FortGorges.gd`, `tests/GorgesTests.gd`.
Flag: `World.USE_GORGES` — one `false` and the star, its island and its map
marker all stay out of the world. `USE_FORT` is still Knox-only.

---

## Where, and why there

World XZ **(172.0, 1056.0)**, parade at sea + 4 m (about y = −18.5).

Bake Portland is **(−85.7, 1056)**. Map scale is ~1:47, so Hog Island Ledge
would sit about fifty metres off the Old Port — inside the city's 190 m pad,
on top of lots and the quay. Knox was seated from the bake then built at
player scale; the same rule here would eat Portland.

The heightfield east of the quay was walked cell by cell against
`maine_water.r16`. There is **no dry ledge** large enough for a 50–70 m fort
that is not the town pad itself (flattened to y ≈ 18). The first honest
harbor water, 100 % wet in a 76 m square and **zero pad cells**, is this
site: 258 m due east of the bake marker, ~90 m off the seawall. From the
quay the star is a landmark across a short run of harbor.

The whole island footprint was re-checked at 4 m: every sample is sea, none
of them sit inside `Cities.CORE_R`. Cities.gd was not touched.

---

## Punch vs island

**Island. No punch.**

A punched hole takes the ground away and puts nothing back. Punching sea is
a rectangular window into the void, visible from the seawall. The island is
granite from 8 m below the parade (through ~2 m of water into the bed) up to
the paving, so the fort carries its own floor. The sink never approaches
World's −60 m trapdoor.

`Overworld.punch_hole` already accepts many rects; Gorges simply does not
register one.

---

## The frame

Local **+X is east** (open harbor), **+Z is south**, **y = 0 is the parade**.
`CORNERS` is a twelve-point hex-star, clockwise from the north tip. Casemates
are the four west faces, looking at Portland. One sally on the east bastion.
One stair, parade to rampart, on the south curtain.

One mesh per material, `keep_probe` for the suite, group `"fort"`.
**526 solid boxes in 5 meshes** (~6,500 triangles). About 64 m across the
bastion tips — smaller than Knox, still a harbor landmark.

---

## Tests

```
godot --headless --path . --script res://tests/GorgesTests.gd
```

**84 assertions, all green.** Headless: `build_flat` + `keep_probe`, every
opening proved by `clear_line`. `MIN_ASSERTIONS = 55` is the lost-section
floor. FortTests (Knox) stays **99/0** with zero edits.

---

## If you want to change it

- **Move it**: `SITE_X` / `SITE_Z`, then re-check a 76 m square against
  `maine_water.r16` and Portland's 190 m pad. Do not sit it on wet cells
  you then punch.
- **Turn it off**: `World.USE_GORGES = false`.
