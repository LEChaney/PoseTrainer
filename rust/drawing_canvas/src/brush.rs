//! Brush Parameters and State
//!
//! This module defines brush parameters and provides logic for calculating
//! brush dabs from input events.

/// Parameters that define brush behavior
#[derive(Debug, Clone, Copy)]
pub struct BrushParams {
    /// Brush size in pixels (diameter)
    pub size: f32,
    /// Per-dab opacity (0.0-1.0), also called "flow"
    pub flow: f32,
    /// Brush edge hardness (0.0=soft, 1.0=hard)
    pub hardness: f32,
    /// Spacing between dabs in pixels
    pub spacing: f32,
    /// Brush color in linear RGBA (0.0-1.0)
    pub color: [f32; 4],
    /// How pressure affects the brush
    pub pressure_mapping: PressureMapping,
}

impl BrushParams {
    /// Create new brush parameters with specified values
    pub fn new(size: f32, flow: f32, hardness: f32, spacing: f32, color: [f32; 4]) -> Self {
        Self {
            size,
            flow,
            hardness,
            spacing,
            color,
            pressure_mapping: PressureMapping::default(),
        }
    }

    /// Validate that parameters are in acceptable ranges
    pub fn validate(&self) -> Result<(), String> {
        if self.size <= 0.0 {
            return Err("Brush size must be positive".to_string());
        }
        if !(0.0..=1.0).contains(&self.flow) {
            return Err("Flow must be between 0.0 and 1.0".to_string());
        }
        if !(0.0..=1.0).contains(&self.hardness) {
            return Err("Hardness must be between 0.0 and 1.0".to_string());
        }
        if self.spacing < 0.0 {
            return Err("Spacing must be non-negative".to_string());
        }
        Ok(())
    }
}

impl Default for BrushParams {
    fn default() -> Self {
        // Flutter colors are in sRGB space, convert to linear for rendering
        Self {
            // Match Flutter effective defaults:
            // maxSizePx * runtimeSizeScale = 100 * 0.75 = 75
            size: 75.0,
            // Flutter effective flow ~0.3 (maxFlow * runtimeFlowScale with formula)
            flow: 0.3,
            // Hardness matches
            hardness: 1.0,
            // Flutter spacing: 0.01 clamped to 0.05 minimum, as fraction of diameter
            // 0.05 * 75 = 3.75 pixels
            spacing: 3.75,
            // Flutter brush color: kBrushDarkDefault (#A302DE = RGB 163, 2, 222)
            // Convert from sRGB to linear RGBA for correct blending
            color: crate::color::srgb_u8_to_linear_f32(163, 2, 222, 1.0),
            // Flutter pressure mapping on flow
            pressure_mapping: PressureMapping::Flow,
        }
    }
}

/// A single brush dab to be rendered
#[derive(Debug, Clone, Copy)]
pub struct BrushDab {
    /// Position in canvas space (pixels)
    pub position: [f32; 2],
    /// Size in pixels (diameter)
    pub size: f32,
    /// Opacity for this dab (0.0-1.0)
    pub opacity: f32,
    /// Color in linear RGBA
    pub color: [f32; 4],
    /// Hardness (0.0-1.0)
    pub hardness: f32,
}

/// Controls how input pressure affects brush parameters
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PressureMapping {
    /// Pressure controls opacity/flow
    Flow,
    /// Pressure controls size
    Size,
    /// Pressure controls both size and flow
    Both,
    /// No pressure sensitivity
    None,
}

impl Default for PressureMapping {
    fn default() -> Self {
        Self::Flow
    }
}

/// Brush state that tracks the current stroke
pub struct BrushState {
    /// Current brush parameters
    pub params: BrushParams,
    /// Last input position (not dab position) for segment calculation
    last_dab_position: Option<[f32; 2]>,
    /// Last pressure value (for interpolation)
    last_dab_pressure: f32,
    /// Whether the last dab was the first in the stroke
    has_moved: bool,
}

impl BrushState {
    /// Create a new brush state with default parameters
    pub fn new() -> Self {
        Self {
            params: BrushParams::default(),
            last_dab_position: None,
            last_dab_pressure: 1.0,
            has_moved: false,
        }
    }

    /// Create a new brush state with specified parameters
    pub fn with_params(params: BrushParams) -> Self {
        Self {
            params,
            last_dab_position: None,
            last_dab_pressure: 1.0,
            has_moved: false,
        }
    }

    /// Reset stroke state (call when starting a new stroke)
    pub fn reset_stroke(&mut self) {
        self.last_dab_position = None;
        self.last_dab_pressure = 1.0;
        self.has_moved = false;
    }

    /// Calculate dabs for a segment from previous position to current position
    /// Returns a vector of dabs to render
    pub fn calculate_dabs(&mut self, position: [f32; 2], pressure: f32, event_type: crate::input::PointerEventType) -> Vec<BrushDab> {
        let mut dabs = Vec::new();

        // Defer adding the first dab until we have movement to get accurate pressure
        let prev_pos = match self.last_dab_position {
            Some(pos) => pos,
            None => {
                let dab = self.create_dab(position, pressure);
                self.last_dab_position = Some(dab.position);
                self.last_dab_pressure = pressure;
                return dabs;
            }
        };
        let is_first_movement = !self.has_moved && matches!(event_type, crate::input::PointerEventType::Move);
        if is_first_movement {
            // Now that we have movement, add the first dab with current pressure (first useable pressure measurement)
            let first_dab = self.create_dab(prev_pos, pressure);
            dabs.push(first_dab);
        }
        self.has_moved = self.has_moved || matches!(event_type, crate::input::PointerEventType::Move);

        let prev_pressure = self.last_dab_pressure;

        // Calculate distance from last DAB position to current DAB position
        let dx = position[0] - prev_pos[0];
        let dy = position[1] - prev_pos[1];
        let segment_distance = (dx * dx + dy * dy).sqrt();

        // Place dabs along the path based on spacing
        let spacing = self.params.spacing.max(0.1); // Avoid division by zero

        let mut remaining_distance = segment_distance;
        while remaining_distance >= spacing {
            // Calculate how far along the CURRENT SEGMENT this dab should be
            // accumulated_distance is measured from the LAST DAB we placed (which might be in a previous segment)
            // We need to figure out where along [prev_pos -> position] to place this dab
            
            let distance_into_segment = segment_distance - remaining_distance + spacing;
            let t = (distance_into_segment / segment_distance).clamp(0.0, 1.0);

            // Interpolate position
            let dab_pos = [
                prev_pos[0] + dx * t,
                prev_pos[1] + dy * t,
            ];

            // Interpolate pressure
            let dab_pressure = prev_pressure + (pressure - prev_pressure) * t;

            // Create and add dab
            let dab = self.create_dab(dab_pos, dab_pressure);
            dabs.push(dab);

            self.last_dab_position = Some(dab.position);
            self.last_dab_pressure = dab_pressure;
            remaining_distance -= spacing;
        }

        dabs
    }

    /// Create a single dab with pressure applied
    fn create_dab(&self, position: [f32; 2], pressure: f32) -> BrushDab {
        let (size, opacity) = match self.params.pressure_mapping {
            PressureMapping::Flow => {
                (self.params.size, self.params.flow * pressure)
            }
            PressureMapping::Size => {
                (self.params.size * pressure, self.params.flow)
            }
            PressureMapping::Both => {
                (self.params.size * pressure, self.params.flow * pressure)
            }
            PressureMapping::None => {
                (self.params.size, self.params.flow)
            }
        };

        BrushDab {
            position,
            size,
            opacity,
            color: self.params.color,
            hardness: self.params.hardness,
        }
    }
}

impl Default for BrushState {
    fn default() -> Self {
        Self::new()
    }
}
