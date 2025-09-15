# Brush Engine (Analytic Soft Round)

Focus: Convert pointer samples into a visually smooth, pressure‑responsive stroke with minimal latency and clear extension points.

## Data Flow Overview
Raw `PointerEvent` → `InputPoint(x, y, pressure, tMs)` → Smoothing (One‑Euro for x, y, pressure) → Spacing / interpolation → `Dab(center, radius, alpha)` objects appended to `StrokeLayer.live` → Drawn every frame by `CustomPainter` → Merged into backing image on commit.

## Key Classes
- **BrushParams**: Immutable base configuration (size, spacing, flow model, hardness, curves, opacity cap).
- **InputPoint**: Transformed sample in *image space* with normalized pressure (0..1) and timestamp for adaptive smoothing.
- **OneEuro**: Adaptive low‑pass filter (per axis + pressure) balancing stability (minCutoff) and responsiveness (beta * speed).
- **Dab**: Analytic circle stamp: center (Offset), radius (pixels), alpha (0..1 pre-global opacity).
- **StrokeLayer**: Holds dabs for the current stroke only and draws them with a two‑phase halo + core strategy based on hardness.
- **BrushEngine**: Orchestrates smoothing, pressure modeling, spacing, and dab emission; exposes runtime multipliers (size, flow, hardness) without mutating base params.

## Parameter Semantics (BrushParams)
- **sizePx**: Nominal diameter at effective high pressure (after curves). Baseline for size scaling.
- **spacing**: Fraction of current diameter used as linear distance between emitted dabs (0.18 ⇒ ~5.5 dabs per diameter of travel). Clamped [0.05, 1.0].
- **flow**: Target per‑dab alpha after saturation (pre overall `opacity`).
- **minFlow**: Flow at zero pressure (ensures faint but visible start / feather).
- **maxFlowPressure**: Pressure at which target flow is reached ( <1 pushes earlier saturation for snappy mid‑pressure response).
- **minSizePct**: Minimum diameter fraction at zero pressure (0.05 ⇒ gentle taper, avoids pin‑point aliasing).
- **sizeGamma**: Pressure curve shaping for size ( <1 ⇒ accelerated early growth; 0.6 gives broad lines at light pressure for gesture work).
- **flowGamma**: Curve shaping for flow (1.0 = linear; <1 early growth, >1 delayed growth).
- **hardness**: 0 soft wide halo, 1 tight core edge (affects halo radius & alpha, not geometry coordinates).
- **opacity**: Global multiplicative cap on dab alpha (post flow computation; future hook for layer opacity / blending adjustments).

## Runtime Multipliers
Temporary dev controls modify perception without changing base preset:
- `setSizeScale(double)` multiplies computed diameter up/down (clamped 0.1..5).
- `setFlowScale(double)` scales only the variable part of flow above `minFlow` (clamped 0.1..3).
- `setHardness(double)` forwards to `StrokeLayer` to adjust halo/core relationship.

## Stroke Lifecycle
1. **Start**: UI requests `engine.resetStroke()` (PointerDown with `reset=true`). Resets smoothing filters and clears previous dabs.
2. **Add Points**: Batched via `engine.addPoints(List<InputPoint>)` from pending frame flush.
3. **Emit Dabs** (`_emit`): For each point:
   - Filter x, y, pressure using respective One‑Euro instances (adaptive smoothing frequency).
   - Compute size pressure curve: `sizeCurve = pow(filteredPressure, sizeGamma)`.
   - Diameter: `sizePx * runtimeSizeScale * lerp(minSizePct, 1, sizeCurve)`.
   - Spacing (pixels): `spacing * diameter`.
   - Flow curve: Normalize pressure by `maxFlowPressure` ⇒ clamp ⇒ gamma ⇒ lerp between `minFlow` and `flow` ⇒ runtime flow scaling.
   - If first dab: emit at filtered coordinates.
   - Else: calculate distance from last dab center. If distance < spacing, skip (accumulate movement). If ≥ spacing: interpolate additional dabs at `spacing` increments along the path direction, ensuring *even coverage* at any pointer speed.
   - Update last dab anchor to the *latest filtered position* (ensures spacing anchored to actual motion, not last emitted point if a residual fragment remains).
4. **Notify**: If any points processed, `notifyListeners()` triggers repaint of live stroke.
5. **Commit**: External (`_commitStroke` in PracticeScreen) composites `StrokeLayer.live` into `_base` then clears `live`.

## One‑Euro Filter Details
- Maintains an estimated sample frequency: `freq = 1000 / dt` using point timestamps.
- Derivative (speed) low‑pass filtered separately; speed influences effective cutoff: `cutoff = minCutoff + beta * |speed|`.
- Higher motion speed ⇒ higher cutoff ⇒ lower smoothing ⇒ responsive tips.
- `reset()` clears internal state between strokes to prevent cross‑stroke bias.

## StrokeLayer Rendering Strategy
Each dab: optional halo + core.
- **Core radius**: Interpolated between 45% and 80% of full radius with hardness.
- **Halo**: Drawn via blur (MaskFilter) sized to the gap between core & full radius; alpha scaled by `(1 - hardness) * 0.55`.
- **Result**: Tighter edges at higher hardness while preserving soft value build-up at low hardness.

## Rationale for Analytic Circles (vs Sprite Atlas)
- Sprite path produced faint square artifacts due to gradient tails + texture minification.
- Analytic circles avoid texture sampling issues, scale sharply at any resolution, and remove GPU upload & atlas management complexity.
- Performance acceptable for a single brush and moderate dab counts; sprite path can re‑emerge later for exotic shapes or batching multiple strokes.

## Invariants
- `live` holds only the current stroke's dabs.
- Smoothing filters reset at stroke start; never reused across strokes.
- `addPoints` is the *only* mutation path for dab addition (ensures consistent spacing logic).
- Spacing is always a function of the *current* filtered diameter (pressure‑adaptive spacing).

## Extension Points / Future Enhancements
| Area | Idea | Notes |
|------|------|------|
| Performance | Switch to drawVertices or shader-based radial falloff | Reduce blur passes; custom falloff curve. |
| Brush Shapes | Reintroduce texture atlas | For textured / pattern brushes. |
| Dynamics | Tilt / velocity modulated size/flow | Input abstraction needed. |
| Accumulation | Flow accumulation limit (true opacity) | Add stroke-level compositing cap. |
| Undo | Keep per-stroke dab list for replay | Already isolated in `live`; just serialize pre-commit. |
| Pressure Curves UI | Interactive curve editor | Replace simple gamma/threshold fields. |
| Stabilizer | Optional pre-smoothing buffer | Complement to One‑Euro for ultra-straight lines. |

## Pseudocode (Emission Core)
```
for point in rawPoints:
  sx = smoothX(point.x)
  sy = smoothY(point.y)
  sp = smoothP(point.pressure)
  sizeCurve = pow(sp, sizeGamma)
  diameter = sizePx * runtimeSizeScale * (minSizePct + (1 - minSizePct) * sizeCurve)
  spacingPx = spacing * diameter
  flowNorm = clamp(sp / maxFlowPressure, 0, 1)
  flowCurve = pow(flowNorm, flowGamma)
  baseFlow = minFlow + (flow - minFlow) * flowCurve
  flowOut = minFlow + (baseFlow - minFlow) * runtimeFlowScale
  if first dab: emit(sx, sy)
  else if distance to last >= spacingPx: interpolate at spacingPx increments
```

## Practical Tuning Guidance
- Lower `spacing` (e.g. 0.12) → smoother but more dabs (cost). Higher (0.3) → faster, risk of gaps at high velocity.
- Lower `sizeGamma` (<0.5) → very fat early lines; higher (>0.9) → thin until heavy pressure.
- `maxFlowPressure` < 1.0 yields earlier density; set =1.0 for linear full range.
- `minSizePct` too small (<0.03) increases alias risk and makes stroke starts feel scratchy.
- Hardness near 1.0 removes halo—useful for crisp lineart variant later.

## Known Limitations
- No temporal blending / wetness (each dab overwrites via normal src-over white).
- No undo (single commit path merges irreversibly).
- Pressure smoothing tuned empirically; may need device-specific calibration.
- Blur-based halo cost scales with dab count; large diameters + dense spacing might benefit from shader falloff optimization.

## Testing Ideas (Future)
- Synthetic path generator to verify even spacing under variable speed.
- Pressure ramp test to confirm expected diameter/alpha monotonicity.
- FPS + memory profiling comparing analytic vs sprite approach.

## Quick Reference Table (Defaults)
| Param | Default | Effect |
|-------|---------|--------|
| sizePx | 10 | Base diameter at high pressure |
| spacing | 0.18 | ~5.5 dabs per diameter traveled |
| flow | 0.65 | Target per-dab alpha (before opacity) |
| minFlow | 0.05 | Faint start/end visibility |
| maxFlowPressure | 0.85 | Early density saturation |
| minSizePct | 0.05 | Minimum 5% diameter taper |
| sizeGamma | 0.6 | Fast early size growth |
| flowGamma | 1.0 | Linear flow curve |
| hardness | 0.2 | Soft halo sketch feel |
| opacity | 1.0 | Global alpha cap |

## Summary
The engine favors clarity and responsiveness: minimal state, explicit data flow, and analytic dabs with adaptive smoothing + pressure-driven size/flow curves. It is intentionally simple to audit and extend—future complexity (multiple brushes, textures, undo, pan/zoom) can layer on without rewriting the core emission logic.
