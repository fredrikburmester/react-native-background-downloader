package com.eko;

import androidx.annotation.NonNull;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReadableMap;

import javax.annotation.Nullable;
import java.util.Map;

public class RNBackgroundDownloaderModule extends NativeRNBackgroundDownloaderSpec {

    private final RNBackgroundDownloaderModuleImpl mModuleImpl;

    public RNBackgroundDownloaderModule(ReactApplicationContext reactContext) {
        super(reactContext);
        mModuleImpl = new RNBackgroundDownloaderModuleImpl(reactContext);
    }

    @Override
    @NonNull
    public String getName() {
        return RNBackgroundDownloaderModuleImpl.NAME;
    }

    @Override
    public void downloadFile(
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
    ) {
        mModuleImpl.downloadFile(
            url,
            destinationPath,
            id,
            headers,
            metadata,
            progressInterval,
            progressMinBytes,
            isAllowedOverRoaming,
            isAllowedOverMetered,
            isNotificationVisible,
            notificationTitle,
            promise
        );
    }

    @Override
    public void cancelDownload(String id) {
        mModuleImpl.cancelDownload(id);
    }

    @Override
    public void pauseDownload(String id) {
        mModuleImpl.pauseDownload(id);
    }

    @Override
    public void resumeDownload(String id) {
        mModuleImpl.resumeDownload(id);
    }

    @Override
    public void checkForExistingDownloads(Promise promise) {
        mModuleImpl.checkForExistingDownloads(promise);
    }

    @Override
    public void completeHandler(String jobId, Promise promise) {
        mModuleImpl.completeHandler(jobId, promise);
    }

    @Override
    public void addListener(String eventName) {
        mModuleImpl.addListener(eventName);
    }

    @Override
    public void removeListeners(double count) {
        mModuleImpl.removeListeners((int) count);
    }

    @Override
    @Nullable
    public Map<String, Object> getConstants() {
        return mModuleImpl.getConstants();
    }

    @Override
    public void initialize() {
        super.initialize();
        mModuleImpl.initialize();
    }

    @Override
    public void invalidate() {
        mModuleImpl.invalidate();
        super.invalidate();
    }
}
