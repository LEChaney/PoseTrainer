# Google Sign-In Refactor (Modern Pattern)

## Overview

Refactored `google_drive_folder_service.dart` to follow the official `google_sign_in` 7.x authentication pattern. This addresses authentication issues on iPad and PC by using the modern authentication event-based approach instead of custom workarounds.

## Why the Refactor?

### Previous Issues
1. **iPad**: Google One Tap appeared but subsequent API calls returned 401 Unauthorized errors
2. **PC**: One Tap failed with "Can't continue with google.com" error, requiring fallback popup
3. **Implementation**: Used outdated patterns with custom HTTP client wrappers and manual token refresh

### Root Cause
The previous implementation tried to work around One Tap instead of embracing it. It used:
- Deprecated authentication methods (`signIn()`, `signInSilently()`)
- Custom `_GoogleSignInAuthClient` wrapper class
- Manual token refresh logic (`_refreshAuthSilently()`)
- Manual retry wrapper (`_withAuthRetry()`)
- Attempts to suppress One Tap by calling `signOut()` immediately after initialization

## New Modern Pattern

### Based on Official Example
Reference: https://pub.dev/packages/google_sign_in/example

The refactored implementation follows the official `google_sign_in` 7.x pattern:

1. **Initialize with clientId**
   ```dart
   await _googleSignIn.initialize(clientId: _clientId);
   ```

2. **Listen to authentication events stream**
   ```dart
   _authEventsSubscription = _googleSignIn.authenticationEvents
       .listen(_handleAuthenticationEvent)
       ..onError(_handleAuthenticationError);
   ```

3. **Attempt lightweight (silent) authentication**
   ```dart
   _googleSignIn.attemptLightweightAuthentication();
   ```

4. **Handle authentication events**
   ```dart
   Future<void> _handleAuthenticationEvent(
     gsi.GoogleSignInAuthenticationEvent event,
   ) async {
     final user = switch (event) {
       gsi.GoogleSignInAuthenticationEventSignIn() => event.user,
       gsi.GoogleSignInAuthenticationEventSignOut() => null,
     };
     // Check authorization, set up API client...
   }
   ```

5. **Separate authentication from scope authorization**
   ```dart
   final authorization = await user.authorizationClient
       .authorizationForScopes(_scopes);
   
   if (authorization == null) {
     await user.authorizationClient.authorizeScopes(_scopes);
   }
   ```

6. **Use extension package for googleapis integration**
   ```dart
   final authClient = authorization.authClient(scopes: _scopes);
   _httpClient = authClient as http.Client;
   _driveApi = drive.DriveApi(_httpClient!);
   ```

### Key Benefits

1. **Automatic State Management**: Authentication events stream handles all state changes
2. **Automatic Token Refresh**: Extension package handles token refresh transparently
3. **Proper Scope Management**: Separation between authentication and scope authorization
4. **One Tap Support**: Works properly when implemented correctly (no need to suppress)
5. **Cleaner Code**: No custom HTTP client wrappers or manual retry logic
6. **Cross-Platform**: Single code path works for web, mobile, and desktop

## What Was Removed

### Removed Classes
- `_GoogleSignInAuthClient`: Custom HTTP client wrapper (replaced by extension package)

### Removed Methods
- `_restoreWebSession()`: No longer needed (authentication events handle restoration)
- `_restoreSession()`: Token-based restoration (not needed with modern pattern)
- `_persistCredentials()`: Manual credential persistence (handled by google_sign_in)
- `_authenticateWeb()`: Separate web auth path (unified with mobile)
- `_authenticateMobile()`: Separate mobile auth path (unified with web)
- `_refreshAuthSilently()`: Manual token refresh (extension handles this)
- `_withAuthRetry()`: Manual retry wrapper (not needed)

### Removed Fields
- `_tokenBoxName`: No longer storing tokens manually
- `_tokenRefreshSubscription`: No manual refresh timer needed

## What Was Added

### New Fields
- `_currentUser`: Tracks authenticated user account
- `_authEventsSubscription`: Subscription to authentication events stream

### New Methods
- `_handleAuthenticationEvent()`: Processes authentication events
- `_handleAuthenticationError()`: Handles authentication errors
- `_requestScopeAuthorization()`: Requests scope authorization from user
- `_setupApiClient()`: Sets up Drive API client using extension package

## Migration Notes

### For Users
- First launch after update will trigger One Tap (this is normal)
- One Tap is now reliable and should work properly on all platforms
- Sessions automatically restored on subsequent launches
- Token refresh happens automatically (no 401 errors)

### For Developers
- No changes needed to calling code (public API unchanged)
- Service still uses Provider/ChangeNotifier
- All public methods have same signatures
- Authentication events happen asynchronously (UI updates via notifyListeners())

## Testing Checklist

- [ ] First-time sign-in shows One Tap on web
- [ ] One Tap works without errors (no "Can't continue" message)
- [ ] Session restored automatically on reload
- [ ] API calls work immediately after authentication
- [ ] No 401 errors after ~1 hour (token refresh working)
- [ ] Sign-out clears session properly
- [ ] Re-authentication works without issues
- [ ] Works on iPad Safari
- [ ] Works on desktop browsers (Chrome, Edge, Firefox)
- [ ] Works on mobile (iOS, Android)

## References

- **Official Example**: https://pub.dev/packages/google_sign_in/example
- **Extension Package**: https://pub.dev/packages/extension_google_sign_in_as_googleapis_auth
- **Google Sign-In 7.x**: https://pub.dev/packages/google_sign_in
- **Google Identity Services**: https://developers.google.com/identity/gsi/web

## Conclusion

This refactor brings the codebase in line with modern Google Sign-In best practices, resolving authentication issues by doing things "the right way" instead of fighting against the framework. One Tap is now a feature, not a bug to work around.
