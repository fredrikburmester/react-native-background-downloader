# Codegen Type Compatibility Fix

## Issue

The React Native Codegen was failing with the following error:

```
[Codegen] UnsupportedGenericParserError: Module NativeRNBackgroundDownloader: 
Unrecognized generic type 'Record' in NativeModule spec.
```

## Root Cause

React Native's Codegen has limited support for TypeScript generic types. Specifically, it does not recognize the `Record<K, V>` generic type utility.

## Solution

Changed the `headers` parameter type in the TurboModule spec from:
```typescript
headers?: Record<string, string>
```

to:
```typescript
headers?: Object
```

## Files Modified

1. **src/NativeRNBackgroundDownloader.ts**
   - Changed `headers` parameter from `Record<string, string>` to `Object`

2. **src/index.ts**
   - Added type cast `headers as Object` when calling the native method

3. **Android Spec Files**
   - Added `@Nullable` annotations to optional parameters:
     - `android/src/newarch/java/com/eko/NativeRNBackgroundDownloaderSpec.java`
     - `android/src/newarch/java/com/eko/RNBackgroundDownloaderModule.java`
     - `android/src/main/java/com/eko/RNBackgroundDownloaderModuleImpl.java`

## Codegen-Compatible Types

When writing TurboModule specs, use these types that Codegen understands:

### Primitives
- `string`
- `number`
- `boolean`

### Complex Types
- `Object` - for any object/dictionary
- `Array<T>` - for arrays of a specific type
- Inline object types with explicit properties:
  ```typescript
  {
    id: string;
    value: number;
  }
  ```

### Types to Avoid
- ❌ `Record<K, V>`
- ❌ `Map<K, V>`
- ❌ `Set<T>`
- ❌ Generic utility types from TypeScript

### React Native Bridge Types (Android)
On the Android/Java side, use:
- `ReadableMap` - equivalent to `Object` in TypeScript spec
- `ReadableArray` - equivalent to `Array<T>` in TypeScript spec
- `@Nullable` - for optional parameters

## Testing

After this fix, run:
```bash
npx expo prebuild --clean -p ios
npx expo run:ios
```

The Codegen should now successfully process the TurboModule spec without errors.

