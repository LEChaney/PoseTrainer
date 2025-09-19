// Web implementation that renders the official Google button via google_sign_in_web
// and falls back to a simple Material button if rendering fails.

import 'dart:html';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    as gsi_platform;
import 'package:google_sign_in_web/google_sign_in_web.dart' as gsi_web;
import 'package:uuid/uuid.dart';

class GoogleSignInButton extends StatefulWidget {
  final VoidCallback? onPressedFallback;
  const GoogleSignInButton({super.key, this.onPressedFallback});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  late final String _viewType;
  bool _rendered = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'gsi-btn-${const Uuid().v4()}';
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = DivElement()
        ..style.display = 'inline-block'
        ..style.width = '100%'
        ..style.textAlign = 'center';
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

  @override
  Widget build(BuildContext context) {
    if (_rendered) {
      return SizedBox(height: 48, child: HtmlElementView(viewType: _viewType));
    }
    return FilledButton.icon(
      onPressed: widget.onPressedFallback,
      icon: const Icon(Icons.login),
      label: const Text('Continue with Google'),
    );
  }
}
