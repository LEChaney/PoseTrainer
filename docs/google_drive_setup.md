# Google Drive Folder Integration - Setup Guide

## Overview

The folder practice mode now uses Google Drive API for persistent folder access across all platforms, including iOS Safari. OAuth tokens are stored in Hive, eliminating the need for repeated folder selection on app reloads.

## Advantages Over File System Access API

✅ **Works on iOS Safari** - No File System API support issues  
✅ **Persistent access** - OAuth refresh tokens survive app reloads  
✅ **Cross-device sync** - Access same folders on mobile + desktop  
✅ **Built-in thumbnails** - Drive API provides thumbnail URLs  
✅ **No re-selection needed** - Seamless experience across sessions

## Google Cloud Console Setup

### 1. Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" → "New Project"
3. Name: `PoseTrainer` (or your app name)
4. Click "Create"

### 2. Enable Google Drive API

1. In your project, go to "APIs & Services" → "Library"
2. Search for "Google Drive API"
3. Click on it → Click "Enable"

### 3. Create OAuth 2.0 Credentials

#### For Web (Required):

1. Go to "APIs & Services" → "Credentials"
2. Click "Create Credentials" → "OAuth client ID"
3. Application type: **Web application**
4. Name: `PoseTrainer Web Client`
5. **Authorized JavaScript origins:**
   - `http://localhost:5000` (for local testing)
   - `http://localhost` (fallback)
   - `https://your domain.com` (for production)
6. **Authorized redirect URIs:**
   - `http://localhost:5000` (for local testing)
   - `http://localhost` (fallback)  
   - `https://yourdomain.com` (for production)
7. Click "Create"
8. **Copy the Client ID** (you'll need this)

#### For Mobile (Optional, for native apps):

1. Create another OAuth client ID
2. Application type: **iOS** or **Android**
3. Follow platform-specific setup
4. Copy the Client ID

### 4. Configure OAuth Consent Screen

1. Go to "APIs & Services" → "OAuth consent screen"
2. User Type: **External** (unless you have a workspace)
3. App name: `PoseTrainer`
4. User support email: Your email
5. Scopes: Click "Add or Remove Scopes"
   - Search for "Google Drive API"
   - Select: `.../auth/drive.readonly` (read-only access)
6. Test users: Add your email for testing
7. Click "Save and Continue"

### 5. Publishing Status

For testing:
- Leave the app in "Testing" mode
- Add test users via "Test users" section

For production:
- Submit for verification
- This process can take several days

## Code Configuration

### Update Client ID

Open `lib/services/google_drive_folder_service.dart`:

```dart
/// OAuth client ID - Replace with your own from Google Cloud Console
const String _clientId = 'YOUR_CLIENT_ID_HERE.apps.googleusercontent.com';
const String _clientSecret = 'YOUR_CLIENT_SECRET'; // Only for non-web
```

Replace `YOUR_CLIENT_ID_HERE` with your actual Client ID from step 3.

**Important:** For web, you don't need a client secret. For mobile/desktop, get the client secret from the credentials page.

### Web-Specific Configuration (IMPORTANT)

For the OAuth flow to work on web, you need to ensure CORS is properly configured. The implicit browser flow used by `googleapis_auth` handles redirects automatically, but your web server needs to allow the OAuth popup.

## Testing the Implementation

### Local Testing (Web)

1. Run the app with web server:
   ```bash
   flutter run -d web-server --web-port 5000
   ```

2. Open browser to `http://localhost:5000`

3. Navigate to "Folder Practice" mode

4. Click "Sign In with Google"

5. OAuth popup should appear → Grant access

6. You should be redirected back to the app (authenticated)

7. Click the "+" folder icon to browse Drive folders

8. Select a folder → It will be scanned for images

9. Selected folders appear as cards with thumbnail previews

10. Select one or more folders → Configure session → Start

### iOS Safari Testing

1. Build for web:
   ```bash
   flutter build web --release
   ```

2. Deploy to an HTTPS server (required for OAuth)

3. Update Google Cloud Console with production URL

4. Test on iOS device:
   - Open Safari
   - Navigate to your app URL
   - Complete OAuth flow
   - Add folders from Drive
   - **Close and reopen app** → Session should persist!

### Testing Persistence

1. Authenticate and add folders
2. Refresh the page (F5) or close/reopen app
3. App should:
   - ✅ Restore authentication automatically
   - ✅ Load previously selected folders
   - ✅ Show correct image counts and thumbnails
4. No re-authentication or folder re-selection needed!

## User Flow

### First Time:

1. User opens Folder Practice mode
2. Sees "Connect to Google Drive" prompt
3. Clicks "Sign In with Google"
4. OAuth popup → Grants access
5. Returns to app (now authenticated)
6. Clicks "+" to add folders
7. Browses Drive root folders
8. Selects a folder → App scans recursively for images
9. Folder appears as a card with 2x2 thumbnail grid
10. Repeats to add more folders
11. Selects folders for session → Starts practice

### Subsequent Sessions:

1. User opens app
2. **Automatically authenticated** (tokens restored from Hive)
3. **Previously selected folders already loaded**
4. User can immediately start a session
5. Or add/remove folders as needed

## Features

### Current Implementation

✅ OAuth2 authentication with persistence  
✅ Browse Drive folders (root level only for now)  
✅ Recursive folder scanning for images  
✅ Thumbnail preview grids (2x2 layout)  
✅ Multi-select folders  
✅ Image count per folder  
✅ Uniform random sampling from selected folders  
✅ Session configuration (count, time)  
✅ Sign out / Clear folders options

### Future Enhancements

- Navigate into subfolders (breadcrumb navigation)
- Search folders by name
- Sort options (name, date, size)
- Cached image loading for offline practice
- Shared folder support
- Folder watching via Drive API webhooks

## API Quotas & Limits

### Free Tier Limits:

- **10,000 queries per day** (should be plenty for individual use)
- **1,000 queries per 100 seconds per user**

### Rate Limiting Strategy:

The service implements caching to minimize API calls:
- Folder scans are cached in memory
- Only re-scan when explicitly requested
- Token refresh handled automatically by googleapis_auth

### If You Hit Limits:

1. Increase quotas in Google Cloud Console (may require billing)
2. Implement more aggressive caching
3. Reduce scan frequency

## Security Considerations

### OAuth Tokens

- ✅ Tokens stored in Hive (IndexedDB on web)
- ✅ Refresh tokens allow persistent access
- ✅ Read-only Drive scope (no modification permissions)
- ⚠️ Anyone with device access can use tokens
- ⚠️ Implement additional app-level security if needed

### Production Deployment

For production apps:
- Use HTTPS only (required for OAuth)
- Implement proper error handling
- Monitor API usage
- Handle token expiration gracefully
- Add logout on security-sensitive actions

## Troubleshooting

### "OAuth client ID not found" Error

- Check that Client ID is correct in code
- Verify authorized origins/redirect URIs in Console
- Ensure you're using the Web application client ID

### "Access blocked: This app isn't verified"

- Your app is in testing mode
- Add yourself as a test user in OAuth consent screen
- Or submit for verification (production)

### "The developer hasn't given you access to this app"

- You need to be added as a test user
- Go to OAuth consent screen → Test users → Add

### Authentication popup is blocked

- Browser is blocking popups
- Allow popups for your app domain
- Or use external redirect flow instead

### "Invalid redirect URI"

- Check that your current URL matches authorized redirect URIs
- For localhost: Use exact port number
- For production: Use exact HTTPS URL

### Tokens don't persist on reload

- Check Hive initialization in main.dart
- Verify Hive boxes are being opened correctly
- Check browser console for storage errors

## Code References

### Key Files:

- `lib/services/google_drive_folder_service.dart` - Core Drive API service
- `lib/screens/folder_select_screen.dart` - UI for folder selection
- `lib/main.dart` - Service provider integration
- `pubspec.yaml` - Dependencies configuration

### Key Dependencies:

- `googleapis: ^13.2.0` - Google APIs client library
- `googleapis_auth: ^1.6.0` - OAuth2 authentication
- `url_launcher: ^6.3.1` - Open browser for OAuth
- `hive_ce: ^2.13.2` - Token persistence

## Next Steps

1. Get your Google Cloud Console credentials
2. Update `_clientId` in `google_drive_folder_service.dart`
3. Test locally at `http://localhost:5000`
4. Deploy to HTTPS for mobile testing
5. Add your domain to authorized origins
6. Test on iOS Safari (the critical platform!)

**Note:** The first time a user authenticates, they'll see Google's consent screen. Subsequent sessions will be automatic with no user interaction needed!
