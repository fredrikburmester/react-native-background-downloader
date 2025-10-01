#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
typedef void (^CompletionHandler)(void);

@interface RNBackgroundDownloader : RCTEventEmitter <RCTBridgeModule, NSURLSessionDelegate, NSURLSessionDownloadDelegate>

+ (void)setCompletionHandlerWithIdentifier:(NSString *)identifier completionHandler:(CompletionHandler)completionHandler;
- (void)completeHandler:(NSString *)jobId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject;

@end

