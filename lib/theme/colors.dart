import 'package:flutter/material.dart';

/// Global color tokens (avoid scattering hex codes throughout codebase).
/// Beginner phase: keep minimal. Promote to ThemeExtension later if we add
/// dynamic switching (e.g., dark mode / alternative paper tones).
const Color kPaperColor = Color.fromARGB(
  255,
  255,
  255,
  255,
); // warm off-white drawing surface
const Color kBrushDarkDefault = Color.fromARGB(
  255,
  163,
  2,
  222,
); // inky dark bluegrey brush

// Unified dark background for reference panels (practice & review).
// Was previously hard-coded in multiple places (0xFF1A1A1E). Centralizing
// ensures consistent contrast and easy future theme adjustments.
const Color kReferencePanelColor = Color(0xFF1A1A1E);
