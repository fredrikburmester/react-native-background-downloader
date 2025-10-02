# React Native Background Downloader - New Architecture Migration

## Summary

This package has been fully migrated to React Native's New Architecture (TurboModules/Bridgeless). **Old Architecture support has been removed.**

## Changes Made

### 1. TurboModule Specification

**File:** `src/NativeRNBackgroundDownloader.ts`

Created a new TurboModule spec that defines the interface for the native module:
- `downloadFile()` - Start a new download with all parameters
- `cancelDownload()` - Cancel an ongoing download
- `pauseDownload()` - Pause a download (iOS only)
- `resumeDownload()` - Resume a paused download (iOS only)
- `checkForExistingDownloads()` - Query existing downloads
- `completeHandler()` - Complete background session (iOS only)
- `addListener()` / `removeListeners()` - Event system support

### 2. JavaScript Layer

**Files:** `src/index.ts`, `src/DownloadTask.ts`

Completely rewritten to work with the New Architecture:
- Uses `NativeEventEmitter` properly with TurboModule
- Simplified event handling - removed complex bridge/bridgeless detection
- Clean event subscription pattern
- Type-safe implementation with proper TypeScript types

### 3. iOS Implementation

**File:** `ios/RNBackgroundDownloader.mm`

Rewritten for New Architecture:
- Implements TurboModule protocol when `RCT_NEW_ARCH_ENABLED` is defined
- Uses `NSURLSession` with background configuration for reliable downloads
- Proper event emission using `sendEventWithName:body:`
- Maintains listener count for proper event delivery
- Background download support with completion handlers
- Delegate methods for progress tracking:
  - `didFinishDownloadingToURL` - completion
  - `didWriteData` - progress updates
  - `didCompleteWithError` - error handling

### 4. Android Implementation

**Files:** 
- `android/src/main/java/com/eko/RNBackgroundDownloaderModuleImpl.java`
- `android/src/newarch/java/com/eko/NativeRNBackgroundDownloaderSpec.java`
- `android/src/newarch/java/com/eko/RNBackgroundDownloaderModule.java`

Updated for New Architecture:
- Spec class defines the TurboModule interface
- Module class wraps the implementation
- Uses Android's `DownloadManager` for background downloads
- Event emission via `DeviceEventManagerModule.RCTDeviceEventEmitter`
- Polling mechanism for download progress
- BroadcastReceiver for download completion

### 5. Package Configuration

**File:** `package.json`

Updated `codegenConfig`:
```json
{
  "codegenConfig": {
    "name": "RNBackgroundDownloaderSpec",
    "type": "modules",
    "jsSrcsDir": "src",
    "android": {
      "javaPackageName": "com.eko"
    },
    "ios": {}
  }
}
```

### 6. iOS Podspec

**File:** `react-native-background-downloader.podspec`

Simplified for New Architecture:
- Uses `install_modules_dependencies(s)` for automatic dependency management
- C++20 standard
- Module support enabled

### 7. Removed Files

Old Architecture support completely removed:
- `android/src/oldarch/java/com/eko/RNBackgroundDownloaderModule.java` - DELETED
- `android/src/newarch/java/com/eko/RNBackgroundDownloaderTurboPackage.java` - DELETED (redundant)

Updated main package to use TurboReactPackage directly.

## Event System

The module emits four events:

1. **downloadBegin** - When download starts
   ```typescript
   { id: string, expectedBytes: number, headers: Record<string, string> }
   ```

2. **downloadProgress** - During download (throttled)
   ```typescript
   { id: string, bytesDownloaded: number, bytesTotal: number }
   ```

3. **downloadComplete** - When download finishes successfully
   ```typescript
   { id: string, location: string, bytesDownloaded: number, bytesTotal: number, headers: Record<string, string> }
   ```

4. **downloadFailed** - When download fails
   ```typescript
   { id: string, error: string, errorCode: number }
   ```

## Usage Example

```typescript
import BackgroundDownloader from '@kesha-antonov/react-native-background-downloader';

const task = BackgroundDownloader.download({
  id: 'file123',
  url: 'https://example.com/file.pdf',
  destination: `${BackgroundDownloader.directories.documents}/file.pdf`
});

task
  .begin((expectedBytes) => {
    console.log(`Download started, expecting ${expectedBytes} bytes`);
  })
  .progress((percent) => {
    console.log(`Downloaded: ${percent * 100}%`);
  })
  .done((result) => {
    console.log('Download complete!', result.location);
  })
  .error((error) => {
    console.log('Download failed', error);
  });
```

## Requirements

- **React Native:** >= 0.73 (New Architecture enabled)
- **iOS:** >= 13.4
- **Android:** API 21+ (Android 5.0)

## Building

### iOS

```bash
cd ios && pod install && cd ..
npx react-native run-ios
```

### Android

```bash
npx react-native run-android
```

The Codegen will automatically generate native bridge code during build.

## Notes

### iOS Background Downloads

- Uses `NSURLSession` with background configuration
- Downloads continue even when app is suspended or terminated
- Requires `handleEventsForBackgroundURLSession` in AppDelegate
- System will wake app to deliver events

### Android Background Downloads

- Uses system `DownloadManager`
- Pause/Resume not supported (Android DownloadManager limitation)
- Downloads persist across app restarts
- Requires storage permissions for Android < 10

### Unknown Content Length

Both platforms handle downloads where `Content-Length` is not provided by the server (e.g., streaming downloads):
- `bytesTotal` will be `0` or `-1`
- Progress percentage will be `0`
- Completion is still detected properly
- Progress events still fire based on bytes threshold

## Migration from Old Architecture

If migrating from an older version that supported the Old Architecture:

1. **Enable New Architecture** in your app:
   - iOS: `RCT_NEW_ARCH_ENABLED=1` in Podfile
   - Android: `newArchEnabled=true` in gradle.properties

2. **No API changes required** - The JavaScript API remains the same

3. **Build and test** - Rebuild native code to generate TurboModule bindings

## Troubleshooting

### Events not firing

Make sure to call `addListener` before starting downloads:
```typescript
// This happens automatically when importing the module
import BackgroundDownloader from '@kesha-antonov/react-native-background-downloader';
```

### iOS builds fail

1. Clean build folder: `rm -rf ios/build`
2. Reinstall pods: `cd ios && pod deintegrate && pod install`
3. Run Codegen: Build the app, Codegen runs automatically

### Android builds fail

1. Clean: `cd android && ./gradlew clean`
2. Run Codegen: Build the app, Codegen runs automatically
3. Check that `newArchEnabled=true` in `android/gradle.properties`

## License

Apache-2.0

