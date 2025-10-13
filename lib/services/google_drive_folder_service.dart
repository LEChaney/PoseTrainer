// services/google_drive_folder_service.dart
// -----------------------------------------
// WHY: Provide persistent folder access across all platforms (especially iOS Safari)
// using Google Drive API. Uses modern google_sign_in 7.x authentication pattern.
//
// AUTHENTICATION PATTERN:
// - Follows official google_sign_in example: https://pub.dev/packages/google_sign_in/example
// - Uses authentication events stream for state management
// - attemptLightweightAuthentication() for silent sign-in
// - authenticate() for explicit user sign-in
// - Scope authorization separate from authentication
// - extension_google_sign_in_as_googleapis_auth for googleapis integration
//
// CURRENT SCOPE:
// - OAuth2 authentication with automatic session restoration
// - List folders in user's Google Drive (including subfolders)
// - Recursive scanning for image files
// - Thumbnail URLs for preview grids
// - Uniform random sampling from selected folders
// - Cross-platform (web, mobile, desktop)
//
// ADVANTAGES OVER FILE SYSTEM API:
// - Works on iOS Safari (no File System API support issues)
// - Persistent access via automatic token refresh
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

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:hive_ce/hive.dart';
import 'debug_logger.dart';

/// OAuth client ID - Replace with your own from Google Cloud Console
/// Get credentials at: https://console.cloud.google.com/apis/credentials
const String _clientId =
    '318937395146-q45i9v1g547jhg61khqs9v2hivreilup.apps.googleusercontent.com';

/// Core OAuth scopes required for Drive API operations.
const List<String> _scopes = [
  drive.DriveApi.driveReadonlyScope,
  drive.DriveApi.driveFileScope,
];

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

/// Service for Google Drive folder access using OAuth2.
///
/// Uses modern google_sign_in 7.x authentication pattern:
/// - Authentication events stream for state management
/// - attemptLightweightAuthentication() for silent sign-in
/// - authenticate() for explicit user sign-in
/// - Scope authorization separate from authentication
///
/// Reference: https://pub.dev/packages/google_sign_in/example
class GoogleDriveFolderService extends ChangeNotifier {
  static const String _tag = 'GoogleDriveFolderService';
  static const String _foldersBoxName = 'google_drive_folders';

  // --- Member Fields ---

  /// Drive API wrapper instance.
  drive.DriveApi? _driveApi;

  /// HTTP client used to make authenticated requests to the Drive API.
  http.Client? _httpClient;

  /// Google Sign-In instance (unified for all platforms).
  final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn.instance;

  /// Current authenticated user account.
  gsi.GoogleSignInAccount? _currentUser;

  /// Subscription to authentication events.
  StreamSubscription<gsi.GoogleSignInAuthenticationEvent>?
  _authEventsSubscription;

  /// Whether the service is initialized.
  bool _isInitialized = false;

  /// Whether authentication is in progress.
  bool _isAuthenticating = false;

  /// List of configured folders.
  final List<DriveFolderInfo> _folders = [];

  /// Cache of scanned images per folder.
  final Map<String, List<DriveImageFile>> _imageCache = {};

  // --- Public Getters ---

  List<DriveFolderInfo> get folders => List.unmodifiable(_folders);
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticating => _isAuthenticating;

  // --- Initialization ---

  /// Initialize service and set up authentication event handling.
  /// Follows official google_sign_in pattern.
  Future<void> init() async {
    if (_isInitialized) {
      infoLog('GoogleDriveFolderService already initialized', tag: _tag);
      return;
    }

    infoLog('Initializing Google Drive folder service', tag: _tag);

    try {
      // Load persisted folders first (even if not authenticated)
      await _loadPersistedFolders();

      // Initialize GoogleSignIn with clientId
      await _googleSignIn.initialize(
        clientId: _clientId,
        // Note: serverClientId not needed for web-only apps
      );

      // Listen to authentication events (modern pattern)
      _authEventsSubscription = _googleSignIn.authenticationEvents.listen(
        _handleAuthenticationEvent,
      )..onError(_handleAuthenticationError);

      // Attempt lightweight (silent) authentication
      // This will trigger authenticationEvents if user is already signed in
      infoLog('Attempting lightweight authentication', tag: _tag);
      _googleSignIn.attemptLightweightAuthentication(reportAllExceptions: true);

      _isInitialized = true;
      infoLog('GoogleDriveFolderService initialized', tag: _tag);
      notifyListeners();
    } catch (e, stack) {
      errorLog(
        'Failed to initialize Google Drive service',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      _isInitialized = true; // Mark as initialized even if auth failed
      notifyListeners();
    }
  }

  /// Handle authentication events from GoogleSignIn.
  /// This is the modern way to track authentication state.
  Future<void> _handleAuthenticationEvent(
    gsi.GoogleSignInAuthenticationEvent event,
  ) async {
    infoLog('Authentication event: ${event.runtimeType}', tag: _tag);

    // Extract user from event
    final user = switch (event) {
      gsi.GoogleSignInAuthenticationEventSignIn() => event.user,
      gsi.GoogleSignInAuthenticationEventSignOut() => null,
    };

    if (user != null) {
      infoLog('User signed in: ${user.email}', tag: _tag);

      // Check if user has authorized required scopes
      final authorization = await user.authorizationClient
          .authorizationForScopes(_scopes);

      if (authorization == null) {
        // User hasn't authorized scopes yet, request them
        warningLog('User not authorized for required scopes', tag: _tag);
        await _requestScopeAuthorization(user);
      } else {
        // User is fully authorized, set up API client
        infoLog('User authorized for required scopes', tag: _tag);
        await _setupApiClient(user);
      }
    } else {
      infoLog('User signed out', tag: _tag);
      _currentUser = null;
      _driveApi = null;
      _httpClient?.close();
      _httpClient = null;
      notifyListeners();
    }
  }

  /// Handle authentication errors.
  void _handleAuthenticationError(Object error, StackTrace stackTrace) {
    errorLog(
      'Authentication error',
      tag: _tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Request scope authorization from user.
  Future<void> _requestScopeAuthorization(gsi.GoogleSignInAccount user) async {
    try {
      infoLog('Requesting scope authorization', tag: _tag);

      // Request authorization for required scopes
      // Returns void (doesn't return boolean)
      await user.authorizationClient.authorizeScopes(_scopes);

      infoLog('Scope authorization requested', tag: _tag);

      // Set up API client (assume authorization was granted if no exception)
      await _setupApiClient(user);
    } catch (e, stack) {
      errorLog(
        'Failed to request scope authorization',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Set up Drive API client with authenticated user.
  /// Uses authorizationClient.authClient() from the extension package.
  Future<void> _setupApiClient(gsi.GoogleSignInAccount user) async {
    try {
      _currentUser = user;

      // Get authorization for required scopes
      final authorization = await user.authorizationClient
          .authorizationForScopes(_scopes);

      if (authorization == null) {
        errorLog('No authorization available', tag: _tag);
        return;
      }

      // Get authenticated HTTP client from authorization
      // This uses the extension package's authClient() method
      final authClient = authorization.authClient(scopes: _scopes);
      _httpClient = authClient as http.Client;

      // Create Drive API client
      _driveApi = drive.DriveApi(_httpClient!);

      infoLog('Drive API client set up successfully', tag: _tag);
      notifyListeners();
    } catch (e, stack) {
      errorLog(
        'Failed to set up API client',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }
  }

  // --- Authentication ---

  /// Check if the platform supports programmatic authenticate() method.
  /// On web, this returns false - must use renderButton() instead.
  bool get supportsAuthenticate =>
      gsi.GoogleSignIn.instance.supportsAuthenticate();

  /// Authenticate with Google Drive using explicit sign-in.
  ///
  /// **IMPORTANT**: On web, this throws UnimplementedError.
  /// For web, use the GoogleSignInButton widget from folder_select_screen.dart
  /// which calls renderButton() to show Google's sign-in UI.
  ///
  /// Shows account picker UI on mobile/desktop platforms.
  Future<bool> authenticate() async {
    if (!supportsAuthenticate) {
      errorLog(
        'authenticate() is not supported on this platform. Use renderButton() on web.',
        tag: _tag,
      );
      return false;
    }

    if (_isAuthenticating) {
      warningLog('Authentication already in progress', tag: _tag);
      return false;
    }

    _isAuthenticating = true;
    notifyListeners();

    infoLog('Starting explicit Google Drive authentication', tag: _tag);

    try {
      // Use modern authenticate() method which shows account picker
      // This will trigger authenticationEvents automatically
      // NOTE: This only works on mobile/desktop, NOT on web
      await _googleSignIn.authenticate();

      // Wait a bit for authentication event to be processed
      await Future.delayed(const Duration(milliseconds: 500));

      final success = isAuthenticated;
      if (success) {
        infoLog('Authentication successful', tag: _tag);
      } else {
        warningLog('Authentication did not complete', tag: _tag);
      }

      return success;
    } catch (e, stack) {
      errorLog('Authentication failed', tag: _tag, error: e, stackTrace: stack);
      return false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  /// Sign out and clear credentials.
  Future<void> signOut() async {
    infoLog('Signing out from Google Drive', tag: _tag);

    try {
      // Modern sign-out method - triggers SignOut event automatically
      await _googleSignIn.signOut();
      infoLog('Signed out successfully', tag: _tag);
    } catch (e, stack) {
      errorLog('Failed to sign out', tag: _tag, error: e, stackTrace: stack);
    }

    // Event handler will clean up _currentUser, _driveApi, _httpClient
    notifyListeners();
  }

  // --- Folder Management ---

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
  /// If parentId is provided, lists folders in that folder instead.
  Future<List<DriveFolderInfo>> listDriveFolders({String? parentId}) async {
    if (_driveApi == null) {
      warningLog('Cannot list folders: not authenticated', tag: _tag);
      return [];
    }

    final location = parentId ?? 'root';
    infoLog('Listing Google Drive folders in: $location', tag: _tag);

    try {
      // Query for folders only (not in trash, in specified parent)
      final query = parentId == null
          ? "mimeType='application/vnd.google-apps.folder' and trashed=false and 'root' in parents"
          : "mimeType='application/vnd.google-apps.folder' and trashed=false and '$parentId' in parents";

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

      infoLog('Found ${folders.length} folders in $location', tag: _tag);
      return folders;
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

  /// Clear all folders (but keep authentication).
  Future<void> clearFolders() async {
    infoLog('Clearing all folders', tag: _tag);
    _folders.clear();
    _imageCache.clear();
    await _persistFolders();
    notifyListeners();
  }

  // --- Image Scanning ---

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
      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        pageSize: 1000,
        pageToken: pageToken,
        $fields:
            'nextPageToken, files(id, name, mimeType, thumbnailLink, webContentLink, size, parents)',
      );

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

  // --- Image Download ---

  /// Download image file bytes from Drive using authenticated client.
  /// Returns null if download fails.
  Future<Uint8List?> downloadImageBytes(String fileId) async {
    if (_driveApi == null || _httpClient == null) {
      warningLog('Cannot download image: not authenticated', tag: _tag);
      return null;
    }

    try {
      infoLog('Downloading image: $fileId', tag: _tag);

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
      final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());

      infoLog('Downloaded ${bytes.length} bytes for $fileId', tag: _tag);
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

  // --- Cleanup ---

  @override
  void dispose() {
    _authEventsSubscription?.cancel();
    _httpClient?.close();
    super.dispose();
  }
}
