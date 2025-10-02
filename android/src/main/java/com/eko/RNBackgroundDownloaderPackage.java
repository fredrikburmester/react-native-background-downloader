package com.eko;

import com.facebook.react.TurboReactPackage;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.module.model.ReactModuleInfo;
import com.facebook.react.module.model.ReactModuleInfoProvider;

import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;

public class RNBackgroundDownloaderPackage extends TurboReactPackage {

    @Nullable
    @Override
    public NativeModule getModule(String name, ReactApplicationContext reactContext) {
        if (name.equals(RNBackgroundDownloaderModuleImpl.NAME)) {
            return new RNBackgroundDownloaderModule(reactContext);
        } else {
            return null;
        }
    }

    @Override
    public ReactModuleInfoProvider getReactModuleInfoProvider() {
        return () -> {
            final Map<String, ReactModuleInfo> moduleInfos = new HashMap<>();
            
            moduleInfos.put(
                RNBackgroundDownloaderModuleImpl.NAME,
                new ReactModuleInfo(
                    RNBackgroundDownloaderModuleImpl.NAME,
                    RNBackgroundDownloaderModuleImpl.NAME,
                    false,
                    false,
                    true,
                    false,
                    true
                ));
            return moduleInfos;
        };
    }
}
