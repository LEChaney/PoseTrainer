# Cache Busting for Flutter Web

This implementation prevents browser cache issues with Flutter web apps, especially when using deferred loading. It ensures users always get the latest version on page refresh.

## How It Works

Based on the strategy described in [this Medium article](https://lukasnevosad.medium.com/our-flutter-web-strategy-for-deferred-loading-instant-updates-happy-users-45ed90a7727c):

1. **Versioned Directories**: After building, all assets are moved to a versioned subdirectory (e.g., `/1.0.0+123/`)
2. **Base Href Update**: The `<base href>` in `index.html` points to the versioned directory
3. **Cache Headers**: Root files (`index.html`, `version.json`) use `no-cache`, versioned assets use aggressive caching
4. **Auto-Increment Build Number**: GitHub Actions automatically uses the workflow run number as the build number

## Version Format

The version follows Flutter's standard format: `MAJOR.MINOR.PATCH+BUILD_NUMBER`

- `MAJOR.MINOR.PATCH`: Defined in `pubspec.yaml` (e.g., `1.0.0`)
- `BUILD_NUMBER`: Auto-incremented by GitHub Actions using `github.run_number`
- Full version example: `1.0.0+123` (where 123 is the GitHub Actions run number)

## Project Structure

```
tools/
  ├── post_build_web.sh         # Post-build script (Bash/Linux/macOS/Git Bash)
  ├── post_build_web.ps1        # Post-build script (PowerShell/Windows)
  ├── post_build_web.bat        # Post-build wrapper (Windows cmd - PowerShell)
  └── post_build_web_bash.bat   # Post-build wrapper (Windows cmd - Git Bash)
.github/
  └── workflows/
      └── deploy_firebase_hosting.yml    # Updated to run post-build script
firebase.json                             # Updated cache headers
```

## Usage

## Usage

### 1. Building Locally

For local testing, you can use any build number:

#### On Windows (Multiple Options):

**Option 1: PowerShell (Recommended - Native)**
```cmd
flutter build web --wasm --release --build-number=999
.\tools\post_build_web.bat
```

**Option 2: Git Bash (Cross-platform consistency)**
```cmd
flutter build web --wasm --release --build-number=999
.\tools\post_build_web_bash.bat
```
*Requires Git for Windows to be installed*

**Option 3: Direct PowerShell/Bash (Advanced)**
```powershell
# PowerShell
flutter build web --wasm --release --build-number=999
powershell -ExecutionPolicy Bypass -File .\tools\post_build_web.ps1

# Or with Git Bash
flutter build web --wasm --release --build-number=999
& "C:\Program Files\Git\bin\bash.exe" tools/post_build_web.sh
```

#### On Linux/macOS:
```bash
# Build Flutter web with a test build number
flutter build web --wasm --release --build-number=999

# Run post-build processing
bash tools/post_build_web.sh
```

### 2. GitHub Actions Deployment

The workflow automatically increments the build number using `github.run_number`. Just push to `main`:

```bash
git add .
git commit -m "Deploy new version"
git push origin main
```

The deployed version will be something like `1.0.0+45` (where 45 is the workflow run number).

### 3. Which Script Should I Use on Windows?

| Script | Pros | Cons | When to Use |
|--------|------|------|-------------|
| **post_build_web.bat** | ✅ Native Windows<br>✅ No dependencies<br>✅ Works everywhere | ⚠️ PowerShell-only | Default choice for Windows |
| **post_build_web_bash.bat** | ✅ Uses same .sh as Linux/macOS<br>✅ Exact same behavior | ❌ Requires Git for Windows | Cross-platform consistency |
| **post_build_web.sh** | ✅ True cross-platform | ❌ Need to call bash manually | CI/CD or when Git Bash is in PATH |
| **post_build_web.ps1** | ✅ Native PowerShell | ❌ Execution policy issues | When you need PowerShell directly |

**Recommendation:** Use `post_build_web.bat` for simplicity, or `post_build_web_bash.bat` if you want the exact same script as Linux/macOS.

## Cache Strategy

### Root Files (index.html, version.json)
- `Cache-Control: no-cache, no-store, must-revalidate`
- Always fetched fresh to ensure users get the latest version pointer

### Versioned Assets (/1.0.0+1/**)
- `Cache-Control: public, max-age=31536000, immutable`
- Aggressively cached since URLs are unique per version

## Benefits

✅ **Eliminates DeferredLoadException** - No more crashes from mismatched chunk versions  
✅ **Instant Updates** - Users get the latest version on page refresh  
✅ **CDN Friendly** - Works perfectly with CDNs since asset URLs are unique  
✅ **Simple Implementation** - Uses standard HTML `<base href>` tag  
✅ **Cross-Platform** - Works on Windows, Linux, and macOS  

## Troubleshooting

### Local Testing

To test locally with Firebase hosting emulator:

#### Windows (PowerShell):
```powershell
# Build and process
flutter build web --wasm --release
.\tools\post_build_web.bat

# Serve with Firebase emulator (use cmd to avoid execution policy issues)
cmd /c firebase emulators:start --only hosting --project demo-test
```

#### Linux/macOS:
```bash
# Build and process
flutter build web --wasm --release
bash tools/post_build_web.sh

# Serve with Firebase emulator
firebase emulators:start --only hosting --project demo-test
```

**Open in browser:** http://localhost:5000

#### Verify Cache Busting is Working

1. **Check version.json at root:**
   ```bash
   curl http://localhost:5000/version.json
   ```
   Should return: `{"version":"1.0.0+1",...}`

2. **Check index.html base href:**
   ```bash
   curl http://localhost:5000/ | grep "base href"
   ```
   Should show: `<base href="/1.0.0/">`

3. **Check asset URLs in browser DevTools:**
   - Open DevTools → Network tab
   - Refresh the page
   - All JS/assets should load from `/1.0.0/...` path
   - Example: `/1.0.0/flutter.js`, `/1.0.0/main.dart.js`

4. **Verify cache headers:**
   ```bash
   # Root files should have no-cache
   curl -I http://localhost:5000/index.html | grep "Cache-Control"
   # Should show: Cache-Control: no-cache, no-store, must-revalidate
   
   # Versioned assets should have max-age
   curl -I http://localhost:5000/1.0.0/flutter.js | grep "Cache-Control"
   # Should show: Cache-Control: public, max-age=31536000, immutable
   ```

5. **Test a version update:**
   - Change version in `pubspec.yaml` (e.g., to `1.0.1+2`)
   - Rebuild: `flutter build web --wasm --release`
   - Reprocess: `.\tools\post_build_web.bat`
   - Restart emulator
   - Check that assets now load from `/1.0.1+2/` path

### Version Not Updating

1. Clear browser cache completely (Ctrl+Shift+Delete)
2. Check that `version.json` in the root shows the new version
3. Verify `<base href>` in `index.html` points to the versioned directory
4. Check Firebase hosting cache headers are correctly configured

### PowerShell Execution Policy (Windows)

If you get an execution policy error when running the PowerShell script, you have two options:

**Option 1: Bypass for this execution only (recommended)**
```powershell
powershell -ExecutionPolicy Bypass -File .\tools\post_build_web.ps1
```

**Option 2: Change policy permanently (requires admin)**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Option 3: Use Git Bash instead**
```bash
bash tools/post_build_web.sh
```

## References

- [Original Medium Article](https://lukasnevosad.medium.com/our-flutter-web-strategy-for-deferred-loading-instant-updates-happy-users-45ed90a7727c)
- [Flutter GitHub Issue #127459](https://github.com/flutter/flutter/issues/127459)
