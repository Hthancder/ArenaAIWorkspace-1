#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A single attempt, with a monotonic deadline. First output may unlock the
/// longer completion budget. Cancellation wakes backoff and cancels the task.
@interface SXRequest : NSObject
- (instancetype)initWithTimeout:(NSTimeInterval)timeout;
- (instancetype)initWithTimeout:(NSTimeInterval)timeout firstOutput:(NSTimeInterval)firstOutput;
@property (nonatomic, readonly) NSTimeInterval remaining;
@property (nonatomic, readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
- (void)markFirstOutput;
- (BOOL)startTask:(NSURLSessionTask *)task;
- (void)finishTask:(NSURLSessionTask *)task;
- (BOOL)waitForCompletion:(dispatch_semaphore_t)signal;
- (BOOL)waitForDelay:(NSTimeInterval)delay;
+ (void)setNetworkAllowed:(BOOL)allowed;
@end

/// No redirects: API keys and media must stay at the explicitly selected origin.
@interface SXNoRedirect : NSObject <NSURLSessionTaskDelegate>
@end

FOUNDATION_EXPORT NSURLSessionConfiguration *SXEphemeralSession(void);
FOUNDATION_EXPORT BOOL SXDefinitelyOffline(void);
FOUNDATION_EXPORT NSURL * _Nullable SXHTTPSURL(NSString *text);
FOUNDATION_EXPORT NSString *SXEndpoint(NSString *base, NSString *suffix);
FOUNDATION_EXPORT NSString *const SXGeminiBaseURL;
FOUNDATION_EXPORT NSString * _Nullable SXGeminiEndpoint(NSString *model, BOOL stream);
FOUNDATION_EXPORT NSError *SXRequestError(SXRequest *request);
/// Bounded, ephemeral HTTP; only call on a worker queue. Returns status/data.
FOUNDATION_EXPORT NSDictionary * _Nullable SXHTTP(NSURLRequest *request, SXRequest *budget, NSUInteger maxBytes, NSError **error);
FOUNDATION_EXPORT NSMutableURLRequest * _Nullable SXJSONRequest(NSString *url, NSDictionary *body, NSDictionary *headers);

NS_ASSUME_NONNULL_END
