/// Shared layout constants for screen splits to keep practice/review aligned.
/// Centralizing prevents drift in side-by-side proportions.
const double kCanvasFraction = 0.65; // vertical/horizontal canvas fraction
const double kDividerThickness = 1.0; // vertical/horizontal divider thickness

/// Breakpoint (logical width) above which we switch to side-by-side layout.
/// Previously hard-coded as 900 in multiple widgets.
const double kWideLayoutBreakpoint = 900;
