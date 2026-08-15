# ABAKÜS ONE — DESIGN BIBLE

**Official Industrial Design Specification**
Document AB1-IDS-001 · Revision 1.0 · Status: **CONTROLLED — MASTER**
Issued by: Industrial Design, Abaküs One

> **Archival note (added when this file was filed into `brand-production/`)**: the source
> document supplied for this pipeline had UTF-8/Latin-1 mojibake throughout (e.g. `AbakÃ¼s`
> for `Abaküs`, `Â·` for `·`, mangled box-drawing tree characters in the collection-tree and
> asset-hierarchy diagrams). This copy corrects the brand name and the common punctuation
> mojibake (`·`, `±`, `°`) for readability; the diagram tree-drawing glyphs in §13.2 and §15.1
> were not hand-repaired character-by-character to avoid introducing transcription errors —
> treat the *tree structure and labels* as authoritative, not the exact box-drawing glyphs.
> If a clean re-export of the original source ever becomes available, replace this file with
> it rather than continuing to hand-patch this copy. Every number, tolerance, hex value, and
> rule below is reproduced exactly as supplied — nothing was reinterpreted.

---

## 0. DESIGN THESIS

The abacus is the oldest computer still in daily use. Abaküs One does not restore it, decorate it, or nostalgize it. It **re-manufactures** it to the tolerances of a modern precision instrument.

The governing sentence, from which every decision in this document descends:

> **A single machined slab, containing sixty-five moving parts, that reads as one object at rest.**

Three consequences follow, and they are non-negotiable:

1. **Nothing protrudes.** Beads, rods and beam all live *inside* the frame's silhouette. Viewed from the side, Abaküs One is a rectangle. The mechanism is discovered, not displayed.
2. **One accent, one time.** The object is achromatic except for a single 1.2 mm mark. Colour is a punctuation mark, not a finish.
3. **Weight is a feature.** At ~720 g the object does not slide, does not rattle, and does not need to be held. It is furniture-adjacent.

### 0.1 Reference calibration

| Reference | What we take | What we explicitly reject |
|---|---|---|
| **Apple** | Radius discipline; part-count reduction; the machined unibody as a moral position | Glossy chamfers; over-symmetry; "friendly" |
| **Bang & Olufsen** | Material honesty; acoustic design as a specified discipline; horizontal repose | Sculptural flourish; asymmetric drama |
| **Nothing** | Restraint as identity; monochrome with one signal; typography as ornament | Transparency gimmick; consumer-electronics idiom |
| **Leica** | Tool-grade knurl and grip; the red dot; the sense that it will outlive the owner | Chrome; leatherette; heritage cosplay |

### 0.2 Prohibited design vocabulary

Absolutely excluded: primary-colour beads · wooden frames of any species · turned finials · bevelled "picture frame" mouldings · painted or printed graphics of any kind · visible fasteners · injection-moulded parts in any visible surface · gloss above 15 GU · drop shadows, bevels or "shiny" treatments in any 2D asset · any bead diameter-to-height ratio that reads as a sphere or a disc.

---

## 1. OVERALL PROPORTIONS

### 1.1 Configuration

**Soroban 1:4** (one heaven bead / four earth beads), **13 rods**.

Rationale: the 1:4 configuration carries the least redundant material of any surviving abacus system. Thirteen rods yields a 3.4:1 plan ratio — the proportion of a soundbar or a rangefinder body, not of a school aid. Any 2:5 (suanpan) configuration is rejected outright: the extra bead rows read as clutter and as "vintage."

### 1.2 Master envelope

| Axis | Dimension | Notes |
|---|---|---|
| **X — Width** | **280.0 mm** | Overall |
| **Y — Depth** | **84.0 mm** | Overall |
| **Z — Thickness** | **18.0 mm** | Overall, feet excluded |
| Feet protrusion | 1.2 mm | Total desk height 19.2 mm |
| **Target mass** | **720 g ± 25 g** | Fully assembled |

### 1.3 Governing ratios

```
X : Y  =  280 : 84   =  10 : 3      (3.333)
X : Z  =  280 : 18   =  15.56 : 1
Y : Z  =   84 : 18   =   4.667 : 1
```

**The 10:3 plan ratio is locked.** All rod-count variants (§16) must resolve to 10:3 ±3% by adjusting rod pitch and end margin, never by changing frame thickness.

### 1.4 The unified module — `u`

All dimensions derive from a single module:

> **u = 2.0 mm**

| Element | Value | In modules |
|---|---|---|
| Frame thickness (Z) | 18.0 mm | 9u |
| Stile width | 14.0 mm | 7u |
| Rail width | 13.0 mm | 6.5u |
| Rod pitch | 18.0 mm | 9u |
| Bead diameter | 14.0 mm | 7u |
| Bead height | 7.0 mm | 3.5u |
| Beam height | 7.0 mm | 3.5u |
| Rod diameter | 2.0 mm | 1u |
| End margin | 18.0 mm | 9u |

No new dimension may be introduced to this product that is not an integer or half-integer multiple of `u`. This rule is the single strongest guarantee of visual coherence across future SKUs.

---

## 2. FRAME DIMENSIONS

### 2.1 Construction

Single-piece **CNC-machined billet frame**. Closed rectangular ring — no mitres, no joints, no corner hardware. The frame is one part. This is the central manufacturing decision of the product and it is not open to value-engineering.

### 2.2 Members

| Member | Qty | Width | Depth (Z) | Notes |
|---|---|---|---|---|
| Stile (left/right) | 2 | 14.0 mm | 18.0 mm | Carries rod terminations |
| Rail (top/bottom) | 2 | 13.0 mm | 18.0 mm | Structural + acoustic damping mass |
| Reckoning beam | 1 | 7.0 mm | 18.0 mm | Separate part, press-fit + bonded |

**Deliberate asymmetry:** stiles are 1.0 mm wider than rails (14 vs 13). This is not an error. Optically, the long horizontal rails read wider than they are; the 1 mm compensation makes the frame appear uniform. Do not "correct" it.

### 2.3 Aperture

| Dimension | Value | Derivation |
|---|---|---|
| Inner clear width | **252.0 mm** | 280 − (2 × 14) |
| Inner clear depth | **58.0 mm** | 84 − (2 × 13) |
| Rod span (first–last) | 216.0 mm | 12 gaps × 18.0 |
| End margin (stile face → first rod) | 18.0 mm | (252 − 216) / 2 |

The end margin equals exactly one rod pitch. The frame therefore reads as a continuation of the rod rhythm rather than as a container placed around it.

### 2.4 Beam position — the asymmetry that makes the object

Measured from the **top rail** inner face:

| Zone | Extent | Contents |
|---|---|---|
| Heaven zone | 0 – 15.0 mm | 1 bead (7.0) + 8.0 mm travel |
| **Reckoning beam** | 15.0 – 22.0 mm | 7.0 mm |
| Earth zone | 22.0 – 58.0 mm | 4 beads (28.0) + 8.0 mm travel |

The beam sits at **25.9% of the aperture depth**. The resulting 1 : 2.4 split between heaven and earth zones is the object's primary compositional tension and must be preserved in every variant.

### 2.5 Travel

**8.0 mm total free travel per zone**, in both zones, identically. Travel is set by the sum of bead heights, not by shimming — it is a consequence of the arithmetic, and it must remain identical top and bottom so that the mechanism feels calibrated rather than assembled.

### 2.6 Underside

- Milled relief pocket, 260 × 64 mm, **0.8 mm deep**, R6 corners. Creates a shadow gap; the object appears to float 0.8 mm above its own footprint.
- Four **recessed foot pads**, Ø10 mm × 1.2 mm proud, inset 22 mm from each corner.
- Laser-etched identity block, centred, **rear-lower quadrant only**: wordmark, model designation, serial, origin. Etch depth 0.03 mm, no fill, no infill paint.
- No screws, no labels, no regulatory printing on any visible face. Compliance marks live in the etch block or nowhere.

---

## 3. ROD SPECIFICATION

| Parameter | Value |
|---|---|
| Diameter | **Ø2.0 mm h7** (−0.000 / −0.010) |
| Effective length | 58.0 mm + 2 × 4.0 mm engagement = 66.0 mm |
| Quantity | 13 |
| Pitch | 18.0 mm, cumulative tolerance ±0.05 mm over full span |
| Straightness | ≤0.02 mm over full length |
| Surface | Ra 0.2 µm, centreless ground |
| Termination | Blind bores in stiles, 4.0 mm deep, interference fit + structural adhesive |

### 3.1 Why 2.0 mm

Below 1.6 mm the rod reads as wire (toy). Above 2.5 mm it reads as structure and competes with the frame. At 2.0 mm — exactly 1u, exactly 1/7 of bead diameter — the rod is a **line**, not an object. In the hero render at 50 mm it subtends less than one pixel-pair of specular width; it disappears and the beads appear to hover in the aperture. This is the intended effect.

### 3.2 Glide system

Rods carry a **DLC (diamond-like carbon) coating**, 1.5 µm, matte anthracite. Bead bore is Ø2.6 mm — a 0.3 mm annular clearance which permits a fractional tilt, so beads glide rather than bind, and land with a defined stop.

**No polymer bushings. No PTFE sleeves. No lubricant.** Any liner would be a plastic part, and the product's promise is that there are none. The DLC-on-steel pairing delivers the required µ ≈ 0.10 without them.

### 3.3 Acoustic specification *(mandatory, not advisory)*

The sound of a bead landing is a primary product surface and is specified as such:

| Parameter | Target |
|---|---|
| Impact transient — dominant band | 3.5 – 5.5 kHz |
| Decay to −40 dB | **< 30 ms** |
| Peak SPL @ 300 mm | 52 – 58 dB(A) |
| Character | Single click. No ring, no buzz, no secondary rattle. |

Achieved by frame mass, the 0.8 mm underside relief acting as a decoupling gap, and elastomer foot pads. If a prototype rings, the frame is wrong — not the beads.

---

## 4. CORNER RADIUS SYSTEM

Radii are a **closed vocabulary**. Five values exist. No sixth may be introduced.

| ID | Value | Application |
|---|---|---|
| **R-A** | **7.0 mm** | Outer plan corners of frame (XY) |
| **R-B** | **4.0 mm** | Inner aperture corners (XY) |
| **R-C** | **1.5 mm** | All top/bottom edge fillets (Z transitions) |
| **R-D** | **0.4 mm** | Beam edges, underside pocket edges, all secondary breaks |
| **R-E** | **0.15 mm** | Universal micro-break. Every remaining edge. No true sharp edge exists on this product. |

### 4.1 The R-A rule

R-A = 7.0 mm = **exactly half the stile width**. The outer corner is therefore a perfect semicircular termination of the stile — the side member simply ends in its own radius. This is why the corners look inevitable rather than styled.

### 4.2 Curvature continuity

R-A and R-B are **G2 continuous** (curvature-continuous blends), not simple arcs. Under grazing light a plain G1 fillet produces a visible highlight break at the tangent point; G2 produces a single sweeping highlight that travels the corner unbroken. This is the difference between a machined part and a designed one, and it is visible at 300 mm.

R-C, R-D and R-E may be G1.

### 4.3 Edge condition

The frame's top and bottom faces meet the outer wall via **R-C 1.5 mm fillet only**. No chamfer. No polished chamfer. A bright chamfer would introduce a hard specular line and a second surface finish — both prohibited. The object has one skin.

---

## 5. BEAD PROPORTIONS

### 5.1 Master geometry

| Parameter | Value |
|---|---|
| Major diameter (equator) | **Ø14.0 mm** |
| Height along rod axis | **7.0 mm** |
| **Aspect ratio** | **2.000 : 1 — LOCKED** |
| Bore | Ø2.6 mm |
| Quantity | 65 (13 heaven + 52 earth) |
| Mass, each | ~2.8 g (316L) |

### 5.2 Profile

The bead is a **double-truncated bicone with G2-blended equator** — not a sphere, not a lens, not a traditional turned bead.

- Cone half-angle: **26.6°** (the angle whose tangent is 0.5 — a direct consequence of the 2:1 ratio)
- Equator blend: **R1.2 mm**, G2
- Polar faces: **flat annulus, Ø5.0 mm**, perpendicular to the rod axis
- Pole-to-cone transition: **R0.6 mm**

**Why the flat poles matter.** Traditional soroban beads meet point-to-point; contact is a knife edge, which chips, and which sounds thin. The Ø5.0 mm annulus gives a defined face-to-face landing: it produces the specified 3.5–5.5 kHz click, it distributes stack load, and — critically — when four earth beads are stacked, the flats read as a **continuous machined column** rather than a string of separate objects. This is the single most important detail in the product.

### 5.3 Clearances

| Gap | Value |
|---|---|
| Bead Ø14.0 vs rod pitch 18.0 | **4.0 mm** air between adjacent bead equators |
| Bead Ø14.0 vs frame Z 18.0 | **2.0 mm reveal** above and below |

The 2.0 mm reveal (1u) is the mechanism of §0 consequence 1: **the bead never breaks the frame's silhouette.** Verify this in every variant.

### 5.4 Heaven bead differentiation

The heaven bead is **geometrically identical** to the earth bead. Differentiation is by **finish only** (§7.4). Two moulds, two part numbers and two inspection routines are not justified by a 13-piece contrast; a finish delta achieves it at zero part-count cost. This is the correct answer.

---

## 6. MATERIAL SPECIFICATION

| # | Part | Material | Process |
|---|---|---|---|
| 1 | Frame | **6082-T6 aluminium**, billet | 5-axis CNC, single setup for all A-surfaces |
| 2 | Reckoning beam | 6082-T6 aluminium | CNC, press-fit + structural epoxy |
| 3 | Rods (13) | **316L stainless**, cold drawn | Centreless ground, DLC coated |
| 4 | Beads (65) | **316L stainless**, bar stock | CNC turned, gang-tumble deburr |
| 5 | Feet (4) | Silicone elastomer, **Shore 60A** | Compression moulded, recessed |
| 6 | Unit marker | Ceramic-filled epoxy inlay | Ø1.2 mm bore, filled, faced flush |

### 6.1 Material rationale

**Frame — 6082-T6, not 6061.** 6082 anodises to a finer, more uniform grain and holds a crisper machined edge. The cost delta is negligible at this volume; the visual delta is not.

**Beads — 316L, not aluminium, not brass.** Three reasons, in order:
1. **Mass.** 2.8 g per bead gives the stack the inertia that produces a confident landing. Aluminium beads (0.95 g) feel hollow and *sound* like a toy — the exact failure mode the brief prohibits.
2. **Wear.** These beads will be moved several thousand times per week for decades. Anodised aluminium wears through at the bore and at the equator. 316L develops a hand-polish patina at the equator instead — the object improves with use.
3. **Contrast.** Steel against anodised aluminium gives a genuine material contrast without introducing colour.

**Brass is rejected.** It reads as vintage, it tarnishes unevenly, and it introduces warmth the palette does not have.

**No wood. No plastic in any visible surface. No glass.**

### 6.2 Bill of materials

| Assembly | Parts | Unique parts |
|---|---|---|
| Frame group | 2 | 2 (frame, beam) |
| Rod group | 13 | 1 |
| Bead group | 65 | 1 |
| Feet | 4 | 1 |
| Marker | 1 | 1 |
| **Total** | **85** | **6** |

**Six unique parts.** This number is a design target and appears on the spec sheet.

---

## 7. SURFACE FINISH

### 7.1 Frame

| Stage | Specification |
|---|---|
| 1 — Machining | All A-surfaces cut in one setup. Max scallop 0.005 mm. No visible tool path. |
| 2 — Texture | Fine glass-bead blast, **120–150 grit**, uniform 4-bar pressure, single direction pass |
| 3 — Anodise | **Type II, 10 µm**, hot DI seal |
| 4 — Verification | **Ra 0.8 – 1.2 µm** · **Gloss 8 – 12 GU @ 60°** |

The 8–12 GU window is narrow and deliberate. Below 8 GU the surface goes chalky and reads as powder coat. Above 15 GU it becomes reflective and reads as consumer plastic. Ten gloss units is the value at which anodised aluminium reads unmistakably as **metal that has been finished on purpose**.

### 7.2 Beads — earth (52 pcs)

| Stage | Specification |
|---|---|
| Turning | Fine feed, continuous cut across the bicone |
| Finish | **Circumferential micro-turn, Ra 0.4 µm** |
| Treatment | Passivated. **No coating.** |

The micro-turn is invisible at arm's length and becomes a fine concentric ring pattern under macro — a Leica-grade detail that rewards inspection without announcing itself. Critically, it produces a **moving anisotropic highlight** as the bead slides: light travels along the equator. This is the product's signature optical event and every hero render must capture it.

### 7.3 Beads — heaven (13 pcs)

Identical geometry and Ra. Additional **PVD, matte graphite-black**, 1.0 µm.

Result: thirteen dark beads above the beam, fifty-two bright beads below. The value structure of the object is legible from three metres, in a single glance, with zero colour and zero graphics.

### 7.4 Beam

Same anodise as frame but **bead-blast to 180 grit** — a half-step finer. The beam therefore sits ~2 GU brighter than the frame: perceptible as a distinct plane, never as a different colour.

### 7.5 Prohibited finishes

Polished/mirror anodise · brushed or grained finishes of any direction · gloss clear coat · powder coat · paint · print · pad print · silk-screen · hydro-dip · two-tone anodising · logos on any A-surface.

---

## 8. COLOUR PALETTE

The palette is **five achromatics and one signal**. Values are sRGB hex for digital and render reference; production colour is controlled by anodise standard panel, not by hex.

### 8.1 Core palette

| Name | Hex | L* | Application |
|---|---|---|---|
| **AB-01 GRAPHITE** | `#2E3033` | 20 | Frame — signature colourway |
| **AB-02 TITAN** | `#8A8D8F` | 57 | Frame — natural anodise colourway |
| **AB-03 CHALK** | `#E4E1DB` | 90 | Frame — light colourway |
| **AB-04 STEEL** | `#B9BCC0` | 76 | Earth beads (material, not applied) |
| **AB-05 ONYX** | `#1B1C1E` | 10 | Heaven beads, rods (PVD / DLC) |

### 8.2 The signal

| Name | Hex | Application |
|---|---|---|
| **AB-06 SIGNAL** | `#B4341F` | Unit-rod marker, **Ø1.2 mm, one instance** |

A single oxide-red dot, inlaid flush into the beam face, marking the unit rod. It is the only chromatic element on the entire object. It is functional — it is how you find the ones column.

**Rules for AB-06:**
- Exactly one physical instance per product. Ever.
- May not appear on packaging exteriors, in typography, in UI, or in any secondary surface.
- May not be scaled, repeated, or used as a brand device.
- Its power is entirely a function of its scarcity. Protect it absolutely.

### 8.3 Colourways at launch

| SKU | Frame | Heaven | Earth | Character |
|---|---|---|---|---|
| **AB1-GR** | Graphite | Onyx | Steel | Signature. Highest contrast. |
| **AB1-TI** | Titan | Onyx | Steel | Monolithic. Most machine-like. |
| **AB1-CH** | Chalk | Onyx | Steel | Editorial. Highest bead legibility. |

### 8.4 Environment palette *(renders, imagery, retail)*

| Name | Hex | Use |
|---|---|---|
| ENV-BG-DARK | `#141517` | Dark hero sweep |
| ENV-BG-MID | `#2A2C2F` | Neutral studio |
| ENV-BG-LIGHT | `#EFEDE8` | Light editorial sweep |
| ENV-SURFACE | `#3A3C40` | Desk / plinth |

No environment may introduce a hue not present above. No gradients between hues — value gradients only.

---

## 9. LIGHTING RECOMMENDATIONS

### 9.1 Principle

The subject is **matte anodise against anisotropic steel**. The lighting must therefore do two distinct jobs and must not confuse them:
- **Broad, soft light** to model the frame's form and reveal the anodise micro-texture.
- **Narrow, hard light** to write a specular line along the bead equators.

A single soft key does the first and fails the second. This is the most common failure in abacus imagery and it is why most abacus imagery looks like a product photo of a toy.

### 9.2 Standard studio rig

| Light | Type | Size | Position | Intensity | Temp |
|---|---|---|---|---|---|
| **KEY** | Area, soft | 1200 × 800 mm | Az 40° L, El 38°, dist 1.4 m | 100% | 5600 K |
| **EQUATOR STRIP** | Area, narrow | 900 × 40 mm | Az 0°, El 62°, dist 0.9 m | 65% | 5600 K |
| **FILL** | Area, very soft | 1600 × 1600 mm | Az 65° R, El 15°, dist 2.0 m | 18% | 5800 K |
| **RIM / GRAZE** | Area, narrow | 700 × 60 mm | Az 155° R, El 8°, dist 1.1 m | 45% | 6200 K |
| **AMBIENT** | Studio HDRI | — | Rot 0° | 0.12 strength | — |

### 9.3 Notes per light

**KEY** — Must be large enough that its reflection wraps the R-A corner without terminating inside the fillet. If you can see the softbox edge in the corner highlight, the box is too small.

**EQUATOR STRIP** — The signature light. Its long axis runs parallel to X so its reflection lands as a continuous bright line across all thirteen bead equators simultaneously. Elevation is critical: at 62° the line lands on the equator; at 50° it slips onto the upper cone and the beads read as spheres. Tune to ±2°.

**FILL** — Kept below 20%. Above that, shadow density collapses and the 18 mm frame stops reading as thick.

**RIM** — Low and behind, grazing. Its only job is to catch the 120-grit anodise texture at the top rail's outer fillet. Without it the frame renders as flat plastic. With it, the material is unmistakable.

**AMBIENT** — 0.12 only. Higher values wash the anodise and lift the blacks off the floor.

### 9.4 Light discipline

- **No coloured lights.** All sources 5400–6300 K. No blue rim, no warm accent, no gel of any kind.
- **No practical light sources in frame.**
- Shadow softness: contact shadows must remain crisp (bead-to-frame), ambient shadows soft. Do not globally blur.
- Any single light may be soloed and the render must still be legible. If soloing a light produces nothing readable, that light is decoration and should be deleted.

---

## 10. CAMERA ANGLES

Global: **physically-based camera, 36 × 24 mm sensor.** No lens distortion, no chromatic aberration, no vignette, no bloom, no lens flare — ever.

### 10.1 Approved shot list

| ID | Name | Focal | Position | Aperture | Focus |
|---|---|---|---|---|---|
| **CAM-01** | HERO 3/4 | **85 mm** | Az 32°, El 24°, dist 1.15 m | f/8 | Front-left R-A corner |
| **CAM-02** | PLAN | Orthographic | Az 0°, El 90° | — | — |
| **CAM-03** | FRONT ELEV | Orthographic | Az 0°, El 0° | — | — |
| **CAM-04** | SIDE ELEV | Orthographic | Az 90°, El 0° | — | — |
| **CAM-05** | MACRO BEAD | **100 mm macro** | Az 15°, El 12°, dist 0.28 m | f/5.6 | Bead equator |
| **CAM-06** | GRAZE | **135 mm** | Az 8°, El 6°, dist 1.6 m | f/11 | Beam face |
| **CAM-07** | EDGE | **85 mm** | Az 88°, El 4°, dist 1.0 m | f/9 | Frame edge |
| **CAM-08** | IN-USE | **50 mm** | Az 25°, El 45°, dist 0.65 m | f/4 | Hand contact point |

### 10.2 Rules

**Never below 50 mm.** A 35 mm or wider lens introduces the perspective exaggeration of lifestyle photography and destroys the object's proportional integrity. 85 mm is the house lens.

**CAM-01 elevation is 24°, not 45°.** At 45° the object flattens into a plan view and the 18 mm thickness — the whole point — disappears. At 24° the top face and the front edge are both legible and the slab reads as a slab.

**CAM-06 GRAZE is mandatory in every asset package.** It is the only view that proves the finish is anodised metal. It is the anti-plastic shot.

**Orthographic views (02/03/04)** are documentation, never marketing. Flat white or flat ENV-BG-LIGHT background, no shadow, no reflection, dimension callouts permitted.

**CAM-08** is the only view where a hand may appear. Hand must be unadorned — no rings, no watch, no manicure, no sleeve branding. The hand is a scale reference, not a lifestyle cue.

### 10.3 Prohibited camera moves and framings

Dutch angle · fisheye · extreme low hero angle ("monument shot") · rack focus as an effect · handheld shake · drone-style orbits · anything that implies motion the object cannot perform.

---

## 11. RENDERING STYLE

| Parameter | Setting |
|---|---|
| Engine | Cycles (path tracing) — mandatory for hero and macro |
| Samples | 3072 hero · 4096 macro · 1024 orthographic |
| Denoise | OpenImageDenoise, **Albedo + Normal passes on** |
| Max bounces | Total 12 · Diffuse 4 · **Glossy 8** · Transmission 4 |
| Clamp indirect | 8.0 |
| Colour management | **AgX**, Look: *Base* or *Punchy* only |
| Exposure | 0.0 baseline; ±0.3 EV maximum grade |
| Output | 32-bit EXR linear → grade → 16-bit deliverable |
| Resolution | 6000 × 4000 hero · 4000 × 4000 macro |

### 11.1 Rendering philosophy

**Photographic, not hyperreal.** The target is a credible studio photograph made with excellent equipment — not a render that announces itself as a render. Every parameter above serves that.

Glossy bounces are set to 8 (higher than typical) because the object's character lives in secondary reflections: bead-in-bead, bead-in-frame, frame-in-underside. Cut this to 4 and the beads go dead.

### 11.2 Mandatory

- Anisotropic BSDF on all bead surfaces, **tangent aligned circumferentially**. This is not optional; it is the material.
- Micro-normal map on frame (procedural noise, scale ~0.004, strength 0.15) reproducing the 120-grit blast.
- Contact shadows resolved — 0.8 mm underside gap must be visible as a real shadow line.
- Subtle edge wear on R-C fillets: **max 4% roughness reduction**, no colour shift. Enough to read as machined metal, never enough to read as "distressed."

### 11.3 Absolutely prohibited

Bloom · glare · lens flare · chromatic aberration · vignette · film grain above 0.5% · motion blur on stills · HDR "pop" grading · S-curves beyond AgX Punchy · saturation boost of any kind · any LUT other than the two named above · outlines, toon shading, or stylised passes · fake studio reflection cards visible in the surface.

### 11.4 Acceptance criteria

A render ships only if all four are true:

1. The **frame material is unambiguously anodised aluminium** — not painted, not plastic, not ceramic.
2. The **bead equator anisotropy is visible** as a travelling highlight.
3. The **18 mm thickness reads correctly** — the object looks like it weighs 720 g.
4. **AB-06 SIGNAL is the only chromatic element in frame.**

---

## 12. ANIMATION PRINCIPLES

### 12.1 Governing law

> **The object has mass and it has bearings. Nothing about it is springy.**

Every animation decision follows from that sentence.

### 12.2 Timing standard

| Event | Duration @ 24 fps | Easing |
|---|---|---|
| Single bead, full 8 mm travel | **9 frames** (375 ms) | Ease-out cubic |
| Stack of 4 beads moving together | **13 frames** (542 ms) | Ease-out cubic, slower tail |
| Bead settle at stop | **2 frames** | Linear, no overshoot |
| Value change (full number) | 18–24 frames | Staggered 2f per rod |
| Camera push-in | 96–144 frames | Ease-in-out sine |
| Camera orbit (max 35°) | 180–240 frames | Ease-in-out sine |

### 12.3 Motion rules

**Ease-out, never ease-in-out, for beads.** A bead is pushed. It accelerates immediately under the finger and decelerates against the stop. Ease-in on a bead makes it look self-propelled and magical — a toy behaviour.

**Zero overshoot. Zero bounce. Zero secondary oscillation.** A steel bead landing on a steel bead does not bounce. Overshoot is the single most reliable way to make this product look cheap. Delete every overshoot key.

**No squash and stretch. No anticipation. No follow-through. No arcs.** The classical animation principles are principles for characters. This object is a precision instrument; borrowing character-animation language from it is a category error and reads immediately as "toy."

**Beads move only on the rod axis (Y).** Any X or Z displacement, or any rotation, is a bug.

**Stagger, don't sync.** When multiple rods change, offset each by 2 frames. Perfect simultaneity reads as digital; a 2-frame cascade reads as mechanical and is far more satisfying.

### 12.4 Camera in motion

- Speed limit: max 12° of arc per second.
- No handheld simulation. Camera is on a motion-control rig and must look like it.
- Focus pulls only when following a specific mechanical event, never for mood.
- The camera never passes below the plane of the desk surface.

### 12.5 Audio sync

Where sound is used, the click transient (§3.3) lands **on the frame of contact — never 1 frame early, never late.** The perceived quality of the entire animation rests on this single alignment.

---

## 13. BLENDER ORGANIZATION

### 13.1 Scene units

| Setting | Value |
|---|---|
| Unit system | Metric |
| Unit scale | 0.001 |
| Length display | Millimeters |
| Separate units | On |
| Scene scale | **1 Blender unit = 1 mm** |

World origin sits at the **geometric centre of the frame footprint, on the underside plane (Z = 0).** The product occupies X ±140, Y ±42, Z 0–18. Every asset, every variant, forever.

### 13.2 Collection tree

```
AB1_MASTER
├── 00_CONTROL
│   ├── CTRL_root
│   ├── CTRL_beads_global
│   └── CTRL_value_readout
├── 10_GEO
│   ├── 11_FRAME
│   │   ├── AB1_GEO_frame_body
│   │   ├── AB1_GEO_frame_beam
│   │   └── AB1_GEO_frame_feet
│   ├── 12_RODS
│   │   └── AB1_GEO_rod_01 … _13
│   ├── 13_BEADS_HEAVEN
│   │   └── AB1_GEO_bead_hvn_r01 … _r13
│   ├── 14_BEADS_EARTH
│   │   └── AB1_GEO_bead_ert_r01p1 … _r13p4
│   └── 15_DETAIL
│       ├── AB1_GEO_marker_signal
│       └── AB1_GEO_etch_identity
├── 20_RIG
│   ├── AB1_RIG_armature
│   └── AB1_RIG_targets
├── 30_MAT
│   └── (material library — no objects)
├── 40_LIGHT
│   ├── AB1_LGT_key
│   ├── AB1_LGT_equator
│   ├── AB1_LGT_fill
│   ├── AB1_LGT_rim
│   └── AB1_LGT_hdri_ref
├── 50_CAM
│   └── AB1_CAM_01_hero … _08_inuse
├── 60_ENV
│   ├── AB1_ENV_sweep
│   └── AB1_ENV_plinth
└── 90_REF
    ├── AB1_REF_dimensions
    └── AB1_REF_blockout        [excluded from view layer]
```

### 13.3 Modelling standards

| Rule | Requirement |
|---|---|
| Topology | All-quad on A-surfaces. Triangles permitted only in non-deforming interior. |
| Normals | Custom split normals **off**. Shade Auto Smooth, 32° |
| Modifiers | Non-destructive. Bevel and Subdivision remain live until export. |
| Bevel | Weighted bevel by edge attribute — never manual loop cuts |
| Scale | All objects Scale 1.0, Rotation 0. **Apply transforms before commit.** |
| Naming | No `.001` suffixes anywhere in a committed file. Zero tolerance. |
| Origins | Each bead's origin at its own centroid. Each rod's origin at its base. |
| Duplication | Beads and rods are **linked duplicates** of a single master mesh |

### 13.4 Material library

| Slot | Name | Notes |
|---|---|---|
| M1 | `AB1_MAT_anodise_graphite` | Base 0.021, Rough 0.42, aniso 0 |
| M2 | `AB1_MAT_anodise_titan` | Base 0.24, Rough 0.42 |
| M3 | `AB1_MAT_anodise_chalk` | Base 0.76, Rough 0.44 |
| M4 | `AB1_MAT_steel_bead` | Metallic 1.0, Rough 0.22, **Aniso 0.65 circumferential** |
| M5 | `AB1_MAT_pvd_onyx` | Metallic 1.0, Rough 0.35, Base 0.012 |
| M6 | `AB1_MAT_dlc_rod` | Metallic 1.0, Rough 0.28 |
| M7 | `AB1_MAT_signal` | Base `#B4341F`, Rough 0.30 |
| M8 | `AB1_MAT_elastomer_foot` | Rough 0.85, subtle SSS |

Colourways are switched **only** by reassigning M1/M2/M3 on `AB1_GEO_frame_body` and `_beam`. No other change is permitted between SKUs.

---

## 14. NAMING CONVENTIONS

### 14.1 Object schema

```
AB1_<TYPE>_<PART>[_<POSITION>][_<VARIANT>][_<LOD>]
```

| Field | Values |
|---|---|
| Prefix | `AB1` (always) |
| TYPE | `GEO` `MAT` `LGT` `CAM` `RIG` `CTRL` `ENV` `REF` `TEX` |
| PART | lowercase, singular, no abbreviation unless in the approved list |
| POSITION | `r01`–`r27` (rod index) · `p1`–`p5` (bead position on rod) · `hvn` / `ert` |
| VARIANT | `graphite` `titan` `chalk` |
| LOD | `lod0` (hero) · `lod1` (mid) · `lod2` (real-time) |

### 14.2 Examples

```
AB1_GEO_bead_ert_r07p3
AB1_GEO_bead_hvn_r01
AB1_GEO_frame_body_graphite_lod0
AB1_GEO_rod_r13
AB1_MAT_anodise_graphite
AB1_LGT_equator
AB1_CAM_01_hero
AB1_CTRL_bead_r07
```

### 14.3 File schema

```
AB1_<CATEGORY>_<DESCRIPTOR>_v<MAJOR>.<MINOR>[_<STATUS>].<ext>
```

| STATUS | Meaning |
|---|---|
| *(none)* | Working |
| `_REV` | In review |
| `_APPR` | Approved, frozen |
| `_ARCH` | Archived, do not edit |

Examples:
```
AB1_MODEL_master_v2.4.blend
AB1_MODEL_master_v3.0_APPR.blend
AB1_RENDER_hero-3q_v1.2.exr
AB1_ANIM_beadslide_v1.0_REV.blend
AB1_DOC_designbible_v1.0_APPR.md
```

### 14.4 Rules

- **Lowercase for descriptors. UPPERCASE for TYPE and STATUS.** No exceptions.
- Underscore separates fields. Hyphen separates words *within* a field.
- No spaces. No `.001`. No `final`, `FINAL`, `final_v2`, `use-this-one`.
- Rod indices are always zero-padded to two digits.
- A renamed object must have every reference updated in the same commit.

---

## 15. ASSET HIERARCHY

### 15.1 Transform chain

```
AB1_CTRL_root                        [empty, plain axes — world anchor]
├── AB1_GEO_frame_body               [static]
│   ├── AB1_GEO_frame_beam           [parented, static]
│   ├── AB1_GEO_marker_signal        [parented, static]
│   ├── AB1_GEO_etch_identity        [parented, static]
│   └── AB1_GEO_frame_feet ×4        [parented, static]
├── AB1_CTRL_rod_r01 … r13           [empty, one per rod]
│   ├── AB1_GEO_rod_rNN              [static]
│   ├── AB1_CTRL_bead_hvn_rNN        [Y-translate, limited]
│   │   └── AB1_GEO_bead_hvn_rNN
│   └── AB1_CTRL_bead_ert_rNNp1..p4  [Y-translate, limited, chained]
│       └── AB1_GEO_bead_ert_rNNpN
└── AB1_CTRL_value_readout           [empty, drives/reads numeric state]
```

### 15.2 Constraint rules

- Every bead controller carries a **Limit Location** constraint on Y matching its zone extents. It is mechanically impossible to animate a bead through the beam or through the frame.
- Earth beads p1–p4 are **chain-parented for push behaviour**: moving p1 toward the beam carries p2–p4 with it, exactly as the physical object behaves. This is the single most valuable rigging decision in the file.
- No bead is ever keyed directly. Animation touches controllers only.
- `AB1_CTRL_root` is the only object with a non-zero world transform. Moving the product moves this and nothing else.

### 15.3 LOD ladder

| LOD | Poly budget | Use |
|---|---|---|
| **lod0** | ~2.4 M | Hero stills, macro, print |
| **lod1** | ~380 K | Animation, turntables, preview |
| **lod2** | ~48 K | Real-time, AR, configurator, web |

All three LODs share identical origins, identical naming, identical material slot order. An LOD swap is a collection visibility toggle — never a re-link.

### 15.4 Linked-library discipline

`AB1_MODEL_master.blend` is the **only** file containing geometry. Every render scene, animation and configurator **links** from it. Geometry is never appended, never copied, never edited downstream. One source of truth.

---

## 16. FUTURE SCALABILITY

### 16.1 Product ladder

| Model | Rods | Width | Depth | Ratio | Position |
|---|---|---|---|---|---|
| **AB1 COMPACT** | 9 | 208 mm | 84 mm | 2.48 : 1 | Travel / desk secondary |
| **AB1** | **13** | **280 mm** | **84 mm** | **3.33 : 1** | **Reference product** |
| **AB1 PRO** | 17 | 352 mm | 84 mm | 4.19 : 1 | Professional / studio |
| **AB1 STUDIO** | 21 | 424 mm | 84 mm | 5.05 : 1 | Institutional / display |

**Invariants across the entire ladder — never change:**
Frame thickness 18.0 · Depth 84.0 · Rod pitch 18.0 · Bead Ø14.0 × 7.0 · Beam 7.0 at 25.9% · All five radii · The module `u` = 2.0 mm

**The only variable is rod count.** Width follows deterministically:

```
Width = (n − 1) × 18 + 36 + 28      [pitch span + 2 end margins + 2 stiles]
```

COMPACT falls below the 10:3 target ratio and is therefore the one permitted exception — approved because the 84 mm depth invariant is more important to family coherence than the plan ratio.

### 16.2 Parametric readiness

Build the master file so that four driver values regenerate every variant:
`rod_count` · `rod_pitch` · `bead_diameter` · `frame_thickness`

Frame width, aperture, end margin, rod array, bead array and beam position must all resolve from these. A new SKU should be **one integer change**, not a remodel.

### 16.3 Roadmap

| Horizon | Programme | Notes |
|---|---|---|
| Near | Colourway expansion | Only via anodise. New hue requires Design Council approval and an update to §8. |
| Near | Materials edition | Titanium frame, Grade 5, bead-blast, unanodised. Bead and rod spec unchanged. |
| Mid | AB1 SENSE | Optional magnetic bead position sensing in stiles. **Zero change to exterior geometry.** If it is visible, it is rejected. |
| Mid | Companion application | Reads state; teaches soroban method. Uses the same six-part visual language. |
| Long | Wall edition | Vertical orientation, 21 rods. All invariants hold; feet replaced by flush cleat. |
| Long | Archive / Serial 001–100 | Hand-finished, individually numbered. No design change. |

### 16.4 Extension governance

Any proposed extension must be tested against six questions. **A single "no" blocks it.**

1. Does it hold every invariant in §16.1?
2. Does it use only materials from §6 and colours from §8?
3. Does it introduce a seventh unique part? *(If yes — justify or reject.)*
4. Does it keep AB-06 SIGNAL as one instance, 1.2 mm, functional?
5. Does anything protrude beyond the frame silhouette?
6. Would it survive CAM-06 GRAZE without looking like plastic?

### 16.5 Amendment procedure

This document is versioned and controlled. Sections **§1.3 (10:3 ratio)**, **§1.4 (module u)**, **§4 (radius vocabulary)**, **§5.1 (2:1 bead ratio)** and **§8.2 (the signal)** are the **locked core**. They may be amended only by a full major-version reissue with written rationale, never by an addendum, and never silently.

Everything else in this document is guidance with teeth. The locked core is the product.

---

## APPENDIX A — QUICK REFERENCE

```
ENVELOPE          280.0 × 84.0 × 18.0 mm
MASS              720 g ± 25 g
MODULE u          2.0 mm
PLAN RATIO        10 : 3
CONFIGURATION     Soroban 1:4, 13 rods
UNIQUE PARTS      6
TOTAL PARTS       85

FRAME             6082-T6 Al · CNC billet · 120-grit blast · Type II anodise 10 µm
                  Ra 0.8–1.2 µm · Gloss 8–12 GU @60°
BEADS             316L stainless · Ø14.0 × 7.0 (2:1) · Ra 0.4 circumferential
                  Heaven ×13: matte graphite PVD · Earth ×52: bare passivated
RODS              316L Ø2.0 h7 · DLC 1.5 µm · pitch 18.0 mm

RADII             R-A 7.0 (G2) · R-B 4.0 (G2) · R-C 1.5 · R-D 0.4 · R-E 0.15
BEAM              7.0 mm at 25.9% of aperture depth · travel 8.0 mm both zones
REVEAL            2.0 mm above and below every bead — nothing protrudes

PALETTE           #2E3033 · #8A8D8F · #E4E1DB · #B9BCC0 · #1B1C1E
SIGNAL            #B4341F — Ø1.2 mm — one instance — unit rod only

HOUSE LENS        85 mm · f/8 · Az 32° El 24°
RENDER            Cycles · 3072 spp · AgX Base · 12 bounces (8 glossy)
BEAD TRAVEL       9 frames @ 24 fps · ease-out cubic · zero overshoot
BLENDER           1 BU = 1 mm · origin at frame-centre, Z=0
```

---

## APPENDIX B — THE FOUR REJECTION TESTS

Before any asset, render, prototype or extension is approved:

| Test | Question | Fail condition |
|---|---|---|
| **TOY** | Would a child assume this is theirs? | Bright colour · bounce in motion · hollow sound · bead aspect ratio drifting toward 1:1 |
| **PLASTIC** | Does any surface read as moulded? | Gloss >15 GU · uniform normals · absent grain · draft angles · parting lines |
| **VINTAGE** | Does this reference the past? | Wood · brass · turned finials · serif type · warm colour cast · patina styling |
| **CLASSROOM** | Does this read as a teaching aid? | 2:5 configuration · rods visible as structure · printed numerals · >21 rods at consumer scale |

Any single fail is a hard stop. There is no partial credit.

---

**END OF DOCUMENT AB1-IDS-001 REV 1.0**
*Controlled document. Amendments per §16.5 only.*
