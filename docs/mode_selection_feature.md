# Mode Selection Feature

## Overview
Added a new start screen that allows users to choose between two practice modes:
1. **e621 Search Mode** - The existing tag-based search functionality
2. **Folder Practice Mode** - Sample images from local folder collections (new)

## Implementation Details

### New Files Created

#### 1. `lib/screens/start_screen.dart`
- Entry point screen for mode selection
- Displays two large, tappable cards for each mode
- Includes History and Debug Settings buttons in the AppBar for quick access
- Clean, centered layout that works well on mobile and desktop

Key features:
- Material 3 design with elevated cards
- Clear iconography (search icon for e621, folder icon for local)
- Descriptive text explaining each mode
- Consistent navigation to existing screens (History, Debug Settings)

#### 2. `lib/screens/folder_select_screen.dart`
- Screen for selecting folders to practice from
- Multi-select folders with visual feedback
- Preview thumbnails (2×2 grid per folder)
- Shows image counts and folder stats

Key features:
- **Placeholder Data**: Currently uses 6 fake folders with placeholder names and Lorem Picsum preview images for testing layout
- **Multi-selection**: Tap folders to select/deselect, with visual indicators (border, checkmark, overlay)
- **Responsive Grid**: Uses `SliverGridDelegateWithMaxCrossAxisExtent` for adaptive layout
- **Stats Display**: Shows selected folder count and total available images
- **AppBar Actions**: History and Debug Settings buttons for consistency
- **Bottom Control Bar**: Appears when folders are selected, ready for session configuration

Future implementation (deferred):
- Platform file picker integration to add real folders
- Recursive folder scanning for image discovery
- Uniform random sampling across all selected folders and subfolders
- Persistence of folder list to local storage
- Folder management UI (add/remove)

### Modified Files

#### `lib/main.dart`
Changed the app's home screen from `SearchScreen` to `StartScreen`:
```dart
// Before:
home: const DebugOverlay(child: SearchScreen()),

// After:
home: const DebugOverlay(child: StartScreen()),
```

## User Flow

### New Flow
1. **Start Screen** → User selects mode
   - Tap "e621 Search" → Navigate to existing `SearchScreen`
   - Tap "Folder Practice" → Navigate to new `FolderSelectScreen`
2. **Folder Select Screen** (new)
   - User selects one or more folders
   - Configures session settings (future: count, time, unlimited)
   - Taps "Start Session" → Will navigate to session runner (not yet implemented)

### Existing Flow Preserved
- All existing functionality from `SearchScreen` remains unchanged
- History, Debug Settings, and Session Runner screens work as before
- Practice and Review screens are unaffected

## Design Decisions

### Placeholder Folders
Using fake data allows us to:
- Test and refine the UI layout without platform-specific file picker code
- Visualize the folder selection experience
- Iterate on design before committing to folder management architecture

The placeholder folders include:
- "Anatomy Studies" (342 images)
- "Figure Drawing" (157 images)
- "Animals" (89 images)
- "Gestures" (423 images)
- "Hands & Feet" (234 images)
- "Portrait Reference" (198 images)

### Consistent Navigation
Both new screens include History and Debug Settings buttons in the AppBar, matching the pattern from `SearchScreen`. This ensures users can always access these utilities regardless of which mode they're using.

### Future: Folder Management
The next steps for folder functionality include:
1. **Add Folders**: Use `file_picker` or platform APIs to let users select directories
2. **Scan for Images**: Recursively find all image files (jpg, png, etc.) in selected folders
3. **Uniform Sampling**: Implement random selection that treats all images equally regardless of folder structure
4. **Persistence**: Save folder paths to local storage (Hive or SharedPreferences)
5. **Session Integration**: Connect folder image source to existing `SessionRunnerScreen`
6. **Folder Stats**: Display last used date, image count updates, folder health

## Testing

### Visual Testing
- Start screen displays correctly with two mode cards
- Folder select screen shows grid of placeholder folders
- Selection state (border, checkmark, overlay) works correctly
- Bottom control bar appears/disappears based on selection
- Responsive layout adapts to different screen sizes

### Navigation Testing
- Start screen → e621 Search → works (existing flow)
- Start screen → Folder Select → displays correctly
- History and Debug Settings accessible from both new screens

### Deferred Testing
- Actual folder scanning (pending platform integration)
- Session start with folder-based images (pending implementation)
- Folder persistence (pending storage layer)

## Code Quality

### Readability
- Clear comments explaining purpose and scope
- Named helper widgets extracted for clarity
- Descriptive variable and class names
- Section headers to organize code

### Maintainability
- Loose coupling: new screens don't affect existing functionality
- Clear separation: mode selection → source selection → session
- Placeholder pattern allows incremental development
- Future TODOs clearly marked in comments

### Consistency
- Follows project's Copilot instructions (descriptive names, Material 3, relative imports)
- Matches existing screen patterns (AppBar actions, navigation)
- Uses established logging patterns (`infoLog` with tags)
