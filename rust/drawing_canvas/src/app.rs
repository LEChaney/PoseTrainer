//! Application State and Logic
//!
//! This module contains the core application state and update/render logic.
//! It's designed to be independent of the windowing system, making it easier
//! to port to different platforms (native, web, Flutter).

use crate::brush::BrushState;
use crate::input::{InputQueue, PointerEvent};
use crate::renderer::Renderer;

/// Main application state
pub struct App {
    /// Clear color (RGBA, values 0.0-1.0)
    clear_color: [f64; 4],
    /// Input event queue
    input_queue: InputQueue,
    /// Brush state
    brush_state: BrushState,
}

impl App {
    /// Create a new application with default state
    pub fn new() -> Self {
        Self {
            // Red background, for testing
            clear_color: [1.0, 0.0, 0.0, 1.0], // #ff0000ff
            input_queue: InputQueue::new(),
            brush_state: BrushState::new(),
        }
    }

    /// Update application state (called each frame)
    pub fn update(&mut self, _delta_time: f64) {
        // TODO: Update animation, handle input, etc.
    }

    /// Render the application (called each frame)
    pub fn render(&mut self, renderer: &mut Renderer) {
        // Process input events and generate brush dabs
        let dabs = self.process_input_events();
        
        // Render dabs to canvas if any
        if !dabs.is_empty() {
            renderer.render_dabs(&dabs);
        }
        
        // Copy canvas to surface
        renderer.render();
    }

    /// Clear the canvas
    pub fn clear_canvas(&mut self, renderer: &mut Renderer) {
        renderer.clear_canvas(self.clear_color);
    }

    /// Set the clear color
    pub fn set_clear_color(&mut self, r: f64, g: f64, b: f64, a: f64) {
        self.clear_color = [r, g, b, a];
    }

    /// Get the current clear color
    pub fn clear_color(&self) -> [f64; 4] {
        self.clear_color
    }

    /// Queue an input event for processing
    pub fn queue_input_event(&mut self, event: PointerEvent) {
        self.input_queue.push_event(event);
    }

    /// Check if there are pending input events
    pub fn has_pending_input(&self) -> bool {
        self.input_queue.has_events()
    }

    /// Get mutable reference to brush state (for parameter adjustment)
    pub fn brush_state_mut(&mut self) -> &mut BrushState {
        &mut self.brush_state
    }

    /// Get reference to brush state
    pub fn brush_state(&self) -> &BrushState {
        &self.brush_state
    }

    /// Process input events and generate brush dabs
    fn process_input_events(&mut self) -> Vec<crate::brush::BrushDab> {
        let mut all_dabs = Vec::new();

        for event in self.input_queue.drain_events() {
            match event.event_type {
                crate::input::PointerEventType::Down => {
                    // Start new stroke
                    self.brush_state.reset_stroke();
                    let dabs = self.brush_state.calculate_dabs(event.position, event.pressure);
                    all_dabs.extend(dabs);
                }
                crate::input::PointerEventType::Move => {
                    // Continue stroke
                    let dabs = self.brush_state.calculate_dabs(event.position, event.pressure);
                    all_dabs.extend(dabs);
                }
                crate::input::PointerEventType::Up => {
                    // End stroke
                    let dabs = self.brush_state.calculate_dabs(event.position, event.pressure);
                    all_dabs.extend(dabs);
                }
            }
        }

        log::debug!("Processed input events, generated {} dabs", all_dabs.len());
        all_dabs
    }
}

impl Default for App {
    fn default() -> Self {
        Self::new()
    }
}
