#import "RNBackgroundDownloader.h"
#import "RNBGDTaskConfig.h"
#import <MMKV/MMKV.h>
#import <React/RCTBridge+Private.h>
#import <React/RCTEventDispatcher.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import "RNBackgroundDownloaderSpec.h"
#import <ReactCommon/RCTTurboModule.h>
#endif

#define ID_TO_CONFIG_MAP_KEY @"com.eko.bgdownloadidmap"
#define PROGRESS_INTERVAL_KEY @"progressInterval"
#define PROGRESS_MIN_BYTES_KEY @"progressMinBytes"

#ifdef DEBUG
#define DLog( s, ... ) NSLog( @"<%p %@:(%d)> %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define DLog( s, ... )
#endif

static CompletionHandler storedCompletionHandler;

@interface RNBackgroundDownloader () <NSURLSessionDownloadDelegate>
@end

@implementation RNBackgroundDownloader {
    MMKV *mmkv;
    NSURLSession *urlSession;
    NSURLSessionConfiguration *sessionConfig;
    NSNumber *sharedLock;
    NSMutableDictionary<NSNumber *, RNBGDTaskConfig *> *taskToConfigMap;
    NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *idToTaskMap;
    NSMutableDictionary<NSString *, NSData *> *idToResumeDataMap;
    NSMutableDictionary<NSString *, NSNumber *> *idToPercentMap;
    NSMutableDictionary<NSString *, NSNumber *> *idToLastBytesMap;
    NSMutableDictionary<NSString *, NSDictionary *> *progressReports;
    float progressInterval;
    int64_t progressMinBytes;
    NSDate *lastProgressReportedAt;
    BOOL isJavascriptLoaded;
    NSInteger listenerCount;
}

RCT_EXPORT_MODULE(RNBackgroundDownloader);

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeRNBackgroundDownloaderSpecJSI>(params);
}
#endif

// Explicitly declare this is a TurboModule
- (BOOL)isTurboModule {
    return YES;
}

- (void)startObserving
{
    NSLog(@"[RNBackgroundDownloader] startObserving");
}

- (void)stopObserving
{
    NSLog(@"[RNBackgroundDownloader] stopObserving");
}

RCT_EXPORT_METHOD(addListener:(NSString *)eventName)
{
    listenerCount++;
    NSLog(@"[RNBackgroundDownloader] addListener: %@ (total: %ld)", eventName, (long)listenerCount);
}

RCT_EXPORT_METHOD(removeListeners:(double)count)
{
    listenerCount -= (NSInteger)count;
    if (listenerCount < 0) listenerCount = 0;
    NSLog(@"[RNBackgroundDownloader] removeListeners: %f (remaining: %ld)", count, (long)listenerCount);
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create("com.eko.backgrounddownloader", DISPATCH_QUEUE_SERIAL);
}

- (NSArray<NSString *> *)supportedEvents {
    return @[
        @"downloadBegin",
        @"downloadProgress",
        @"downloadComplete",
        @"downloadFailed"
    ];
}

- (void)sendEventToJS:(NSString *)eventName body:(id)body {
    NSLog(@"[RNBackgroundDownloader] Sending event: %@", eventName);
    
    if (listenerCount > 0) {
        [self sendEventWithName:eventName body:body];
    }
}

- (NSDictionary *)constantsToExport {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return @{
        @"documents": [paths firstObject],
        @"TaskRunning": @(NSURLSessionTaskStateRunning),
        @"TaskSuspended": @(NSURLSessionTaskStateSuspended),
        @"TaskCanceling": @(NSURLSessionTaskStateCanceling),
        @"TaskCompleted": @(NSURLSessionTaskStateCompleted)
    };
}

- (id)init {
    DLog(@"[RNBackgroundDownloader] init");
    self = [super init];
    if (self) {
        [MMKV initializeMMKV:nil];
        mmkv = [MMKV mmkvWithID:@"RNBackgroundDownloader"];

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        NSString *sessionIdentifier = [bundleIdentifier stringByAppendingString:@".backgrounddownloadtask"];
        sessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionIdentifier];
        sessionConfig.HTTPMaximumConnectionsPerHost = 4;
        sessionConfig.timeoutIntervalForRequest = 60 * 60;
        sessionConfig.timeoutIntervalForResource = 60 * 60 * 24;
        sessionConfig.discretionary = NO;
        sessionConfig.sessionSendsLaunchEvents = YES;
        if (@available(iOS 9.0, *)) {
            sessionConfig.shouldUseExtendedBackgroundIdleMode = YES;
        }
        if (@available(iOS 13.0, *)) {
            sessionConfig.allowsExpensiveNetworkAccess = YES;
        }

        sharedLock = [NSNumber numberWithInt:1];

        NSData *taskToConfigMapData = [mmkv getDataForKey:ID_TO_CONFIG_MAP_KEY];
        NSMutableDictionary *taskToConfigMapDataDefault = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *taskToConfigMapDataDecoded = taskToConfigMapData != nil ? [self deserialize:taskToConfigMapData] : nil;
        taskToConfigMap = taskToConfigMapDataDecoded != nil ? taskToConfigMapDataDecoded : taskToConfigMapDataDefault;
        idToTaskMap = [[NSMutableDictionary alloc] init];
        idToResumeDataMap = [[NSMutableDictionary alloc] init];
        idToPercentMap = [[NSMutableDictionary alloc] init];
        idToLastBytesMap = [[NSMutableDictionary alloc] init];

        progressReports = [[NSMutableDictionary alloc] init];
        float progressIntervalScope = [mmkv getFloatForKey:PROGRESS_INTERVAL_KEY];
        progressInterval = isnan(progressIntervalScope) ? 1.0 : progressIntervalScope;
        int64_t progressMinBytesScope = [mmkv getInt64ForKey:PROGRESS_MIN_BYTES_KEY];
        progressMinBytes = progressMinBytesScope > 0 ? progressMinBytesScope : 1024 * 1024;
        lastProgressReportedAt = [[NSDate alloc] init];

        listenerCount = 0;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleBridgeAppEnterForeground:)
                                              name:UIApplicationWillEnterForegroundNotification
                                              object:nil];
    }

    return self;
}

- (void)dealloc {
    DLog(@"[RNBackgroundDownloader] dealloc");
    [self unregisterSession];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleBridgeAppEnterForeground:(NSNotification *)note {
    DLog(@"[RNBackgroundDownloader] handleBridgeAppEnterForeground");
    [self resumeTasks];
}

- (void)lazyRegisterSession {
    DLog(@"[RNBackgroundDownloader] lazyRegisterSession");
    @synchronized (sharedLock) {
        if (urlSession == nil) {
            urlSession = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
        }
    }
}

- (void)unregisterSession {
    DLog(@"[RNBackgroundDownloader] unregisterSession");
    if (urlSession) {
        [urlSession invalidateAndCancel];
        urlSession = nil;
    }
}

- (void)resumeTasks {
    @synchronized (sharedLock) {
        DLog(@"[RNBackgroundDownloader] resumeTasks");
        [urlSession getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
            for (NSURLSessionDownloadTask *task in downloadTasks) {
                if (task.state == NSURLSessionTaskStateRunning) {
                    [task suspend];
                    [task resume];
                }
            }
        }];
    }
}

- (void)removeTaskFromMap:(NSURLSessionTask *)task {
    DLog(@"[RNBackgroundDownloader] removeTaskFromMap");
    @synchronized (sharedLock) {
        NSNumber *taskId = @(task.taskIdentifier);
        RNBGDTaskConfig *taskConfig = taskToConfigMap[taskId];

        [taskToConfigMap removeObjectForKey:taskId];
        [mmkv setData:[self serialize:taskToConfigMap] forKey:ID_TO_CONFIG_MAP_KEY];

        if (taskConfig) {
            [self->idToTaskMap removeObjectForKey:taskConfig.configId];
            [idToPercentMap removeObjectForKey:taskConfig.configId];
            [idToLastBytesMap removeObjectForKey:taskConfig.configId];
        }
    }
}

#pragma mark - JS exported methods

RCT_EXPORT_METHOD(downloadFile:(NSString *)url
                  destinationPath:(NSString *)destination
                  configId:(NSString *)identifier
                  headers:(NSDictionary *)headers
                  metadata:(NSString *)metadata
                  progressIntervalScope:(NSNumber *)progressIntervalScope
                  progressMinBytesScope:(NSNumber *)progressMinBytesScope
                  isAllowedOverRoaming:(BOOL)isAllowedOverRoaming
                  isAllowedOverMetered:(BOOL)isAllowedOverMetered
                  isNotificationVisible:(BOOL)isNotificationVisible
                  notificationTitle:(NSString *)notificationTitle
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    DLog(@"[RNBackgroundDownloader] downloadFile: %@ to %@", url, destination);
    
    if (progressIntervalScope) {
        progressInterval = [progressIntervalScope intValue] / 1000;
        [mmkv setFloat:progressInterval forKey:PROGRESS_INTERVAL_KEY];
    }
    
    if (progressMinBytesScope) {
        progressMinBytes = [progressMinBytesScope longLongValue];
        [mmkv setInt64:progressMinBytes forKey:PROGRESS_MIN_BYTES_KEY];
    }

    NSString *destinationRelative = [self getRelativeFilePathFromPath:destination];

    if (identifier == nil || url == nil || destination == nil) {
        reject(@"E_PARAMS", @"id, url and destination must be set", nil);
        return;
    }

    if (destinationRelative == nil) {
        reject(@"E_DEST", @"destination is not valid", nil);
        return;
    }

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    [request setValue:identifier forHTTPHeaderField:@"configId"];
    
    if (headers != nil) {
        for (NSString *headerKey in headers) {
            [request setValue:[headers valueForKey:headerKey] forHTTPHeaderField:headerKey];
        }
    }

    @synchronized (sharedLock) {
        [self lazyRegisterSession];

        NSURLSessionDownloadTask __strong *task = [urlSession downloadTaskWithRequest:request];
        if (task == nil) {
            reject(@"E_TASK", @"failed to create download task", nil);
            return;
        }

        RNBGDTaskConfig *taskConfig = [[RNBGDTaskConfig alloc] initWithDictionary:@{
            @"id": identifier,
            @"url": url,
            @"destination": destination,
            @"metadata": metadata ?: @""
        }];

        taskToConfigMap[@(task.taskIdentifier)] = taskConfig;
        [mmkv setData:[self serialize:taskToConfigMap] forKey:ID_TO_CONFIG_MAP_KEY];

        self->idToTaskMap[identifier] = task;
        idToPercentMap[identifier] = @0.0;

        [task resume];
        lastProgressReportedAt = [[NSDate alloc] init];
        
        resolve(nil);
    }
}

RCT_EXPORT_METHOD(pauseDownload:(NSString *)identifier)
{
    DLog(@"[RNBackgroundDownloader] pauseDownload");
    @synchronized (sharedLock) {
        NSURLSessionDownloadTask *task = self->idToTaskMap[identifier];
        if (task != nil && task.state == NSURLSessionTaskStateRunning) {
            [task suspend];
        }
    }
}

RCT_EXPORT_METHOD(resumeDownload:(NSString *)identifier)
{
    DLog(@"[RNBackgroundDownloader] resumeDownload");
    @synchronized (sharedLock) {
        NSURLSessionDownloadTask *task = self->idToTaskMap[identifier];
        if (task != nil && task.state == NSURLSessionTaskStateSuspended) {
            [task resume];
        }
    }
}

RCT_EXPORT_METHOD(cancelDownload:(NSString *)identifier)
{
    DLog(@"[RNBackgroundDownloader] cancelDownload");
    @synchronized (sharedLock) {
        NSURLSessionDownloadTask *task = self->idToTaskMap[identifier];
        if (task != nil) {
            [task cancel];
            [self removeTaskFromMap:task];
        }
    }
}

RCT_EXPORT_METHOD(completeHandler:(NSString *)jobId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    DLog(@"[RNBackgroundDownloader] completeHandler: %@", jobId);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (storedCompletionHandler) {
                storedCompletionHandler();
                storedCompletionHandler = nil;
            }
            resolve(nil);
        } @catch (NSException *exception) {
            reject(@"completion_handler_error", exception.reason ?: @"Unknown error", nil);
        }
    });
}

RCT_EXPORT_METHOD(checkForExistingDownloads:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    DLog(@"[RNBackgroundDownloader] checkForExistingDownloads");
    [self lazyRegisterSession];
    [urlSession getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
        NSMutableArray *foundTasks = [[NSMutableArray alloc] init];
        @synchronized (self->sharedLock) {
            [NSThread sleepForTimeInterval:0.1f];

            for (NSURLSessionDownloadTask *foundTask in downloadTasks) {
                NSURLSessionDownloadTask __strong *task = foundTask;

                NSDictionary *headers = task.currentRequest.allHTTPHeaderFields;
                NSString *configId = headers[@"configId"];

                NSNumber *taskIdentifier = @-1;
                RNBGDTaskConfig *taskConfig = nil;
                for (NSNumber *key in self->taskToConfigMap) {
                    RNBGDTaskConfig *config = self->taskToConfigMap[key];
                    if ([config.configId isEqualToString:configId]) {
                        taskIdentifier = key;
                        taskConfig = config;
                        break;
                    }
                }

                if (taskConfig && [taskIdentifier intValue] != -1) {
                    BOOL taskCompletedOrSuspended = (task.state == NSURLSessionTaskStateCompleted || task.state == NSURLSessionTaskStateSuspended);
                    BOOL hasUnknownContentLength = task.countOfBytesExpectedToReceive <= 0;
                    BOOL taskNeedBytes = !hasUnknownContentLength && (task.countOfBytesReceived < task.countOfBytesExpectedToReceive);
                    
                    if (taskCompletedOrSuspended && taskNeedBytes) {
                        NSData *taskResumeData = task.error.userInfo[NSURLSessionDownloadTaskResumeData];

                        if (task.error && task.error.code == -999 && taskResumeData != nil) {
                            task = [self->urlSession downloadTaskWithResumeData:taskResumeData];
                        } else {
                            task = [self->urlSession downloadTaskWithURL:task.currentRequest.URL];
                        }
                        [task resume];
                    }

                    NSNumber *percent = task.countOfBytesExpectedToReceive > 0
                        ? [NSNumber numberWithFloat:(float)task.countOfBytesReceived/(float)task.countOfBytesExpectedToReceive]
                        : @0.0;

                    [foundTasks addObject:@{
                        @"id": taskConfig.configId,
                        @"metadata": taskConfig.metadata,
                        @"state": [NSNumber numberWithInt:(int)task.state],
                        @"bytesDownloaded": [NSNumber numberWithLongLong:task.countOfBytesReceived],
                        @"bytesTotal": [NSNumber numberWithLongLong:task.countOfBytesExpectedToReceive]
                    }];
                    taskConfig.reportedBegin = YES;
                    self->taskToConfigMap[@(task.taskIdentifier)] = taskConfig;
                    self->idToTaskMap[taskConfig.configId] = task;
                    self->idToPercentMap[taskConfig.configId] = percent;
                } else {
                    [task cancel];
                }
            }

            resolve(foundTasks);
        }
    }];
}

#pragma mark - NSURLSessionDownloadDelegate methods

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didFinishDownloadingToURL:(NSURL *)location
{
    NSLog(@"[RNBackgroundDownloader] didFinishDownloadingToURL");
    
    @synchronized (sharedLock) {
        RNBGDTaskConfig *taskConfig = taskToConfigMap[@(downloadTask.taskIdentifier)];

        if (taskConfig == nil) {
            NSLog(@"[RNBackgroundDownloader] No taskConfig found for task");
            return;
        }
        
        NSError *error = [self getServerError:downloadTask];
        
        if (error == nil) {
            BOOL saveSuccess = [self saveFile:taskConfig downloadURL:location error:&error];
            if (!saveSuccess || error != nil) {
                NSLog(@"[RNBackgroundDownloader] File save failed: %@", error);
            }
        }

        if (error == nil) {
            NSDictionary *responseHeaders = ((NSHTTPURLResponse *)downloadTask.response).allHeaderFields;
            
            int64_t bytesTotal = downloadTask.countOfBytesExpectedToReceive;
            int64_t bytesReceived = downloadTask.countOfBytesReceived;
            
            NSDictionary *eventBody = @{
                @"id": taskConfig.configId,
                @"headers": responseHeaders ?: @{},
                @"location": taskConfig.destination,
                @"bytesDownloaded": [NSNumber numberWithLongLong:bytesReceived],
                @"bytesTotal": [NSNumber numberWithLongLong:bytesTotal]
            };
            
            [self sendEventToJS:@"downloadComplete" body:eventBody];
        } else {
            [self sendEventToJS:@"downloadFailed" body:@{
                @"id": taskConfig.configId,
                @"error": [error localizedDescription],
                @"errorCode": @-1
            }];
        }

        [self removeTaskFromMap:downloadTask];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didResumeAtOffset:(int64_t)fileOffset
      expectedbytesTotal:(int64_t)expectedbytesTotal
{
    DLog(@"[RNBackgroundDownloader] didResumeAtOffset");
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesDownloaded
      totalBytesWritten:(int64_t)bytesTotalWritten
      totalBytesExpectedToWrite:(int64_t)bytesTotalExpectedToWrite
{
    @synchronized (sharedLock) {
        RNBGDTaskConfig *taskConfig = taskToConfigMap[@(downloadTask.taskIdentifier)];
        if (taskConfig != nil) {
            if (!taskConfig.reportedBegin) {
                NSDictionary *responseHeaders = ((NSHTTPURLResponse *)downloadTask.response).allHeaderFields;
                [self sendEventToJS:@"downloadBegin" body:@{
                    @"id": taskConfig.configId,
                    @"expectedBytes": [NSNumber numberWithLongLong:bytesTotalExpectedToWrite],
                    @"headers": responseHeaders
                }];
                taskConfig.reportedBegin = YES;
            }

            NSNumber *prevPercent = idToPercentMap[taskConfig.configId];
            NSNumber *prevBytes = idToLastBytesMap[taskConfig.configId];
            NSNumber *percent;
            BOOL percentThresholdMet = NO;
            
            if (bytesTotalExpectedToWrite > 0) {
                percent = [NSNumber numberWithFloat:(float)bytesTotalWritten/(float)bytesTotalExpectedToWrite];
                percentThresholdMet = [percent floatValue] - [prevPercent floatValue] > 0.01f;
            } else {
                percent = @0.0;
            }
            
            long long lastReportedBytes = prevBytes ? [prevBytes longLongValue] : 0;
            BOOL bytesThresholdMet = bytesTotalWritten - lastReportedBytes >= progressMinBytes;
            
            if (percentThresholdMet || bytesThresholdMet || bytesTotalExpectedToWrite <= 0) {
                progressReports[taskConfig.configId] = @{
                    @"id": taskConfig.configId,
                    @"bytesDownloaded": [NSNumber numberWithLongLong:bytesTotalWritten],
                    @"bytesTotal": [NSNumber numberWithLongLong:bytesTotalExpectedToWrite]
                };
                idToPercentMap[taskConfig.configId] = percent;
                idToLastBytesMap[taskConfig.configId] = [NSNumber numberWithLongLong:bytesTotalWritten];
            }

            NSDate *now = [[NSDate alloc] init];
            if ([now timeIntervalSinceDate:lastProgressReportedAt] > progressInterval && progressReports.count > 0) {
                NSArray *progressArray = [progressReports allValues];
                [self sendEventToJS:@"downloadProgress" body:progressArray];
                lastProgressReportedAt = now;
                [progressReports removeAllObjects];
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)session
      task:(NSURLSessionTask *)task
      didCompleteWithError:(NSError *)error
{
    NSLog(@"[RNBackgroundDownloader] didCompleteWithError");
    
    @synchronized (sharedLock) {
        RNBGDTaskConfig *taskConfig = taskToConfigMap[@(task.taskIdentifier)];
        if (taskConfig == nil) {
            return;
        }

        if (error == nil) {
            return;
        }

        if (error.code == -999) {
            return;
        }
        
        [self sendEventToJS:@"downloadFailed" body:@{
            @"id": taskConfig.configId,
            @"error": [error localizedDescription],
            @"errorCode": @(error.code)
        }];
        
        [self removeTaskFromMap:task];
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    DLog(@"[RNBackgroundDownloader] URLSessionDidFinishEventsForBackgroundURLSession");
}

+ (void)setCompletionHandlerWithIdentifier:(NSString *)identifier
                         completionHandler:(CompletionHandler)completionHandler
{
    DLog(@"[RNBackgroundDownloader] setCompletionHandlerWithIdentifier");
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    NSString *sessionIdentifier = [bundleIdentifier stringByAppendingString:@".backgrounddownloadtask"];
    if ([sessionIdentifier isEqualToString:identifier]) {
        storedCompletionHandler = completionHandler;
    }
}

- (NSError *)getServerError:(NSURLSessionDownloadTask *)downloadTask {
    NSError *serverError;
    NSInteger httpStatusCode = [((NSHTTPURLResponse *)downloadTask.response) statusCode];

    if (httpStatusCode != 200 && httpStatusCode != 206) {
        serverError = [NSError errorWithDomain:NSURLErrorDomain
                                          code:httpStatusCode
                                      userInfo:@{NSLocalizedDescriptionKey: [NSHTTPURLResponse localizedStringForStatusCode:httpStatusCode]}];
    }

    return serverError;
}

- (BOOL)saveFile:(RNBGDTaskConfig *)taskConfig
     downloadURL:(NSURL *)location
           error:(NSError **)saveError
{
    NSString *rootPath = [self getRootPathFromPath:taskConfig.destination];
    NSString *fileRelativePath = [self getRelativeFilePathFromPath:taskConfig.destination];
    NSString *fileAbsolutePath = [rootPath stringByAppendingPathComponent:fileRelativePath];
    NSURL *destinationURL = [NSURL fileURLWithPath:fileAbsolutePath];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtURL:[destinationURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [fileManager removeItemAtURL:destinationURL error:nil];

    return [fileManager moveItemAtURL:location toURL:destinationURL error:saveError];
}

#pragma mark - serialization

- (NSData *)serialize:(NSMutableDictionary<NSNumber *, RNBGDTaskConfig *> *)taskMap {
    NSError *error = nil;
    NSData *taskMapRaw = [NSKeyedArchiver archivedDataWithRootObject:taskMap requiringSecureCoding:YES error:&error];

    if (error) {
        DLog(@"[RNBackgroundDownloader] Serialization error: %@", error);
        return nil;
    }

    return taskMapRaw;
}

- (NSMutableDictionary<NSNumber *, RNBGDTaskConfig *> *)deserialize:(NSData *)taskMapRaw {
    NSError *error = nil;
    NSSet *classes = [NSSet setWithObjects:[RNBGDTaskConfig class], [NSMutableDictionary class], [NSNumber class], [NSString class], nil];
    NSMutableDictionary<NSNumber *, RNBGDTaskConfig *> *taskMap = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:taskMapRaw error:&error];

    if (error) {
        DLog(@"[RNBackgroundDownloader] Deserialization error: %@", error);
        return nil;
    }

    return taskMap;
}

- (NSString *)getRootPathFromPath:(NSString *)path {
    NSString *bundlePath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    NSString *bundlePathWithoutUuid = [self getPathWithoutSuffixUuid:bundlePath];
    NSString *dataPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByDeletingLastPathComponent];
    NSString *dataPathWithoutUuid = [self getPathWithoutSuffixUuid:dataPath];

    if ([path hasPrefix:bundlePathWithoutUuid]) {
        return bundlePath;
    }

    if ([path hasPrefix:dataPathWithoutUuid]) {
        return dataPath;
    }

    return nil;
}

- (NSString *)getRelativeFilePathFromPath:(NSString *)path {
    NSString *bundlePath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    NSString *bundlePathWithoutUuid = [self getPathWithoutSuffixUuid:bundlePath];

    NSString *dataPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByDeletingLastPathComponent];
    NSString *dataPathWithoutUuid = [self getPathWithoutSuffixUuid:dataPath];

    if ([path hasPrefix:bundlePathWithoutUuid]) {
        return [path substringFromIndex:[bundlePath length]];
    }

    if ([path hasPrefix:dataPathWithoutUuid]) {
        return [path substringFromIndex:[dataPath length]];
    }

    return nil;
}

- (NSString *)getPathWithoutSuffixUuid:(NSString *)path {
    NSString *pattern = @"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];

    NSString *pathSuffix = [path lastPathComponent];
    NSTextCheckingResult *pathSuffixIsUuid = [regex firstMatchInString:pathSuffix options:0 range:NSMakeRange(0, [pathSuffix length])];
    if (pathSuffixIsUuid) {
        return [path stringByDeletingLastPathComponent];
    }

    return path;
}

@end
