# PoseTrainer Debug Logging System

This comprehensive logging system provides multiple ways to get debug information from your Flutter app, especially useful for iOS development on Windows where traditional debugging tools are expensive or limited.

## Features

### 1. In-App Debug Overlay 🐛
- **Access**: Use a 3-finger tap anywhere in the app to toggle
- **Features**: 
  - Real-time log display with color-coded levels
  - Filterable by log level (Debug, Info, Warning, Error)
  - Auto-scroll to latest logs
  - Copy logs to clipboard
  - Share logs via platform share sheet

### 2. Network Logging 📡
- **Setup**: Run `tools/start_log_receiver.bat` on your Windows PC
- **Features**:
  - Sends logs over WiFi to your development PC
  - Real-time display with color coding
  - Works from any device on the same network
  - No USB connection required

### 3. File Logging 📁
- **Mobile/Desktop**: Saves logs to device storage
- **Features**:
  - Persistent log files
  - Share via iOS Share Sheet (email, AirDrop, etc.)
  - View file size and location
  - Automatic file management

## Quick Setup

### For iOS Development on Windows

1. **Enable Debug Overlay**:
   - Use 3-finger tap in the app to show/hide overlay
   - Or tap the bug icon in the app bar (debug builds only)

2. **Setup Network Logging** (Recommended):
   ```bash
   # On your Windows PC:
   cd tools
   python log_receiver.py
   
   # Note the IP address shown (e.g., 192.168.1.100)
   # In the app: Settings > Debug Settings
   # Enter: http://192.168.1.100:8080/logs
   # Enable "Network Logging"
   ```

3. **Use File Logging** (For sharing):
   - Enable "File Logging" in Debug Settings
   - Use "Share Logs" button to email/AirDrop logs to yourself

## Usage Examples

### Adding Logs to Your Code

```dart
import '../services/debug_logger.dart';

// Simple logging
debugLog('Detailed debug information');
infoLog('Something interesting happened');
warningLog('This might be a problem');
errorLog('Something went wrong!');

// With tags and context
infoLog('User tapped paint button', tag: 'BrushEngine');
errorLog('Failed to load image', tag: 'ImageLoader', error: exception);

// In methods
void startDrawing() {
  infoLog('Starting new drawing session', tag: 'DrawingSession');
  // ... your code
}
```

### Configuring Log Levels

```dart
// Only show warnings and errors
DebugLogger.instance.setMinLevel(LogLevel.warning);

// Show everything (default)
DebugLogger.instance.setMinLevel(LogLevel.debug);
```

## Free Flutter Debugging Alternatives

### 1. Flutter Inspector (VS Code/Android Studio)
- **Access**: View > Command Palette > "Flutter: Open Widget Inspector"
- **Features**: Widget tree, properties, performance overlay
- **Limitation**: Requires USB connection to device

### 2. Flutter DevTools
- **Access**: `flutter run` then follow the DevTools URL
- **Features**: Full debugging suite including network, performance, logging
- **Limitation**: Requires USB connection

### 3. VS Code Flutter Extension
- **Features**: 
  - Breakpoint debugging
  - Hot reload
  - Device logs in output panel
- **Access**: Install "Flutter" extension in VS Code

### 4. Built-in Flutter Tools
```bash
# View device logs
flutter logs

# Run with verbose logging
flutter run -v

# Profile mode for performance
flutter run --profile

# Debug info
flutter doctor -v
```

### 5. Browser DevTools (Web)
- **Access**: F12 in browser when running `flutter run -d chrome`
- **Features**: Console logs, network tab, elements inspector

### 6. Physical Device Logging
```bash
# iOS (requires Xcode command line tools)
# View iOS simulator logs
xcrun simctl spawn booted log stream

# Android
adb logcat | grep flutter
```

## Network Logging Setup Details

### Windows PC Setup
```bash
# Method 1: Use provided script
cd tools
start_log_receiver.bat

# Method 2: Manual Python
python log_receiver.py --port 8080 --host 0.0.0.0
```

### Finding Your PC's IP Address
```bash
# Windows Command Prompt
ipconfig

# Look for "IPv4 Address" under your WiFi adapter
# Usually something like 192.168.1.xxx or 10.0.0.xxx
```

### App Configuration
1. Open Debug Settings (bug icon in app bar)
2. Enable "Network Logging"
3. Enter URL: `http://YOUR_PC_IP:8080/logs`
4. Save settings

## Troubleshooting

### Network Logging Not Working
- Ensure both devices are on the same WiFi network
- Check Windows Firewall (may block incoming connections)
- Verify the IP address is correct
- Try a different port if 8080 is blocked

### iOS Share Sheet Not Working
- Ensure "File Logging" is enabled in settings
- Try the "Copy Logs" button as fallback
- Check iOS permissions for file access

### Overlay Not Appearing
- Try 3-finger tap in different areas of the screen
- Check if debug mode is enabled (`kDebugMode`)
- Use the bug icon in the app bar instead

### Performance Impact
- The logging system is designed to be lightweight
- Disable verbose logging in production builds
- Network logging has minimal impact (async with timeouts)

## Advanced Configuration

### Custom Log Levels
```dart
// Set different levels for different components
if (kDebugMode) {
  DebugLogger.instance.setMinLevel(LogLevel.debug);
} else {
  DebugLogger.instance.setMinLevel(LogLevel.warning);
}
```

### Network Endpoint Customization
```dart
// Configure multiple endpoints
DebugLogger.instance.configureNetworkLogging(
  url: 'http://192.168.1.100:8080/logs',
  enabled: true,
);
```

## Cost Comparison

| Solution | Cost | Platform | Features |
|----------|------|----------|----------|
| **This System** | Free | All | In-app overlay, network logs, file sharing |
| Inspect App | $79/year | iOS | Professional remote debugging |
| Flutter DevTools | Free | All | Full debugging (requires USB) |
| Proxyman | $49/year | macOS | Network debugging |
| Charles Proxy | $50 | All | Network debugging |

## Files Created

- `lib/services/debug_logger.dart` - Core logging service
- `lib/widgets/debug_overlay.dart` - In-app debug panel
- `lib/screens/debug_settings_screen.dart` - Settings UI
- `tools/log_receiver.py` - PC log server
- `tools/start_log_receiver.bat` - Windows launcher

This system gives you professional-grade debugging capabilities without the cost of commercial tools, particularly valuable for iOS development on Windows machines.