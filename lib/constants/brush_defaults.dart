/// Centralized brush parameter defaults
///
/// These values define the default brush behavior across the app.
/// Change these to adjust the default drawing experience.
library;

/// Default brush size scale (0.01-1.0)
/// This is multiplied by maxSizePx (100) to get actual pixel size
/// Default: 0.75 = 75px diameter
const double kDefaultBrushSizeScale = 0.75;

/// Default flow/opacity scale (0.01-1.0)
/// This controls the per-dab opacity/flow
/// Default: 0.3 = 30% flow (light sketching)
const double kDefaultBrushFlowScale = 0.3;

/// Default edge hardness (0.0-1.0)
/// 0.0 = very soft edges with wide halo
/// 1.0 = hard edges with minimal feathering
/// Default: 1.0 = hard edges for clean lines
const double kDefaultBrushHardness = 1.0;

/// Maximum brush size in pixels (diameter)
/// This is the upper limit for brush size calculations
/// Flutter: used as BrushParams.maxSizePx
/// Rust: used as BrushParams.size upper bound
const double kMaxBrushSizePx = 100.0;

/// Brush spacing as fraction of diameter (0.0-1.0)
/// Smaller values = more dabs per stroke = smoother but slower
/// Larger values = fewer dabs = faster but may show gaps
/// Default: 0.01 clamped to 0.05 minimum = 5% of diameter
const double kDefaultBrushSpacing = 0.01;
const double kMinBrushSpacing = 0.05;

/// Size pressure curve gamma
/// <1.0 = aggressive early growth (light pressure already gives readable width)
/// =1.0 = linear
/// >1.0 = delayed growth (need more pressure for size)
const double kDefaultSizeGamma = 0.6;

/// Flow pressure curve gamma
/// <1.0 = aggressive early opacity
/// =1.0 = linear
/// >1.0 = delayed opacity
const double kDefaultFlowGamma = 1.0;

/// Maximum flow at/after this pressure level
/// <1.0 = flow reaches max before full pressure
/// =1.0 = flow reaches max at full pressure
const double kDefaultMaxFlowPressure = 1.0;

/// Minimum size scale at zero pressure (0.0-1.0)
/// Fraction of max size when no pressure applied
/// Useful for tapered stroke starts/ends
const double kDefaultMinScale = 1.0;

/// Minimum flow at zero pressure (0.0-1.0)
const double kDefaultMinFlow = 0.0;

/// Maximum flow/opacity (0.0-1.0)
const double kDefaultMaxFlow = 1.0;

/// Overall stroke opacity multiplier (0.0-1.0)
const double kDefaultBrushOpacity = 1.0;
