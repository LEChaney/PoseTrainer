//! Brush Parameters and State
//!
//! This module defines brush parameters and provides logic for calculating
//! brush dabs from input events.

use crate::input::PointerEventSource;

/// Parameters that define brush behavior
#[derive(Debug, Clone, Copy)]
pub struct BrushParams {
    /// Brush size in pixels (diameter)
    pub size: f32,
    /// Per-dab opacity (0.0-1.0), also called "flow"
    pub flow: f32,
    /// Brush edge hardness (0.0=soft, 1.0=hard)
    pub hardness: f32,
    /// Spacing between dabs as a fraction of brush diameter (0.0-1.0)
    /// e.g., 0.05 = 5% of diameter, 0.25 = 25% of diameter
    pub spacing: f32,
    /// Brush color in sRGB RGBA (0.0-1.0)
    /// Will be converted to linear at render time if needed
    pub color: [f32; 4],
    /// How pressure affects the brush
    pub pressure_mapping: PressureMapping,
    /// Minimum size as a fraction of full size at zero pressure (0.0-1.0)
    /// e.g., 0.1 = 10% of size, 1.0 = 100% (no pressure effect on size)
    /// Only applies when Size or Both pressure mapping is enabled
    pub min_size_percent: f32,
    /// Flow coefficient - maximum flow scaling factor at full pressure
    /// Can be greater than 1.0 for increased size up speed (clamped at 1.0 in dab creation)
    pub max_size_percent: f32,
    /// Minimum flow as a fraction of full flow at zero pressure (0.0-1.0)
    /// e.g., 0.0 = fully transparent at zero pressure, 1.0 = no pressure effect on flow
    /// Only applies when Flow or Both pressure mapping is enabled
    pub min_flow_percent: f32,
    /// Flow coefficient - maximum flow scaling factor at full pressure
    /// Can be greater than 1.0 for increased flow up speed (clamped at 1.0 in dab creation)
    pub max_flow_percent: f32,
    /// Size pressure curve gamma
    /// <1.0 = aggressive early growth, =1.0 = linear, >1.0 = delayed growth
    pub size_gamma: f32,
    /// Flow pressure curve gamma
    /// <1.0 = aggressive early opacity, =1.0 = linear, >1.0 = delayed opacity
    pub flow_gamma: f32,
    /// Input filter mode - which input sources to accept
    pub input_filter_mode: InputFilterMode,
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
            ..BrushParams::default()
        }
    }

    /// Apply gamma curve and map pressure to a range [min, max]
    /// 
    /// # Arguments
    /// * `pressure` - Raw pressure value (0.0-1.0)
    /// * `gamma` - Gamma curve exponent (<1.0 = aggressive early response, =1.0 = linear, >1.0 = delayed response)
    /// * `min` - Minimum output value at zero pressure
    /// * `max` - Maximum output value at full pressure
    /// 
    /// # Returns
    /// Mapped value in the range [min, max]
    fn apply_pressure_curve(pressure: f32, gamma: f32, min: f32, max: f32) -> f32 {
        let pressure_clamped = pressure.clamp(0.0, 1.0);
        let curved = pressure_clamped.powf(gamma);
        min + curved * (max - min)
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
        if !(0.0..=1.0).contains(&self.spacing) {
            return Err("Spacing must be between 0.0 and 1.0".to_string());
        }
        Ok(())
    }
}

impl Default for BrushParams {
    fn default() -> Self {
        Self {
            size: 30.0,
            flow: 1.0,
            hardness: 1.0,
            spacing: 0.15,
            color: [163.0 / 255.0, 2.0 / 255.0, 222.0 / 255.0, 1.0],
            pressure_mapping: PressureMapping::Both,
            min_size_percent: 0.0,
            max_size_percent: 4.0,
            min_flow_percent: 0.05,
            max_flow_percent: 4.0,
            size_gamma: 1.2,
            flow_gamma: 1.8,
            input_filter_mode: InputFilterMode::default(),
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
    /// Color in sRGB RGBA (will be converted by renderer based on blend mode)
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
        Self::Both
    }
}

/// Controls which input sources are accepted for drawing
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputFilterMode {
    /// Only accept pen/stylus input (TabletTool)
    PenOnly,
    /// Accept pen, touch, and mouse input
    PenAndTouch,
}

impl Default for InputFilterMode {
    fn default() -> Self {
        Self::PenAndTouch
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
    /// Whether the brush is currently down (in a stroke)
    brush_down: bool,
    /// Source of the brush input (Mouse, Touch, TabletTool, Unknown)
    brush_src: PointerEventSource,
}

impl BrushState {
    /// Create a new brush state with default parameters
    pub fn new() -> Self {
        Self {
            params: BrushParams::default(),
            last_dab_position: None,
            last_dab_pressure: 1.0,
            has_moved: false,
            brush_down: false,
            brush_src: PointerEventSource::Unknown,
        }
    }

    /// Create a new brush state with specified parameters
    pub fn with_params(params: BrushParams) -> Self {
        Self {
            params,
            last_dab_position: None,
            last_dab_pressure: 1.0,
            has_moved: false,
            brush_down: false,
            brush_src: PointerEventSource::Unknown,
        }
    }

    /// Update the source of the brush input, potentially ending the stroke if source changes
    pub fn update_brush_src(&mut self, source: PointerEventSource) {
        if self.brush_src != source && self.brush_down {
            // If source changed during stroke, end the stroke
            self.end_stroke();
        }
        self.brush_src = source;
    }

    /// Reset brush state to initial conditions
    pub fn reset_brush(&mut self) {
        self.last_dab_position = None;
        self.last_dab_pressure = 0.0;
        self.has_moved = false;
        self.brush_down = false;
        self.brush_src = PointerEventSource::Unknown;
    }

    /// Begin a new stroke (call when starting a new stroke)
    pub fn begin_stroke(&mut self) {
        self.last_dab_position = None;
        self.last_dab_pressure = 0.0;
        self.has_moved = false;
        self.brush_down = true;
    }

    /// End the current stroke (call when finishing a stroke)
    pub fn end_stroke(&mut self) {
        self.reset_brush();
    }

    /// Calculate dabs for a segment from previous position to current position
    /// Returns a vector of dabs to render
    pub fn calculate_dabs(&mut self, position: [f32; 2], pressure: f32, event_type: crate::input::PointerEventType) -> Vec<BrushDab> {
        let mut dabs = Vec::new();
        // Only draw if brush is down
        if !self.brush_down {
            return dabs;
        }

        // Filter input based on input filter mode
        if self.params.input_filter_mode == InputFilterMode::PenOnly {
            // In PenOnly mode, only accept non-touch input
            if self.brush_src == PointerEventSource::Touch {
                log::debug!("Rejecting input from {:?} in PenOnly mode", self.brush_src);
                return dabs;
            }
        }

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

        // Calculate actual spacing in pixels as a percentage of brush diameter
        // Clamp spacing ratio to a minimum to avoid division by zero and ensure reasonable behavior
        let spacing_ratio = self.params.spacing.max(0.01);
        let spacing_px = spacing_ratio * self.params.size;

        let mut remaining_distance = segment_distance;
        while remaining_distance >= spacing_px {
            // Calculate how far along the CURRENT SEGMENT this dab should be
            // accumulated_distance is measured from the LAST DAB we placed (which might be in a previous segment)
            // We need to figure out where along [prev_pos -> position] to place this dab
            
            let distance_into_segment = segment_distance - remaining_distance + spacing_px;
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
            remaining_distance -= spacing_px;
        }

        dabs
    }

    /// Create a single dab with pressure applied
    fn create_dab(&self, position: [f32; 2], pressure: f32) -> BrushDab {
        let (size, opacity) = match self.params.pressure_mapping {
            PressureMapping::Flow => {
                let flow_scale = BrushParams::apply_pressure_curve(
                    pressure,
                    self.params.flow_gamma,
                    self.params.min_flow_percent,
                    self.params.max_flow_percent,
                ).clamp(0.0, 1.0);
                (self.params.size, self.params.flow * flow_scale)
            }
            PressureMapping::Size => {
                let size_scale = BrushParams::apply_pressure_curve(
                    pressure,
                    self.params.size_gamma,
                    self.params.min_size_percent,
                    self.params.max_size_percent,
                ).clamp(0.0, 1.0);
                (self.params.size * size_scale, self.params.flow)
            }
            PressureMapping::Both => {
                let size_scale = BrushParams::apply_pressure_curve(
                    pressure,
                    self.params.size_gamma,
                    self.params.min_size_percent,
                    self.params.max_size_percent,
                ).clamp(0.0, 1.0);
                let flow_scale = BrushParams::apply_pressure_curve(
                    pressure,
                    self.params.flow_gamma,
                    self.params.min_flow_percent,
                    self.params.max_flow_percent,
                ).clamp(0.0, 1.0);
                (self.params.size * size_scale, self.params.flow * flow_scale)
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
