import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../screens/search_screen.dart';

/// Gate that initializes Firebase and requires a signed-in, allowed user
/// before showing the app content. Shows a basic sign-in UI otherwise.
class AuthGate extends StatefulWidget {
  final Set<String> allowedEmails;
  const AuthGate({super.key, required this.allowedEmails});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _attemptedSilent = false;

  @override
  Widget build(BuildContext context) {
    // Only gate on web. Other platforms render the app content directly.
    if (!kIsWeb) {
      return const SearchScreen();
    }
    return ChangeNotifierProvider(
      create: (_) => AuthService(allowedEmails: widget.allowedEmails),
      child: Consumer<AuthService>(
        builder: (context, auth, _) {
          if (!kIsWeb) {
            return const SearchScreen();
          }
          if (!_attemptedSilent) {
            _attemptedSilent = true;
            // Fire-and-forget silent sign-in attempt; UI will rebuild on notify.
            auth.ensureSignedIn();
          }
          if (!auth.state.isSignedIn) {
            return _SignInScreen(onGoogle: () => auth.ensureSignedIn());
          }
          return const SearchScreen();
        },
      ),
    );
  }
}

class _SignInScreen extends StatelessWidget {
  final VoidCallback onGoogle;
  const _SignInScreen({required this.onGoogle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in required')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sign in to access PoseTrainer'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGoogle,
              icon: const Icon(Icons.login),
              label: const Text('Continue with Google'),
            ),
          ],
        ),
      ),
    );
  }
}
