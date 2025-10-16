//! Application State and Logic
//!
//! This module contains the core application state and update/render logic.
//! It's designed to be independent of the windowing system, making it easier
//! to port to different platforms (native, web, Flutter).

use crate::renderer::Renderer;

/// Main application state
pub struct App {
    /// Clear color (RGBA, values 0.0-1.0)
    clear_color: [f64; 4],
}

impl App {
    /// Create a new application with default state
    pub fn new() -> Self {
        Self {
            // Red background, for testing
            clear_color: [1.0, 0.0, 0.0, 1.0], // #ff0000ff
        }
    }

    /// Update application state (called each frame)
    pub fn update(&mut self, _delta_time: f64) {
        // TODO: Update animation, handle input, etc.
    }

    /// Render the application (called each frame)
    pub fn render(&mut self, renderer: &mut Renderer) {
        renderer.render(self.clear_color);
    }

    /// Set the clear color
    pub fn set_clear_color(&mut self, r: f64, g: f64, b: f64, a: f64) {
        self.clear_color = [r, g, b, a];
    }

    /// Get the current clear color
    pub fn clear_color(&self) -> [f64; 4] {
        self.clear_color
    }
}

impl Default for App {
    fn default() -> Self {
        Self::new()
    }
}
