# Troubleshooting Guide

## Error: TurboModuleRegistry.getEnforcing: 'RNBackgroundDownloader' could not be found

This error occurs when the native module isn't properly registered in the app. Here's how to fix it:

### Solution 1: Clean and Rebuild (Most Common)

The module needs to be rebuilt with Codegen artifacts. In your app directory:

#### iOS
```bash
# Clean everything
cd ios
rm -rf build Pods Podfile.lock
cd ..

# Reinstall and rebuild
npx expo prebuild --clean -p ios
npx expo run:ios
```

#### Android
```bash
# Clean everything
cd android
./gradlew clean
cd ..

# Reinstall and rebuild
npx expo prebuild --clean -p android
npx expo run:android
```

### Solution 2: Verify Installation

Make sure the package is properly installed in your app:

```bash
# In your app directory
npm ls @kesha-antonov/react-native-background-downloader

# Should show it's installed
# If not, reinstall:
npm install @kesha-antonov/react-native-background-downloader
```

### Solution 3: Check New Architecture is Enabled

This package REQUIRES New Architecture to be enabled.

#### iOS
Check `ios/Podfile`:
```ruby
ENV['RCT_NEW_ARCH_ENABLED'] = '1'
```

#### Android  
Check `android/gradle.properties`:
```properties
newArchEnabled=true
```

### Solution 4: Verify Codegen Config

The package's `package.json` should have:
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

### Solution 5: Check Autolinking

In your app, check `node_modules/@kesha-antonov/react-native-background-downloader/react-native.config.js` exists and is valid.

If using Expo, ensure you're using a Development Build (not Expo Go):
```bash
# Create a development build
eas build --profile development --platform ios
```

### Solution 6: Manual Linking (Last Resort)

If autolinking fails, you can manually add the module:

#### iOS Manual Steps
1. Open your app's `.xcworkspace` in Xcode
2. Check if `RNBackgroundDownloader` pod is installed: `Pods` → `Development Pods` → should see `react-native-background-downloader`
3. If not, run `pod install` in the `ios` folder

#### Android Manual Steps
1. Check `android/settings.gradle` includes the module (should be automatic with autolinking)
2. Check `android/app/build.gradle` has the dependency (should be automatic)

### Solution 7: Check for Build Errors

Look for any build warnings or errors during `pod install` or when building:

```bash
# iOS - look for any warnings about Codegen
cd ios && pod install --verbose

# Android - look for any build issues
cd android && ./gradlew assembleDebug --info
```

### Common Issues

#### "Codegen artifacts not found"
Run prebuild again to generate them:
```bash
npx expo prebuild --clean
```

#### "Module not found in bridge"
Make sure you're NOT using Expo Go - you MUST use a Development Build or bare React Native.

#### "Headers not found"
The Codegen headers might not have been generated. Clean and rebuild:
```bash
# iOS
cd ios
rm -rf build
xcodebuild clean
pod install
cd ..
npx expo run:ios

# Or use Xcode: Product → Clean Build Folder
```

### Debugging Steps

1. **Check module is found by Codegen:**
   ```bash
   cd ios
   pod install 2>&1 | grep -i "background"
   # Should see: [Codegen] Found @kesha-antonov/react-native-background-downloader
   ```

2. **Check generated files exist (iOS):**
   ```bash
   # After pod install, these should exist:
   ls ios/build/generated/ios/
   # Should contain RNBackgroundDownloaderSpec files
   ```

3. **Check generated files exist (Android):**
   ```bash
   # After gradle build:
   ls android/build/generated/source/codegen/
   # Should contain generated Java files
   ```

4. **Verify the module exports correctly:**
   The native module should be registered with the name `RNBackgroundDownloader`

### Still Not Working?

If none of the above works:

1. Create a fresh project and test:
   ```bash
   npx create-expo-app test-app
   cd test-app
   npm install @kesha-antonov/react-native-background-downloader
   npx expo prebuild
   npx expo run:ios
   ```

2. Check React Native version compatibility:
   - Requires RN >= 0.73 with New Architecture enabled
   - Requires Expo SDK >= 50 if using Expo

3. Report an issue with:
   - Your RN/Expo version
   - Full build logs
   - Whether you're using Expo or bare RN
   - iOS or Android

