#import "SXNetwork.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include <netinet/in.h>
#include <math.h>

static BOOL SXNetworkAllowed = YES;
static NSHashTable<SXRequest *> *SXRequests;
static NSTimeInterval SXNow(void) { return NSProcessInfo.processInfo.systemUptime; }

@implementation SXRequest {
	NSCondition *_lock;
	NSURLSessionTask *_task;
	dispatch_semaphore_t _waiting;
	NSTimeInterval _deadline, _firstDeadline;
	BOOL _cancelled;
}
- (instancetype)initWithTimeout:(NSTimeInterval)timeout {
	return [self initWithTimeout:timeout firstOutput:timeout];
}
- (instancetype)initWithTimeout:(NSTimeInterval)timeout firstOutput:(NSTimeInterval)firstOutput {
	if ((self = [super init])) {
		_lock = [NSCondition new];
		NSTimeInterval now = SXNow();
		_deadline = now + MAX(0, timeout);
		_firstDeadline = now + MAX(0, MIN(timeout, firstOutput));
		@synchronized (SXRequest.class) {
			if (!SXRequests) SXRequests = [NSHashTable weakObjectsHashTable];
			[SXRequests addObject:self];
			_cancelled = !SXNetworkAllowed;
		}
	}
	return self;
}
+ (void)setNetworkAllowed:(BOOL)allowed {
	NSArray *pending = nil;
	@synchronized (SXRequest.class) {
		SXNetworkAllowed = allowed;
		if (!allowed) pending = SXRequests.allObjects;
	}
	for (SXRequest *request in pending) [request cancel];
}
- (BOOL)isCancelled { [_lock lock]; BOOL result = _cancelled; [_lock unlock]; return result; }
- (NSTimeInterval)remaining {
	[_lock lock]; NSTimeInterval value = _cancelled ? 0 : MAX(0, _firstDeadline - SXNow()); [_lock unlock];
	return value;
}
- (void)markFirstOutput {
	[_lock lock];
	if (!_cancelled && SXNow() < _firstDeadline) _firstDeadline = _deadline;
	[_lock unlock];
}
- (void)cancel {
	[_lock lock];
	_cancelled = YES;
	NSURLSessionTask *task = _task;
	if (_waiting) dispatch_semaphore_signal(_waiting);
	[_lock broadcast];
	[_lock unlock];
	[task cancel];
}
- (BOOL)startTask:(NSURLSessionTask *)task {
	[_lock lock];
	BOOL ok = !_task && !_cancelled && SXNow() < _firstDeadline;
	if (ok) { _task = task; [task resume]; }
	[_lock unlock];
	return ok;
}
- (void)finishTask:(NSURLSessionTask *)task {
	[_lock lock]; if (_task == task) _task = nil; [_lock unlock];
}
- (BOOL)waitForCompletion:(dispatch_semaphore_t)signal {
	// Wait in stages so a first token can extend the budget without blocking a hook.
	[_lock lock]; _waiting = signal; [_lock unlock];
	BOOL completed = NO;
	for (NSTimeInterval remaining = self.remaining; remaining > 0; remaining = self.remaining) {
		if (dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC))) == 0) {
			completed = self.remaining > 0; break;
		}
	}
	[_lock lock]; _waiting = nil; [_lock unlock];
	return completed;
}
- (BOOL)waitForDelay:(NSTimeInterval)delay {
	[_lock lock];
	NSTimeInterval end = SXNow() + delay;
	if (_cancelled || end >= _firstDeadline) { [_lock unlock]; return NO; }
	while (!_cancelled && SXNow() < end) [_lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:MAX(0, end - SXNow())]];
	BOOL ok = !_cancelled && SXNow() < _firstDeadline;
	[_lock unlock];
	return ok;
}
@end

@implementation SXNoRedirect
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
	newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))handler {
	(void)session; (void)task; (void)response; (void)request;
	handler(nil);
}
@end

BOOL SXDefinitelyOffline(void) {
#ifdef SX_TESTING
	if (NSClassFromString(@"SXFixtureProtocol")) return NO;
#endif
	struct sockaddr_in address = {0};
	address.sin_len = sizeof(address);
	address.sin_family = AF_INET;
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&address);
	if (!reachability) return NO;
	SCNetworkReachabilityFlags flags = 0;
	BOOL known = SCNetworkReachabilityGetFlags(reachability, &flags);
	CFRelease(reachability);
	return known && !(flags & (kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsConnectionRequired));
}
NSURL *SXHTTPSURL(NSString *text) {
	if (!text.length) return nil;
	NSURLComponents *parts = [NSURLComponents componentsWithString:[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
	return [parts.scheme.lowercaseString isEqualToString:@"https"] && parts.host.length && !parts.user && !parts.password && !parts.fragment ? parts.URL : nil;
}
NSString *SXEndpoint(NSString *base, NSString *suffix) {
	NSURL *url = SXHTTPSURL(base);
	NSURLComponents *parts = url ? [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO] : nil;
	if (!parts) return @"";
	NSString *path = parts.path ?: @"";
	while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
	if (![path hasSuffix:suffix]) {
		for (NSString *known in @[@"/chat/completions", @"/audio/transcriptions", @"/audio/translations", @"/audio/speech"]) {
			if ([path hasSuffix:known]) { path = [path substringToIndex:path.length - known.length]; break; }
		}
		path = [path stringByAppendingString:suffix];
	}
	parts.path = path;
	return parts.URL.absoluteString ?: @"";
}
NSString *const SXGeminiBaseURL = @"https://generativelanguage.googleapis.com/v1beta";
NSString *SXGeminiEndpoint(NSString *model, BOOL stream) {
	if ([model hasPrefix:@"models/"]) model = [model substringFromIndex:7];
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."];
	if (!model.length || model.length > 128 || [model rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return nil;
	return [NSString stringWithFormat:@"%@/models/%@:%@", SXGeminiBaseURL, model,
		stream ? @"streamGenerateContent?alt=sse" : @"generateContent"];
}
NSError *SXRequestError(SXRequest *request) {
	return [NSError errorWithDomain:NSURLErrorDomain code:request.cancelled ? NSURLErrorCancelled : NSURLErrorTimedOut
		userInfo:@{NSLocalizedDescriptionKey: request.cancelled ? @"Đã hủy yêu cầu." : @"Hết thời gian chờ kết nối."}];
}

@interface SXHTTPReceiver : SXNoRedirect <NSURLSessionDataDelegate>
@property (nonatomic) NSInteger status;
@property (nonatomic) NSUInteger maxBytes;
@property (nonatomic) BOOL oversized;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) dispatch_semaphore_t signal;
@property (nonatomic, strong) NSError *error;
@end
@implementation SXHTTPReceiver
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
	(void)session; (void)task;
	self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
	self.oversized = response.expectedContentLength > (int64_t)self.maxBytes;
	handler(self.oversized ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
	(void)session;
	if (self.oversized || data.length > self.maxBytes - self.data.length) { self.oversized = YES; [task cancel]; return; }
	[self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
	(void)session; (void)task;
	self.error = self.oversized ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum
		userInfo:@{NSLocalizedDescriptionKey: @"Phản hồi vượt giới hạn dung lượng."}] : error;
	dispatch_semaphore_signal(self.signal);
}
@end

NSURLSessionConfiguration *SXEphemeralSession(void) {
	NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
	config.HTTPCookieStorage = nil;
	config.URLCache = nil;
#ifdef SX_TESTING
	Class fixture = NSClassFromString(@"SXFixtureProtocol");
	if (fixture) config.protocolClasses = @[fixture];
#endif
	return config;
}

NSDictionary *SXHTTP(NSURLRequest *request, SXRequest *budget, NSUInteger maxBytes, NSError **error) {
	if (!request.URL || !SXHTTPSURL(request.URL.absoluteString)) {
		if (error) *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:@{NSLocalizedDescriptionKey: @"Địa chỉ API HTTPS không hợp lệ."}];
		return nil;
	}
	if (budget.remaining <= 0) { if (error) *error = SXRequestError(budget); return nil; }
	SXHTTPReceiver *receiver = [SXHTTPReceiver new];
	receiver.data = [NSMutableData data]; receiver.maxBytes = maxBytes; receiver.signal = dispatch_semaphore_create(0);
	NSURLSession *session = [NSURLSession sessionWithConfiguration:SXEphemeralSession() delegate:receiver delegateQueue:nil];
	NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
	BOOL done = [budget startTask:task] && [budget waitForCompletion:receiver.signal];
	[budget finishTask:task];
	if (!done) { [session invalidateAndCancel]; if (error) *error = SXRequestError(budget); return nil; }
	[session finishTasksAndInvalidate];
	if (receiver.error) { if (error) *error = receiver.error; return nil; }
	return @{@"status": @(receiver.status), @"data": [receiver.data copy]};
}
NSMutableURLRequest *SXJSONRequest(NSString *url, NSDictionary *body, NSDictionary *headers) {
	NSURL *target = SXHTTPSURL(url);
	NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
	if (!target || !payload) return nil;
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:target];
	request.HTTPMethod = @"POST";
	request.HTTPBody = payload;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	for (NSString *name in headers) [request setValue:headers[name] forHTTPHeaderField:name];
	return request;
}
