// --- Auth Service (web-only) -----------------------------------------------
// Minimal auth interface used by the UI. On web we use google_sign_in;
// on other platforms we allow access with no auth.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart' as gsi;

/// Immutable snapshot of auth state used by UI.
@immutable
class AuthState {
  final bool isSignedIn;
  final String? email;
  const AuthState({required this.isSignedIn, this.email});
}

/// Simple auth facade around FirebaseAuth for gating access.
class AuthService extends ChangeNotifier {
  final Set<String> _allowedEmails;
  final gsi.GoogleSignIn? _gsi;
  AuthState _state = const AuthState(isSignedIn: false);
  AuthState get state => _state;

  AuthService({Set<String>? allowedEmails})
    : _allowedEmails = allowedEmails ?? const {},
      _gsi = kIsWeb ? gsi.GoogleSignIn(scopes: const ['email']) : null;

  Future<void> ensureSignedIn() async {
    if (!kIsWeb) {
      _state = const AuthState(isSignedIn: true);
      notifyListeners();
      return;
    }
    final account = await _gsi!.signInSilently() ?? await _gsi.signIn();
    final email = account?.email;
    final allowed =
        email != null &&
        (_allowedEmails.isEmpty || _allowedEmails.contains(email));
    _state = AuthState(isSignedIn: allowed, email: email);
    notifyListeners();
  }

  Future<void> signOut() async {
    if (kIsWeb && _gsi != null) {
      await _gsi.signOut();
      _state = const AuthState(isSignedIn: false);
      notifyListeners();
    }
  }
}
