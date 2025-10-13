// widgets/google_sign_in_button.dart
// ------------------------------------
// WHY: Provide a unified Google Sign-In button that works across all platforms.
// On web, uses google_sign_in_web's renderButton() which creates Google's official button.
// On mobile/desktop, uses a custom FilledButton that calls authenticate().

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import '../services/google_drive_folder_service.dart';
import '../services/debug_logger.dart';

/// Cross-platform Google Sign-In button.
///
/// On web: Renders Google's official sign-in button using GIS SDK.
/// On mobile/desktop: Shows custom button that calls authenticate().
class GoogleSignInButton extends StatelessWidget {
  final GoogleDriveFolderService service;
  final VoidCallback? onSuccess;
  final VoidCallback? onFailure;

  const GoogleSignInButton({
    super.key,
    required this.service,
    this.onSuccess,
    this.onFailure,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // On web, use Google's official button widget
      return _buildWebButton(context);
    } else {
      // On mobile/desktop, use custom button with authenticate()
      return _buildMobileButton(context);
    }
  }

  /// Build Google's official sign-in button for web.
  /// This is the ONLY way to sign in on web with GIS SDK.
  Widget _buildWebButton(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 48, // Standard button height
        child: web.renderButton(
          configuration: web.GSIButtonConfiguration(
            type: web.GSIButtonType.standard,
            theme: Theme.of(context).brightness == Brightness.dark
                ? web.GSIButtonTheme.filledBlack
                : web.GSIButtonTheme.filledBlue,
            size: web.GSIButtonSize.large,
            text: web.GSIButtonText.signinWith,
            shape: web.GSIButtonShape.rectangular,
            logoAlignment: web.GSIButtonLogoAlignment.left,
          ),
        ),
      ),
    );
  }

  /// Build custom button for mobile/desktop platforms.
  /// These platforms support programmatic authenticate().
  Widget _buildMobileButton(BuildContext context) {
    return FilledButton.icon(
      onPressed: service.isAuthenticating
          ? null
          : () => _handleAuthentication(context),
      icon: service.isAuthenticating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label: Text(
        service.isAuthenticating ? 'Connecting...' : 'Sign In with Google',
      ),
    );
  }

  /// Handle authentication for mobile/desktop (programmatic).
  Future<void> _handleAuthentication(BuildContext context) async {
    infoLog('Starting mobile authentication', tag: 'GoogleSignInButton');

    final success = await service.authenticate();

    if (!context.mounted) return;

    if (success) {
      infoLog('Authentication successful', tag: 'GoogleSignInButton');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to Google Drive')),
      );
      onSuccess?.call();
    } else {
      errorLog('Authentication failed', tag: 'GoogleSignInButton');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      onFailure?.call();
    }
  }
}
