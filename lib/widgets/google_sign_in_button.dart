// Export a platform-appropriate Google Sign-In button implementation.
export 'google_sign_in_button_fallback.dart'
    if (dart.library.html) 'google_sign_in_button_web_html.dart';
