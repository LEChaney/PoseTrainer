import 'package:hive_ce/hive.dart';
import '../constants/brush_defaults.dart';

/// Persistent brush settings that are saved across sessions
/// These are the runtime multipliers that control the brush behavior
class BrushSettings extends HiveObject {
  /// Brush size scale (0.01-1.0), multiplied by maxSizePx
  /// Default: 0.75 (75% of max size = 75px when maxSizePx=100)
  double sizeScale;

  /// Flow/opacity scale (0.01-1.0), multiplied by computed flow
  /// Default: 0.3 (30% flow for light sketching)
  double flowScale;

  /// Edge hardness (0.0-1.0)
  /// 0.0 = very soft edges, 1.0 = hard edges
  /// Default: 1.0 (hard edges for clean lines)
  double hardness;

  BrushSettings({
    required this.sizeScale,
    required this.flowScale,
    required this.hardness,
  });

  /// Default settings matching Flutter BrushParams defaults
  factory BrushSettings.defaults() {
    return BrushSettings(
      sizeScale: kDefaultBrushSizeScale,
      flowScale: kDefaultBrushFlowScale,
      hardness: kDefaultBrushHardness,
    );
  }

  BrushSettings copyWith({
    double? sizeScale,
    double? flowScale,
    double? hardness,
  }) {
    return BrushSettings(
      sizeScale: sizeScale ?? this.sizeScale,
      flowScale: flowScale ?? this.flowScale,
      hardness: hardness ?? this.hardness,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushSettings &&
          runtimeType == other.runtimeType &&
          sizeScale == other.sizeScale &&
          flowScale == other.flowScale &&
          hardness == other.hardness;

  @override
  int get hashCode =>
      sizeScale.hashCode ^ flowScale.hashCode ^ hardness.hashCode;

  @override
  String toString() {
    return 'BrushSettings(sizeScale: $sizeScale, flowScale: $flowScale, hardness: $hardness)';
  }
}

/// Hive adapter for BrushSettings
class BrushSettingsAdapter extends TypeAdapter<BrushSettings> {
  @override
  final int typeId = 1;

  @override
  BrushSettings read(BinaryReader reader) {
    return BrushSettings(
      sizeScale: reader.readDouble(),
      flowScale: reader.readDouble(),
      hardness: reader.readDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, BrushSettings obj) {
    writer.writeDouble(obj.sizeScale);
    writer.writeDouble(obj.flowScale);
    writer.writeDouble(obj.hardness);
  }
}

/// Service for loading and saving brush settings
class BrushSettingsService {
  static const String _boxName = 'brush_settings';
  static const String _settingsKey = 'current';

  static Box<BrushSettings>? _box;

  /// Initialize the settings box
  static Future<void> init() async {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(BrushSettingsAdapter());
    }
    _box = await Hive.openBox<BrushSettings>(_boxName);
  }

  /// Load saved settings or return defaults
  static BrushSettings load() {
    if (_box == null) {
      throw StateError(
        'BrushSettingsService not initialized. Call init() first.',
      );
    }
    return _box!.get(_settingsKey) ?? BrushSettings.defaults();
  }

  /// Save settings
  static Future<void> save(BrushSettings settings) async {
    if (_box == null) {
      throw StateError(
        'BrushSettingsService not initialized. Call init() first.',
      );
    }
    await _box!.put(_settingsKey, settings);
  }

  /// Close the box (call on app shutdown)
  static Future<void> close() async {
    await _box?.close();
    _box = null;
  }
}
