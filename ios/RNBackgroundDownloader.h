#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
// New Architecture support temporarily disabled
// #ifdef RCT_NEW_ARCH_ENABLED
// #if __has_include("RNBackgroundDownloaderSpec.h")
// #import "RNBackgroundDownloaderSpec.h"
// #elif __has_include(<RNBackgroundDownloaderSpec/RNBackgroundDownloaderSpec.h>)
// #import <RNBackgroundDownloaderSpec/RNBackgroundDownloaderSpec.h>
// #endif
// #endif

typedef void (^CompletionHandler)();

@interface RNBackgroundDownloader : RCTEventEmitter <RCTBridgeModule, NSURLSessionDelegate, NSURLSessionDownloadDelegate>

+ (void)setCompletionHandlerWithIdentifier:(NSString *)identifier completionHandler:(CompletionHandler)completionHandler;
- (void)completeHandler:(NSString *)jobId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject;

@end

// New Architecture interface temporarily disabled
// #ifdef RCT_NEW_ARCH_ENABLED
// @interface RNBackgroundDownloader () <NativeRNBackgroundDownloaderSpec>
// 
// @end
// #endif
