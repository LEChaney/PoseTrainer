# Google Sign-In Web Implementation Guide

## Critical: Web vs Mobile Authentication

The `google_sign_in` 7.x plugin uses **completely different** authentication methods for web vs mobile:

### ❌ **Web: `authenticate()` DOES NOT WORK**
```dart
await GoogleSignIn.instance.authenticate(); // ❌ Throws UnimplementedError on web!
```

### ✅ **Web: Must use `renderButton()`**
```dart
import 'package:google_sign_in_web/web_only.dart' as web;

// Render Google's official sign-in button
web.renderButton(
  configuration: web.GSIButtonConfiguration(
    type: web.GSIButtonType.standard,
    theme: web.GSIButtonTheme.filledBlue,
    size: web.GSIButtonSize.large,
    // ...
  ),
);
```

## Why This Limitation?

Google's [Identity Services (GIS) SDK](https://developers.google.com/identity/gsi/web) requires all web sign-ins to happen through **official Google-rendered UI**. This is a security measure to prevent phishing.

The GIS SDK loads directly in the browser and manages authentication. Your Flutter app cannot trigger sign-in programmatically - it must be user-initiated through Google's button.

## Implementation in PoseCoach

We've created a **unified button widget** that works across all platforms:

### `lib/widgets/google_sign_in_button.dart`

```dart
/// Cross-platform Google Sign-In button.
/// - Web: Renders Google's official button
/// - Mobile/Desktop: Custom button calling authenticate()
class GoogleSignInButton extends StatelessWidget {
  final GoogleDriveFolderService service;
  
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return web.renderButton(...); // Google's official button
    } else {
      return FilledButton.icon(...); // Custom button + authenticate()
    }
  }
}
```

### Usage in Folder Select Screen

```dart
// Old code (doesn't work on web):
FilledButton.icon(
  onPressed: () => service.authenticate(), // ❌ Fails on web
  label: Text('Sign In with Google'),
)

// New code (works everywhere):
GoogleSignInButton(service: service) // ✅ Works on web + mobile
```

## Authentication Flow

### Web Flow:
1. User sees Google's official "Sign in with Google" button
2. User clicks button
3. Google shows One Tap or account picker
4. User authenticates with Google
5. `authenticationEvents` stream fires `GoogleSignInAuthenticationEventSignIn`
6. Event handler sets up Drive API client
7. App can now make API calls

### Mobile/Desktop Flow:
1. User sees custom "Sign In with Google" button
2. User clicks button
3. App calls `GoogleSignIn.instance.authenticate()`
4. Native SDK shows account picker
5. User authenticates
6. `authenticationEvents` stream fires `GoogleSignInAuthenticationEventSignIn`
7. Event handler sets up Drive API client
8. App can now make API calls

## Configuration Requirements

### `web/index.html`

**Required meta tags:**

```html
<head>
  <!-- Client ID for Google Sign-In -->
  <meta name="google-signin-client_id" content="YOUR_CLIENT_ID.apps.googleusercontent.com">
  
  <!-- Referrer policy for CORS -->
  <meta name="referrer" content="no-referrer-when-downgrade">
</head>
```

### Google Cloud Console

**Authorized JavaScript origins** must include your development and production domains:

```
http://localhost
http://localhost:5000
https://localhost
https://localhost:5000
https://your-app.web.app
```

**Authorized redirect URIs** (NO ports for web):

```
http://localhost
https://localhost
https://your-app.web.app
```

## Button Customization

The Google button can be customized with various options:

```dart
web.renderButton(
  configuration: web.GSIButtonConfiguration(
    // Button type
    type: web.GSIButtonType.standard, // or .icon
    
    // Theme (matches app theme)
    theme: Theme.of(context).brightness == Brightness.dark
        ? web.GSIButtonTheme.filledBlack
        : web.GSIButtonTheme.filledBlue,
    
    // Size
    size: web.GSIButtonSize.large, // .small, .medium, .large
    
    // Text
    text: web.GSIButtonText.signinWith, // or .signin, .signup, etc.
    
    // Shape
    shape: web.GSIButtonShape.rectangular, // or .pill, .circle, .square
    
    // Logo alignment
    logoAlignment: web.GSIButtonLogoAlignment.left, // or .center
  ),
)
```

## Debugging Web Authentication

### Check if renderButton is called:

Open Chrome DevTools → Console and look for:
```
[GSI_LOGGER]: Button rendered successfully
```

### Check for CORS errors:

```
ERR_FAILED
Server did not send correct CORS headers
```
→ Check your Authorized JavaScript origins in Google Cloud Console

### Check authentication events:

In your code:
```dart
_googleSignIn.authenticationEvents.listen((event) {
  print('Auth event: ${event.runtimeType}'); // Should see SignIn or SignOut
});
```

### Verify meta tags:

View page source and confirm:
```html
<meta name="google-signin-client_id" content="318937395146-...">
<meta name="referrer" content="no-referrer-when-downgrade">
```

## Common Issues

### ❌ "UnimplementedError: authenticate is not supported on the web"
**Solution**: Use `GoogleSignInButton` widget instead of calling `authenticate()`

### ❌ Button doesn't appear
**Solution**: Check that `google-signin-client_id` meta tag is in `web/index.html`

### ❌ CORS errors
**Solution**: Add `http://localhost:5000` and `http://localhost` to Authorized JavaScript origins

### ❌ Button appears but clicking does nothing
**Solution**: Check browser console for errors; ensure Google Identity Services API is enabled

### ❌ One Tap shows but API calls fail with 401
**Solution**: Check that you're requesting proper scopes in `_requestScopeAuthorization()`

## Token Expiration

**Important**: On web, access tokens expire after 3600 seconds (1 hour) and are **not automatically refreshed**.

When API calls start failing with 401/403 errors:
1. Detect the error in your API calls
2. Show the Google Sign-In button again
3. User clicks to re-authorize
4. Get new token
5. Retry failed operation

We handle this in `google_drive_folder_service.dart` by wrapping API calls with error handling.

## References

- **Google Identity Services**: https://developers.google.com/identity/gsi/web
- **google_sign_in package**: https://pub.dev/packages/google_sign_in
- **google_sign_in_web package**: https://pub.dev/packages/google_sign_in_web
- **GIS Button Customization**: https://developers.google.com/identity/gsi/web/reference/html-reference

## Migration Note

If you're migrating from google_sign_in 6.x or earlier:
- Old: `await _googleSignIn.signIn()` worked on web
- New: Must use `renderButton()` on web
- Old: Manual token refresh
- New: Tokens expire, must re-authenticate (no refresh)

See official [migration guide](https://github.com/flutter/packages/blob/main/packages/google_sign_in/google_sign_in/MIGRATION.md) for full details.
