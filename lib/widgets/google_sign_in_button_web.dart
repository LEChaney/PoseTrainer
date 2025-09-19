// --- Web Google Sign-In button (FedCM style) ------------------------------
// Renders the official Google button via google_sign_in_web and triggers
// the platform sign-in flow consistent with FedCM guidance.

// This file is only meant to be used when kIsWeb is true.

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    as gsi_platform;
import 'package:google_sign_in_web/google_sign_in_web.dart' as gsi_web;
import 'package:uuid/uuid.dart';

/// A widget that renders Google's sign-in button using the web plugin.
class GoogleSignInButtonWeb extends StatefulWidget {
  final VoidCallback? onPressedFallback;
  const GoogleSignInButtonWeb({super.key, this.onPressedFallback});

  @override
  State<GoogleSignInButtonWeb> createState() => _GoogleSignInButtonWebState();
}

class _GoogleSignInButtonWebState extends State<GoogleSignInButtonWeb> {
  late final String _viewType;
  bool _rendered = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'gsi-btn-${const Uuid().v4()}';
    if (kIsWeb) {
      // Register a view that the web plugin can render into.
      ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final container = DivElement()
          ..style.display = 'inline-block'
          ..style.width = '100%'
          ..style.textAlign = 'center';
        // Try to render the official Google button via the web plugin.
        try {
          final platform = gsi_platform.GoogleSignInPlatform.instance;
          if (platform is gsi_web.GoogleSignInPlugin) {
            platform.renderButton(
              target: container,
              theme: gsi_web.GsiButtonTheme.outline,
              size: gsi_web.GsiButtonSize.large,
              text: gsi_web.GsiButtonTextType.continueWith,
              shape: gsi_web.GsiButtonShape.pill,
              logoAlignment: gsi_web.GsiButtonLogoAlignment.left,
            );
            _rendered = true;
          }
        } catch (_) {
          _rendered = false;
        }
        return container;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return _fallbackButton();
    }
    if (_rendered) {
      return SizedBox(height: 48, child: HtmlElementView(viewType: _viewType));
    }
    return _fallbackButton();
  }

  Widget _fallbackButton() {
    return FilledButton.icon(
      onPressed: widget.onPressedFallback,
      icon: const Icon(Icons.login),
      label: const Text('Continue with Google'),
    );
  }
}
