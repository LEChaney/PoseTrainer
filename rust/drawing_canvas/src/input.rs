//! Input Event Handling
//!
//! This module handles pointer input events (mouse, touch, stylus) and queues them
//! for processing during rendering. Events are coalesced between frames to minimize
//! latency while avoiding frame drops.

use std::collections::VecDeque;

/// A pointer input event (mouse, touch, or stylus)
#[derive(Debug, Clone)]
pub struct PointerEvent {
    /// Position in canvas space (pixels from top-left)
    pub position: [f32; 2],
    /// Pressure value (0.0-1.0), defaults to 1.0 for mouse
    pub pressure: f32,
    /// Tilt angles (x and y in degrees, 0-90), if available
    pub tilt: Option<[f32; 2]>,
    /// Azimuth/rotation angle in radians, if available
    pub azimuth: Option<f32>,
    /// Barrel rotation (twist) in degrees (0-359), if available
    pub twist: Option<f32>,
    /// Timestamp in milliseconds since some reference point
    pub timestamp: f64,
    /// Type of event (down, move, up)
    pub event_type: PointerEventType,
    /// Source of the event (Mouse, Touch, TabletTool)
    pub source: PointerEventSource,
}

/// Type of pointer event
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PointerEventType {
    /// Pointer button pressed (start of stroke)
    Down,
    /// Pointer moved while button held (continue stroke)
    Move,
    /// Pointer button released (end of stroke)
    Up,
}

// Source of pointer event
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PointerEventSource {
    Mouse,
    Touch,
    TabletTool,
    Unknown,
}

/// Queue for input events that coalesces events between frames
pub struct InputQueue {
    /// Pending events to process
    events: VecDeque<PointerEvent>,
    /// Whether we're currently in a drawing stroke
    is_drawing: bool,
    /// Last known pointer position (for calculating spacing)
    last_position: Option<[f32; 2]>,
}

impl InputQueue {
    /// Create a new empty input queue
    pub fn new() -> Self {
        Self {
            events: VecDeque::new(),
            is_drawing: false,
            last_position: None,
        }
    }

    /// Add an event to the queue
    pub fn push_event(&mut self, event: PointerEvent) {
        let event_type = event.event_type; // Copy before moving event
        
        match event.event_type {
            PointerEventType::Down => {
                self.is_drawing = true;
                self.last_position = Some(event.position);
            }
            PointerEventType::Move => {
                // Only queue move events if we're drawing
                if self.is_drawing {
                    self.last_position = Some(event.position);
                } else {
                    // Ignore move events when not drawing
                    return;
                }
            }
            PointerEventType::Up => {
                self.is_drawing = false;
                self.last_position = Some(event.position);
            }
        }

        self.events.push_back(event);
        log::debug!("Input event queued: {:?} (queue size: {})", event_type, self.events.len());
    }

    /// Drain all pending events for processing
    /// Returns an iterator that consumes the events
    pub fn drain_events(&mut self) -> impl Iterator<Item = PointerEvent> + '_ {
        self.events.drain(..)
    }

    /// Check if there are pending events
    pub fn has_events(&self) -> bool {
        !self.events.is_empty()
    }

    /// Check if currently drawing
    pub fn is_drawing(&self) -> bool {
        self.is_drawing
    }

    /// Get the last known pointer position
    pub fn last_position(&self) -> Option<[f32; 2]> {
        self.last_position
    }
}

impl Default for InputQueue {
    fn default() -> Self {
        Self::new()
    }
}
