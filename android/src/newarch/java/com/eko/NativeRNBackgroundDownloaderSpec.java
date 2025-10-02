package com.eko;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;

public abstract class NativeRNBackgroundDownloaderSpec extends com.facebook.react.bridge.ReactContextBaseJavaModule {

    public NativeRNBackgroundDownloaderSpec(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @NonNull
    @Override
    public abstract String getName();

    @ReactMethod
    public abstract void downloadFile(
        String url,
        String destinationPath,
        String id,
        @Nullable ReadableMap headers,
        @Nullable String metadata,
        double progressInterval,
        double progressMinBytes,
        boolean isAllowedOverRoaming,
        boolean isAllowedOverMetered,
        boolean isNotificationVisible,
        @Nullable String notificationTitle,
        Promise promise
    );

    @ReactMethod
    public abstract void cancelDownload(String id);

    @ReactMethod
    public abstract void pauseDownload(String id);

    @ReactMethod
    public abstract void resumeDownload(String id);

    @ReactMethod
    public abstract void checkForExistingDownloads(Promise promise);

    @ReactMethod
    public abstract void completeHandler(String jobId, Promise promise);

    @ReactMethod
    public abstract void addListener(String eventName);

    @ReactMethod
    public abstract void removeListeners(double count);
}
