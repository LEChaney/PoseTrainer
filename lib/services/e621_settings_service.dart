// services/e621_settings_service.dart
// ------------------------------------
// Service for managing customizable e621 API query settings.
// Persists settings using Hive for cross-session retention.

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// Available rating filter options
enum E621Rating {
  safe('safe', 'Safe only'),
  questionable('questionable', 'Questionable'),
  explicit('explicit', 'Explicit'),
  none('', 'No filter');

  final String value;
  final String displayName;
  const E621Rating(this.value, this.displayName);
}

/// Default base URL for e621 API
const String kDefaultE621BaseUrl = 'https://e621.net';

/// Service for managing e621 API query settings with persistence.
class E621SettingsService extends ChangeNotifier {
  static E621SettingsService? _instance;
  static E621SettingsService get instance =>
      _instance ??= E621SettingsService._();

  E621SettingsService._();

  Box<dynamic>? _settingsBox;
  bool _settingsLoaded = false;

  // Settings with defaults
  String _baseUrl = kDefaultE621BaseUrl;
  int _pageLimit = 320;
  E621Rating _rating = E621Rating.safe;
  bool _excludeCub = true;
  String _customTags = '';

  // Getters
  bool get settingsLoaded => _settingsLoaded;
  String get baseUrl => _baseUrl;
  int get pageLimit => _pageLimit;
  E621Rating get rating => _rating;
  bool get excludeCub => _excludeCub;
  String get customTags => _customTags;

  /// Initialize the service by loading settings from Hive.
  /// Call this once at app startup before using the service.
  static Future<void> init() async {
    await instance._loadSettings();
  }

  /// Builds the full query URL with current settings and user search tags.
  /// [userTags] should already be '+'-separated (no whitespace).
  String buildQueryUrl(String userTags) {
    // Ensure baseUrl doesn't have trailing slash
    final cleanBaseUrl = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final buffer = StringBuffer('$cleanBaseUrl/posts.json?');
    buffer.write('limit=$_pageLimit');
    buffer.write('&tags=');

    final tagParts = <String>[];

    // Add rating filter if set
    if (_rating != E621Rating.none) {
      tagParts.add('rating:${_rating.value}');
    }

    // Add cub exclusion if enabled
    if (_excludeCub) {
      tagParts.add('-cub');
    }

    // Add custom fixed tags
    final trimmedCustom = _customTags.trim();
    if (trimmedCustom.isNotEmpty) {
      // Split by whitespace and add each tag
      final customParts = trimmedCustom.split(RegExp(r'\s+'));
      tagParts.addAll(customParts);
    }

    // Add user search tags
    if (userTags.isNotEmpty) {
      tagParts.add(userTags);
    }

    buffer.write(tagParts.join('+'));
    return buffer.toString();
  }

  /// Returns a preview of what the URL would look like with example tags.
  String get previewUrl => buildQueryUrl('example_tag');

  Future<void> _loadSettings() async {
    try {
      if (!Hive.isBoxOpen('e621_settings')) {
        _settingsBox = await Hive.openBox('e621_settings');
      } else {
        _settingsBox = Hive.box('e621_settings');
      }

      // Load persisted settings
      _baseUrl =
          _settingsBox?.get('baseUrl', defaultValue: kDefaultE621BaseUrl) ??
          kDefaultE621BaseUrl;

      _pageLimit = _settingsBox?.get('pageLimit', defaultValue: 30) ?? 30;

      final ratingIndex =
          _settingsBox?.get(
            'ratingIndex',
            defaultValue: E621Rating.safe.index,
          ) ??
          E621Rating.safe.index;
      _rating =
          E621Rating.values[ratingIndex.clamp(0, E621Rating.values.length - 1)];

      _excludeCub = _settingsBox?.get('excludeCub', defaultValue: true) ?? true;
      _customTags = _settingsBox?.get('customTags', defaultValue: '') ?? '';

      _settingsLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading e621 settings: $e');
      _settingsLoaded = true; // Mark as loaded even on failure
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsBox?.put('baseUrl', _baseUrl);
      await _settingsBox?.put('pageLimit', _pageLimit);
      await _settingsBox?.put('ratingIndex', _rating.index);
      await _settingsBox?.put('excludeCub', _excludeCub);
      await _settingsBox?.put('customTags', _customTags);
    } catch (e) {
      debugPrint('Error saving e621 settings: $e');
    }
  }

  // Setters that persist changes

  void setBaseUrl(String value) {
    final trimmed = value.trim();
    if (_baseUrl != trimmed) {
      _baseUrl = trimmed.isEmpty ? kDefaultE621BaseUrl : trimmed;
      _saveSettings();
      notifyListeners();
    }
  }

  void setPageLimit(int value) {
    final clamped = value.clamp(1, 320); // e621 max is 320
    if (_pageLimit != clamped) {
      _pageLimit = clamped;
      _saveSettings();
      notifyListeners();
    }
  }

  void setRating(E621Rating value) {
    if (_rating != value) {
      _rating = value;
      _saveSettings();
      notifyListeners();
    }
  }

  void setExcludeCub(bool value) {
    if (_excludeCub != value) {
      _excludeCub = value;
      _saveSettings();
      notifyListeners();
    }
  }

  void setCustomTags(String value) {
    if (_customTags != value) {
      _customTags = value;
      _saveSettings();
      notifyListeners();
    }
  }

  /// Reset all settings to defaults
  void resetToDefaults() {
    _baseUrl = kDefaultE621BaseUrl;
    _pageLimit = 30;
    _rating = E621Rating.safe;
    _excludeCub = true;
    _customTags = '';
    _saveSettings();
    notifyListeners();
  }
}
