//! Color Space Conversion Utilities
//!
//! This module provides utilities for converting between sRGB and linear RGB color spaces.
//! 
//! Color workflow:
//! - Flutter colors (e.g., kPaperColor, kBrushDarkDefault) are in sRGB space
//! - Canvas texture uses linear format for correct alpha blending
//! - Surface uses sRGB format, wgpu handles automatic linear → sRGB conversion

/// Convert a single sRGB color component to linear space
/// 
/// sRGB uses a gamma curve with a linear segment near black for efficiency.
/// Formula from: https://en.wikipedia.org/wiki/SRGB#From_sRGB_to_CIE_XYZ
#[inline]
pub fn srgb_to_linear(srgb: f32) -> f32 {
    if srgb <= 0.04045 {
        srgb / 12.92
    } else {
        ((srgb + 0.055) / 1.055).powf(2.4)
    }
}

/// Convert sRGB color (0.0-1.0) to linear RGB
/// 
/// # Arguments
/// * `srgb` - Color in sRGB space [r, g, b, a] where RGB are gamma-encoded and alpha is linear
/// 
/// # Returns
/// Color in linear space [r, g, b, a] where all components are linear
#[inline]
pub fn srgb_to_linear_rgba(srgb: [f32; 4]) -> [f32; 4] {
    [
        srgb_to_linear(srgb[0]),
        srgb_to_linear(srgb[1]),
        srgb_to_linear(srgb[2]),
        srgb[3], // Alpha is already linear
    ]
}

/// Convert sRGB color (0.0-1.0) to linear RGB for use with f64
/// 
/// # Arguments
/// * `srgb` - Color in sRGB space [r, g, b, a] where RGB are gamma-encoded and alpha is linear
/// 
/// # Returns
/// Color in linear space [r, g, b, a] where all components are linear
#[allow(dead_code)]
#[inline]
pub fn srgb_to_linear_rgba_f64(srgb: [f64; 4]) -> [f64; 4] {
    [
        srgb_to_linear(srgb[0] as f32) as f64,
        srgb_to_linear(srgb[1] as f32) as f64,
        srgb_to_linear(srgb[2] as f32) as f64,
        srgb[3], // Alpha is already linear
    ]
}

/// Convert RGB color from 0-255 sRGB to linear 0.0-1.0
/// 
/// # Arguments
/// * `r, g, b` - Color components in 0-255 sRGB space
/// * `a` - Alpha in 0.0-1.0 (already linear)
/// 
/// # Returns
/// Color in linear space [r, g, b, a] where all values are 0.0-1.0
#[inline]
pub fn srgb_u8_to_linear_f32(r: u8, g: u8, b: u8, a: f32) -> [f32; 4] {
    srgb_to_linear_rgba([
        r as f32 / 255.0,
        g as f32 / 255.0,
        b as f32 / 255.0,
        a,
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_srgb_to_linear() {
        // Test black
        assert_eq!(srgb_to_linear(0.0), 0.0);
        
        // Test white
        assert!((srgb_to_linear(1.0) - 1.0).abs() < 0.001);
        
        // Test middle gray (sRGB 0.5 ≈ linear 0.214)
        let linear = srgb_to_linear(0.5);
        assert!((linear - 0.214).abs() < 0.01);
    }

    #[test]
    fn test_flutter_paper_color() {
        // Flutter kPaperColor: #F4F3EF (244, 243, 239)
        let linear = srgb_u8_to_linear_f32(244, 243, 239, 1.0);
        
        // Verify conversion is reasonable (lighter colors should be closer to 1.0)
        assert!(linear[0] > 0.9 && linear[0] <= 1.0);
        assert!(linear[1] > 0.9 && linear[1] <= 1.0);
        assert!(linear[2] > 0.9 && linear[2] <= 1.0);
        assert_eq!(linear[3], 1.0);
    }

    #[test]
    fn test_flutter_brush_color() {
        // Flutter kBrushDarkDefault: #A302DE (163, 2, 222)
        let linear = srgb_u8_to_linear_f32(163, 2, 222, 1.0);
        
        // Verify alpha is preserved
        assert_eq!(linear[3], 1.0);
        
        // Verify color components are in valid range
        assert!(linear[0] >= 0.0 && linear[0] <= 1.0);
        assert!(linear[1] >= 0.0 && linear[1] <= 1.0);
        assert!(linear[2] >= 0.0 && linear[2] <= 1.0);
    }
}
