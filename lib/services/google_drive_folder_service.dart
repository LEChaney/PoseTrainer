// services/google_drive_folder_service.dart
// -----------------------------------------
// WHY: Provide persistent folder access across all platforms (especially iOS Safari)
// using Google Drive API. OAuth tokens survive app reloads, eliminating the need
// for repeated folder selection.
//
// CURRENT SCOPE:
// - OAuth2 authentication with refresh token persistence via Hive
// - List folders in user's Google Drive
// - Recursive scanning for image files
// - Thumbnail URLs for preview grids
// - Uniform random sampling from selected folders
// - Cross-platform (web, mobile, desktop)
//
// ADVANTAGES OVER FILE SYSTEM API:
// - Works on iOS Safari (no File System API support issues)
// - Persistent access via refresh tokens (no re-selection needed)
// - Built-in thumbnails and metadata
// - Cross-device folder sync
//
// OAUTH SETUP:
// 1. Create project at https://console.cloud.google.com
// 2. Enable Google Drive API
// 3. Create OAuth 2.0 credentials (Web application type)
// 4. Add authorized redirect URIs:
//    - http://localhost (for local testing)
//    - Your production domain
// 5. Replace CLIENT_ID below with your credentials
//
// FUTURE:
// - Image caching for offline practice
// - Folder watching via Drive API webhooks
// - Shared folder support

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:http/http.dart' as http;
import 'package:hive_ce/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import 'debug_logger.dart';

/// OAuth client ID - Replace with your own from Google Cloud Console
/// Get credentials at: https://console.cloud.google.com/apis/credentials
const String _clientId =
    '318937395146-q45i9v1g547jhg61khqs9v2hivreilup.apps.googleusercontent.com';
const String _clientSecret = 'YOUR_CLIENT_SECRET'; // Only needed for non-web

/// OAuth scopes - readonly access to Drive
const List<String> _scopes = [drive.DriveApi.driveReadonlyScope];

/// Represents a Google Drive folder with metadata and preview thumbnails.
class DriveFolderInfo {
  final String id; // Drive file ID
  final String name;
  final String? parentId;
  final DateTime? modifiedTime;
  final int imageCount; // Cached count from last scan
  final List<String> previewUrls; // Thumbnail URLs (up to 4)

  DriveFolderInfo({
    required this.id,
    required this.name,
    this.parentId,
    this.modifiedTime,
    this.imageCount = 0,
    this.previewUrls = const [],
  });

  DriveFolderInfo copyWith({
    String? id,
    String? name,
    String? parentId,
    DateTime? modifiedTime,
    int? imageCount,
    List<String>? previewUrls,
  }) {
    return DriveFolderInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      imageCount: imageCount ?? this.imageCount,
      previewUrls: previewUrls ?? this.previewUrls,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'modifiedTime': modifiedTime?.toIso8601String(),
    'imageCount': imageCount,
    'previewUrls': previewUrls,
  };

  factory DriveFolderInfo.fromJson(Map<String, dynamic> json) {
    return DriveFolderInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.parse(json['modifiedTime'] as String)
          : null,
      imageCount: (json['imageCount'] as int?) ?? 0,
      previewUrls:
          (json['previewUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

/// Image file metadata from Google Drive.
class DriveImageFile {
  final String id;
  final String name;
  final String? mimeType;
  final String? thumbnailLink;
  final String? webContentLink; // Direct download URL
  final int? size;

  DriveImageFile({
    required this.id,
    required this.name,
    this.mimeType,
    this.thumbnailLink,
    this.webContentLink,
    this.size,
  });

  factory DriveImageFile.fromDriveFile(drive.File file) {
    return DriveImageFile(
      id: file.id!,
      name: file.name!,
      mimeType: file.mimeType,
      thumbnailLink: file.thumbnailLink,
      webContentLink: file.webContentLink,
      size: file.size != null ? int.tryParse(file.size!) : null,
    );
  }
}

/// Service for managing folders via Google Drive API with persistent OAuth access.
class GoogleDriveFolderService extends ChangeNotifier {
  static const String _tag = 'GoogleDriveFolderService';
  static const String _tokenBoxName = 'google_drive_tokens';
  static const String _foldersBoxName = 'google_drive_folders';

  drive.DriveApi? _driveApi;
  http.Client? _httpClient;
  gsi.GoogleSignIn? _googleSignIn; // Keep reference to GoogleSignIn instance
  bool _isAuthenticated = false;
  bool _isInitialized = false;
  bool _isAuthenticating = false;

  final List<DriveFolderInfo> _folders = [];

  // Cache of scanned images per folder
  final Map<String, List<DriveImageFile>> _imageCache = {};

  List<DriveFolderInfo> get folders => List.unmodifiable(_folders);
  bool get isAuthenticated => _isAuthenticated;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticating => _isAuthenticating;

  /// Initialize service and attempt to restore previous session.
  Future<void> init() async {
    if (_isInitialized) {
      infoLog('GoogleDriveFolderService already initialized', tag: _tag);
      return;
    }

    infoLog('Initializing Google Drive folder service', tag: _tag);

    try {
      // Load persisted folders first (even if not authenticated)
      await _loadPersistedFolders();

      // Attempt to restore credentials from storage
      final restored = await _restoreSession();
      if (restored) {
        infoLog('Session restored from storage', tag: _tag);
      } else {
        infoLog('No stored session found', tag: _tag);
      }
    } catch (e, stack) {
      errorLog(
        'Failed to initialize Google Drive service',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Authenticate with Google Drive using OAuth2.
  Future<bool> authenticate() async {
    if (_isAuthenticating) {
      warningLog('Authentication already in progress', tag: _tag);
      return false;
    }

    _isAuthenticating = true;
    notifyListeners();

    infoLog('Starting Google Drive authentication', tag: _tag);

    try {
      if (kIsWeb) {
        return await _authenticateWeb();
      } else {
        return await _authenticateMobile();
      }
    } catch (e, stack) {
      errorLog('Authentication failed', tag: _tag, error: e, stackTrace: stack);
      return false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  /// Web authentication using browser OAuth flow.
  Future<bool> _authenticateWeb() async {
    infoLog('Using Google Sign-In for web authentication', tag: _tag);

    try {
      // Use google_sign_in which handles the new Google Identity Services API
      _googleSignIn = gsi.GoogleSignIn(
        clientId: _clientId,
        scopes: _scopes,
      );

      // Try silent sign-in first (uses existing session if available)
      var account = await _googleSignIn!.signInSilently();

      // If silent sign-in fails, try regular sign-in
      if (account == null) {
        infoLog('Silent sign-in failed, prompting user', tag: _tag);
        account = await _googleSignIn!.signIn();
      }

      if (account == null) {
        warningLog('User cancelled sign-in', tag: _tag);
        return false;
      }

      infoLog('User signed in: ${account.email}', tag: _tag);

      // Create authenticated HTTP client using google_sign_in's auth
      _httpClient = _GoogleSignInAuthClient(_googleSignIn!, http.Client());

      // Create Drive API client
      _driveApi = drive.DriveApi(_httpClient!);
      _isAuthenticated = true;

      infoLog('Web authentication successful', tag: _tag);
      notifyListeners();
      return true;
    } catch (e, stack) {
      errorLog(
        'Web authentication failed',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Mobile/desktop authentication using installed app flow.
  Future<bool> _authenticateMobile() async {
    infoLog('Using mobile/desktop OAuth flow', tag: _tag);

    try {
      final id = auth_io.ClientId(_clientId, _clientSecret);
      final httpClient = http.Client();

      // Obtain credentials via user consent
      final credentials = await auth_io.obtainAccessCredentialsViaUserConsent(
        id,
        _scopes,
        httpClient,
        (url) async {
          // Open browser for user consent
          infoLog('Opening consent URL: $url', tag: _tag);
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            errorLog('Cannot launch URL: $url', tag: _tag);
          }
        },
      );

      // Store tokens
      await _persistCredentials(credentials);

      // Create authenticated client
      _httpClient = auth_io.authenticatedClient(httpClient, credentials);
      _driveApi = drive.DriveApi(_httpClient!);
      _isAuthenticated = true;

      infoLog('Mobile authentication successful', tag: _tag);
      notifyListeners();
      return true;
    } catch (e, stack) {
      errorLog(
        'Mobile authentication failed',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Attempt to refresh authentication silently when token expires.
  /// Returns true if refresh succeeded, false if user needs to re-authenticate.
  Future<bool> _refreshAuthSilently() async {
    infoLog('Attempting silent token refresh', tag: _tag);

    try {
      if (kIsWeb && _googleSignIn != null) {
        // For web, try silent sign-in
        final account = await _googleSignIn!.signInSilently();

        if (account != null) {
          infoLog('Silent token refresh successful', tag: _tag);
          // The _GoogleSignInAuthClient will automatically use the refreshed token
          return true;
        } else {
          warningLog('Silent sign-in returned null account', tag: _tag);
          return false;
        }
      } else {
        // For mobile/desktop, the authenticatedClient should handle refresh automatically
        // If we get here, we need to re-authenticate
        warningLog('Token refresh not available for mobile', tag: _tag);
        return false;
      }
    } catch (e, stack) {
      errorLog(
        'Failed to refresh token silently',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Wrapper that handles authentication errors and retries with token refresh.
  Future<T?> _withAuthRetry<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (e) {
      // Check if it's an authentication error
      final errorStr = e.toString();
      if (errorStr.contains('invalid_token') ||
          errorStr.contains('Access was denied') ||
          errorStr.contains('401')) {
        warningLog(
          'Authentication error detected, attempting token refresh',
          tag: _tag,
        );

        // Try to refresh silently
        final refreshed = await _refreshAuthSilently();

        if (refreshed) {
          // Retry the operation with refreshed token
          infoLog('Retrying operation with refreshed token', tag: _tag);
          try {
            return await operation();
          } catch (retryError) {
            errorLog(
              'Operation failed after token refresh',
              tag: _tag,
              error: retryError,
            );
            rethrow;
          }
        } else {
          // Need full re-authentication
          errorLog(
            'Token refresh failed, user needs to re-authenticate',
            tag: _tag,
          );
          _isAuthenticated = false;
          notifyListeners();
          rethrow;
        }
      } else {
        // Not an auth error, just rethrow
        rethrow;
      }
    }
  }

  /// Persist OAuth credentials to Hive for session restoration.
  Future<void> _persistCredentials(
    auth_io.AccessCredentials credentials,
  ) async {
    try {
      final box = await Hive.openBox<dynamic>(_tokenBoxName);
      await box.put('access_token', credentials.accessToken.data);
      await box.put('token_type', credentials.accessToken.type);
      await box.put('expiry', credentials.accessToken.expiry.toIso8601String());

      if (credentials.refreshToken != null) {
        await box.put('refresh_token', credentials.refreshToken);
        infoLog('Refresh token stored', tag: _tag);
      }

      await box.put('scopes', credentials.scopes);

      infoLog('Credentials persisted to storage', tag: _tag);
    } catch (e, stack) {
      errorLog(
        'Failed to persist credentials',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Restore OAuth session from Hive storage.
  Future<bool> _restoreSession() async {
    try {
      final box = await Hive.openBox<dynamic>(_tokenBoxName);

      final accessTokenData = box.get('access_token') as String?;
      final tokenType = box.get('token_type') as String?;
      final expiryStr = box.get('expiry') as String?;
      final refreshToken = box.get('refresh_token') as String?;
      final scopes = (box.get('scopes') as List<dynamic>?)?.cast<String>();

      if (accessTokenData == null || tokenType == null || expiryStr == null) {
        debugLog('No stored credentials found', tag: _tag);
        return false;
      }

      final accessToken = auth_io.AccessToken(
        tokenType,
        accessTokenData,
        DateTime.parse(expiryStr),
      );

      final credentials = auth_io.AccessCredentials(
        accessToken,
        refreshToken,
        scopes ?? _scopes,
      );

      // Create authenticated client
      final httpClient = http.Client();
      _httpClient = auth_io.authenticatedClient(httpClient, credentials);
      _driveApi = drive.DriveApi(_httpClient!);
      _isAuthenticated = true;

      infoLog('Session restored successfully', tag: _tag);
      notifyListeners();
      return true;
    } catch (e, stack) {
      errorLog(
        'Failed to restore session',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      // Clear invalid tokens
      try {
        final box = await Hive.openBox<dynamic>(_tokenBoxName);
        await box.clear();
      } catch (_) {}
      return false;
    }
  }

  /// Load persisted folder metadata from Hive.
  Future<void> _loadPersistedFolders() async {
    try {
      final box = await Hive.openBox<dynamic>(_foldersBoxName);
      final folderJsonList = box.get('folders') as List<dynamic>?;

      if (folderJsonList == null || folderJsonList.isEmpty) {
        debugLog('No persisted folders found', tag: _tag);
        return;
      }

      _folders.clear();
      for (final json in folderJsonList) {
        final folder = DriveFolderInfo.fromJson(
          Map<String, dynamic>.from(json as Map),
        );
        _folders.add(folder);
      }

      infoLog('Loaded ${_folders.length} persisted folders', tag: _tag);
      notifyListeners();
    } catch (e, stack) {
      errorLog(
        'Failed to load persisted folders',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Persist folder list to Hive.
  Future<void> _persistFolders() async {
    try {
      final box = await Hive.openBox<dynamic>(_foldersBoxName);
      final folderJsonList = _folders.map((f) => f.toJson()).toList();
      await box.put('folders', folderJsonList);
      debugLog('Persisted ${_folders.length} folders', tag: _tag);
    } catch (e, stack) {
      errorLog(
        'Failed to persist folders',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// List all folders in user's Google Drive root.
  Future<List<DriveFolderInfo>> listDriveFolders() async {
    if (_driveApi == null) {
      warningLog('Cannot list folders: not authenticated', tag: _tag);
      return [];
    }

    infoLog('Listing Google Drive folders', tag: _tag);

    try {
      // Use auth retry wrapper to handle token expiration
      final result = await _withAuthRetry<List<DriveFolderInfo>>(() async {
        // Query for folders only (not in trash, in root)
        final query =
            "mimeType='application/vnd.google-apps.folder' and trashed=false and 'root' in parents";
        final fileList = await _driveApi!.files.list(
          q: query,
          spaces: 'drive',
          orderBy: 'name',
          pageSize: 1000, // Get up to 1000 folders
          $fields: 'files(id, name, parents, modifiedTime)',
        );

        final folders =
            fileList.files?.map((file) {
              return DriveFolderInfo(
                id: file.id!,
                name: file.name!,
                parentId: file.parents?.firstOrNull,
                modifiedTime: file.modifiedTime,
              );
            }).toList() ??
            [];

        infoLog('Found ${folders.length} folders in Drive root', tag: _tag);
        return folders;
      });

      return result ?? [];
    } catch (e, stack) {
      errorLog(
        'Failed to list Drive folders',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  /// Add a folder to the collection and scan for images.
  Future<bool> addFolder(DriveFolderInfo folder) async {
    if (_folders.any((f) => f.id == folder.id)) {
      warningLog('Folder ${folder.name} already added', tag: _tag);
      return false;
    }

    infoLog('Adding folder: ${folder.name}', tag: _tag);

    // Scan folder for images to get count and preview thumbnails
    final images = await scanFolder(folder.id);

    // Extract preview URLs (first 4 images with thumbnails)
    final previewUrls = images
        .where((img) => img.thumbnailLink != null)
        .take(4)
        .map((img) => img.thumbnailLink!)
        .toList();

    // Add folder with updated metadata
    final folderWithMetadata = folder.copyWith(
      imageCount: images.length,
      previewUrls: previewUrls,
    );

    _folders.add(folderWithMetadata);
    await _persistFolders();

    infoLog(
      'Folder added: ${folder.name} (${images.length} images)',
      tag: _tag,
    );
    notifyListeners();
    return true;
  }

  /// Remove a folder from the collection.
  Future<void> removeFolder(String folderId) async {
    final initialLength = _folders.length;
    _folders.removeWhere((f) => f.id == folderId);
    if (_folders.length < initialLength) {
      _imageCache.remove(folderId);
      await _persistFolders();
      infoLog('Removed folder: $folderId', tag: _tag);
      notifyListeners();
    }
  }

  /// Scan a folder recursively for image files.
  Future<List<DriveImageFile>> scanFolder(String folderId) async {
    if (_driveApi == null) {
      warningLog('Cannot scan folder: not authenticated', tag: _tag);
      return [];
    }

    // Check cache first
    if (_imageCache.containsKey(folderId)) {
      debugLog('Returning cached images for folder: $folderId', tag: _tag);
      return _imageCache[folderId]!;
    }

    infoLog('Scanning folder recursively: $folderId', tag: _tag);

    try {
      final images = <DriveImageFile>[];
      await _scanFolderRecursive(folderId, images);

      // Cache results
      _imageCache[folderId] = images;

      infoLog('Scan complete: ${images.length} images found', tag: _tag);
      return images;
    } catch (e, stack) {
      errorLog('Failed to scan folder', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  /// Recursively scan folder and subfolders for images.
  Future<void> _scanFolderRecursive(
    String folderId,
    List<DriveImageFile> accumulator,
  ) async {
    // Query for files in this folder
    final query = "'$folderId' in parents and trashed=false";

    String? pageToken;
    int entryCount = 0;

    do {
      // Use auth retry wrapper
      final fileList = await _withAuthRetry<drive.FileList>(() async {
        return await _driveApi!.files.list(
          q: query,
          spaces: 'drive',
          pageSize: 1000,
          pageToken: pageToken,
          $fields:
              'nextPageToken, files(id, name, mimeType, thumbnailLink, webContentLink, size, parents)',
        );
      });

      if (fileList == null) break;

      for (final file in fileList.files ?? []) {
        entryCount++;
        final mimeType = file.mimeType ?? '';

        if (mimeType == 'application/vnd.google-apps.folder') {
          // Recurse into subfolder
          debugLog('Entering subfolder: ${file.name}', tag: _tag);
          await _scanFolderRecursive(file.id!, accumulator);
        } else if (_isImageMimeType(mimeType)) {
          // Add image file
          accumulator.add(DriveImageFile.fromDriveFile(file));
        }
      }

      pageToken = fileList.nextPageToken;
    } while (pageToken != null);

    debugLog('Scanned $entryCount entries in folder $folderId', tag: _tag);
  }

  /// Check if MIME type is an image format.
  bool _isImageMimeType(String mimeType) {
    const imageTypes = [
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp',
      'image/heic',
      'image/heif',
    ];
    return imageTypes.any((type) => mimeType.startsWith(type));
  }

  /// Sample random images uniformly from selected folders.
  Future<List<DriveImageFile>> sampleImages(
    List<String> folderIds,
    int count,
  ) async {
    infoLog(
      'Sampling $count images from ${folderIds.length} folders',
      tag: _tag,
    );

    // Collect all images from selected folders
    final allImages = <DriveImageFile>[];
    for (final folderId in folderIds) {
      final images = await scanFolder(folderId);
      allImages.addAll(images);
    }

    if (allImages.isEmpty) {
      warningLog('No images found in selected folders', tag: _tag);
      return [];
    }

    // Uniform random sampling
    final random = math.Random();
    allImages.shuffle(random);
    final sampled = allImages.take(count).toList();

    infoLog(
      'Sampled ${sampled.length} images from ${allImages.length} total',
      tag: _tag,
    );
    return sampled;
  }

  /// Download image file bytes from Drive using authenticated client.
  /// Returns null if download fails.
  Future<Uint8List?> downloadImageBytes(String fileId) async {
    if (_driveApi == null || _httpClient == null) {
      warningLog('Cannot download image: not authenticated', tag: _tag);
      return null;
    }

    try {
      infoLog('Downloading image: $fileId', tag: _tag);

      // Use auth retry wrapper to handle token expiration
      final bytes = await _withAuthRetry<Uint8List>(() async {
        // Use Drive API to get file content
        // The alt=media parameter tells Drive to return file content instead of metadata
        final media =
            await _driveApi!.files.get(
                  fileId,
                  downloadOptions: drive.DownloadOptions.fullMedia,
                )
                as drive.Media;

        // Read the stream into a byte list
        final chunks = <List<int>>[];
        await for (final chunk in media.stream) {
          chunks.add(chunk);
        }

        // Combine all chunks
        return Uint8List.fromList(chunks.expand((c) => c).toList());
      });

      if (bytes != null) {
        infoLog('Downloaded ${bytes.length} bytes for $fileId', tag: _tag);
      }
      return bytes;
    } catch (e, stack) {
      errorLog(
        'Failed to download image $fileId',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Sign out and clear credentials.
  Future<void> signOut() async {
    infoLog('Signing out from Google Drive', tag: _tag);

    // Sign out from GoogleSignIn if on web
    if (_googleSignIn != null) {
      try {
        await _googleSignIn!.signOut();
        infoLog('Signed out from GoogleSignIn', tag: _tag);
      } catch (e) {
        warningLog('Failed to sign out from GoogleSignIn: $e', tag: _tag);
      }
      _googleSignIn = null;
    }

    _driveApi = null;
    _httpClient?.close();
    _httpClient = null;
    _isAuthenticated = false;
    _imageCache.clear();

    // Clear persisted credentials
    try {
      final tokenBox = await Hive.openBox<dynamic>(_tokenBoxName);
      await tokenBox.clear();
      infoLog('Credentials cleared from storage', tag: _tag);
    } catch (e, stack) {
      errorLog(
        'Failed to clear credentials',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }

    notifyListeners();
  }

  /// Clear all folders (but keep authentication).
  Future<void> clearFolders() async {
    infoLog('Clearing all folders', tag: _tag);
    _folders.clear();
    _imageCache.clear();
    await _persistFolders();
    notifyListeners();
  }

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }
}

/// Custom HTTP client that uses google_sign_in authentication.
/// This bridges google_sign_in with googleapis by providing auth headers.
class _GoogleSignInAuthClient extends http.BaseClient {
  final gsi.GoogleSignIn _googleSignIn;
  final http.Client _baseClient;

  _GoogleSignInAuthClient(this._googleSignIn, this._baseClient);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Get current account
    final account = _googleSignIn.currentUser;

    if (account == null) {
      throw Exception('No authenticated user');
    }

    // Get auth headers and add to request
    final authHeaders = await account.authHeaders;
    request.headers.addAll(authHeaders);

    return _baseClient.send(request);
  }

  @override
  void close() {
    _baseClient.close();
  }
}
