import 'package:flutter/material.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressedFallback;
  const GoogleSignInButton({super.key, this.onPressedFallback});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressedFallback,
      icon: const Icon(Icons.login),
      label: const Text('Continue with Google'),
    );
  }
}
