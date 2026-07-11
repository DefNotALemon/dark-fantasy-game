# The Withering — Concept Art Prompts

Tuned text-to-image prompts built from the game design doc. Paste into Midjourney, DALL·E, Leonardo, Firefly, or any text-to-image tool. Notes on tool-specific syntax at the bottom.

## Shared style anchor (paste into every prompt)
> gritty-realism low-poly 3D, faceted geometry, dark fantasy, atmospheric fog and drifting ash, dramatic cinematic lighting, desaturated slate and indigo base palette with vivid ember-orange and frost-blue accents, snow-white highlights, moody but vibrant, volumetric light, game key art, highly detailed, 8k

Keep this consistent so every image looks like the same game.

---

## 1. Hero key art (store page banner)
A lone armored wanderer stands on a windswept cliff edge, seen from behind and slightly below, raising a longsword wreathed in glowing frost-blue elemental energy that lights the scene. Towering jagged snow-capped low-poly mountains rise behind, a ruined castle perched on a distant peak, a dragon silhouetted in flight against a dusk sky streaked with cold teal aurora and a hazy ember sun on the horizon. Ash and dust drift through the air.
`+ shared style anchor`
*Aspect: 16:9 (wide banner)*

## 2. The wanderer (character key art)
Full-body hero shot of a battle-worn adventurer in weathered layered armor and a tattered cloak, gripping a hand-and-a-half sword, faceted low-poly armor plates catching cold rim light, breath misting in frozen air, grim determined posture, neutral grey environment so the character pops.
`+ shared style anchor`
*Aspect: 2:3 (portrait)*

## 3. Snowy peaks — dragon territory
A vast frozen mountain range at blue hour, enormous low-poly faceted peaks, a massive dragon perched on a crag exhaling embers, its internal fire glowing through its body, swirling snow and ash, tiny ruined watchtower for scale, cold aurora overhead.
`+ shared style anchor`
*Aspect: 16:9*

## 4. Plains at dusk — goblin camp & distant castle
Rolling grassland and flower fields under a burning orange-and-violet sunset, a fortified city with a castle silhouetted on a far hill, a goblin war-camp in the foreground with crude tents and a campfire, faceted low-poly terrain, long shadows, ash on the breeze.
`+ shared style anchor`
*Aspect: 16:9*

## 5. The shifting cave (world event)
Interior of a collapsing underground cavern, faceted low-poly rock walls, boulders frozen mid-fall, a shaft of pale light breaking through dust clouds, an undead skeleton emerging from the dark, ominous and claustrophobic, ember torchlight vs cold shadow.
`+ shared style anchor`
*Aspect: 16:9*

## 6. Combat moment — frost blade vs skeleton
First-person-style dramatic angle of a glowing frost-imbued sword mid-swing shattering an undead skeleton that is withering into glowing dust, faceted low-poly bone and weapon, motion energy, sparks of frost, dark dungeon backdrop.
`+ shared style anchor`
*Aspect: 16:9*

## 7. Weapon showcase (material + element)
Studio-style hero render of a fantastical longsword forged from glowing meteoric metal, frost aura licking the blade, faceted low-poly design, resting on dark stone, ember forge-light behind, trophy presentation.
`+ shared style anchor`
*Aspect: 1:1 (square)*

## 8. Boss key art — the Lich
A towering undead lich in a ruined mountain dungeon, faceted low-poly robes and crown, hollow glowing eyes, surrounded by lesser skeletons and floating ash, cold green-blue necrotic light vs ember braziers, foreboding scale, throne of bone.
`+ shared style anchor`
*Aspect: 16:9*

---

## Tool-specific tips
- **Midjourney:** append `--ar 16:9 --style raw --v 6`. Add `--stylize 250` for more painterly drama. Put the style anchor first.
- **DALL·E 3:** write as one flowing paragraph (it ignores `--flags`); state the aspect ("a wide cinematic banner") in words.
- **Leonardo / SDXL:** use the style anchor as the prompt and add a negative prompt: `blurry, low detail, flat shading, cartoon, photorealistic faces, text artifacts, watermark`.
- **Firefly:** set content type to "Art," pick a dark/cinematic style preset, paste the scene description.
- **Consistency:** reuse the exact shared style anchor every time, and keep the same wanderer description (#2) whenever the character appears, so your set looks cohesive.
