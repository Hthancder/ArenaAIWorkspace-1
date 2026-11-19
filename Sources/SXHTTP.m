#import "SXHTTP.h"
#import "SXLog.h"

NSString *const SXHTTPErrorDomain = @"com.sirix.http";

#pragma mark - Kết quả

@implementation SXHTTPResult
- (instancetype)init {
	self = [super init];
	if (self) _body = [NSData data];
	return self;
}
- (NSString *)description {
	return [NSString stringWithFormat:@"<SXHTTPResult status=%ld bytes=%lu error=%@>",
			(long)self.status, (unsigned long)self.body.length,
			self.error.localizedDescription ?: @"(none)"];
}
@end

#pragma mark - Delegate thu dữ liệu

@interface SXHTTPReceiver : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, copy, nullable) SXHTTPDataHandler onData;
@property (nonatomic, copy, nullable) SXHTTPStatusHandler onStatus;
@property (nonatomic) NSUInteger maxBytes;
@property (nonatomic, strong, nullable) NSError *overflowError;
@property (nonatomic) NSInteger status;
@property (nonatomic, copy, nullable) NSString *mimeType;
@property (nonatomic, copy, nullable) NSURLRequest *redirectedRequest;
@end

@implementation SXHTTPReceiver

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
	willPerformHTTPRedirection:(NSHTTPURLResponse *)response
		newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
	(void)session;
	// Không lặng lẽ đi sang host khác: tầng công cụ đọc web yêu cầu giữ 3xx.
	if (self.onData == nil) {
		self.redirectedRequest = request;
		completionHandler(request);
		return;
	}
	completionHandler(nil);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
 didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
	(void)session;
	(void)dataTask;
	if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
		self.status = [(NSHTTPURLResponse *)response statusCode];
	}
	self.mimeType = response.MIMEType;
	if (self.onStatus) self.onStatus(self.status);
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
	didReceiveData:(NSData *)data {
	(void)session;
	(void)dataTask;
	if (self.overflowError) return;
	if (self.onData) {
		if (!self.onData(data)) {
			self.overflowError = [SXHTTP errorWithCode:-2 message:@"Đã huỷ nhận dữ liệu."];
			[dataTask cancel];
		}
		return;
	}
	if (self.maxBytes && self.buffer.length + data.length > self.maxBytes) {
		self.overflowError = [SXHTTP errorWithCode:413
										 message:[NSString stringWithFormat:
											@"Nội dung lớn hơn %lu KB — không tải tiếp.",
											(unsigned long)(self.maxBytes / 1024)]];
		[dataTask cancel];
		return;
	}
	if (!self.buffer) self.buffer = [NSMutableData dataWithCapacity:MAX(data.length, 4096)];
	[self.buffer appendData:data];
}

@end

#pragma mark - SXHTTP

@implementation SXHTTP

+ (NSString *)userAgent {
#ifdef SX_VERSION
	return [NSString stringWithFormat:@"SiriX/%@", SX_VERSION];
#else
	return @"SiriX";
#endif
}

+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
	return [NSError errorWithDomain:SXHTTPErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey: message ?: @"Lỗi không rõ."}];
}

+ (NSString *)snippetOfData:(NSData *)data limit:(NSUInteger)limit {
	if (!data.length) return @"";
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	if (!text) return @"";
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (text.length > limit) text = [[text substringToIndex:limit] stringByAppendingString:@"…"];
	return text;
}

/// Tìm message lỗi ở các hình dạng phổ biến:
///   OpenAI: {"error":{"message":"…"}} | {"error":"…"} | {"message":"…"}
///   Gemini: {"error":{"message":"…","status":"…"}} | promptFeedback.blockReason
+ (NSString *)userMessageForStatus:(NSInteger)status data:(NSData *)data {
	NSString *detail = nil;
	id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
	if ([json isKindOfClass:[NSDictionary class]]) {
		id error = ((NSDictionary *)json)[@"error"];
		if ([error isKindOfClass:[NSDictionary class]]) {
			id message = ((NSDictionary *)error)[@"message"];
			if ([message isKindOfClass:[NSString class]]) detail = message;
		} else if ([error isKindOfClass:[NSString class]]) {
			detail = error;
		}
		if (!detail.length) {
			id message = ((NSDictionary *)json)[@"message"];
			if ([message isKindOfClass:[NSString class]]) detail = message;
		}
		if (!detail.length) {
			id feedback = ((NSDictionary *)json)[@"promptFeedback"];
			if ([feedback isKindOfClass:[NSDictionary class]]) {
				id reason = ((NSDictionary *)feedback)[@"blockReason"];
				if ([reason isKindOfClass:[NSString class]] && [reason length]) {
					detail = [NSString stringWithFormat:@"Bị chặn bởi bộ lọc an toàn (%@).", reason];
				}
			}
		}
	}
	if (!detail.length) detail = [self snippetOfData:data limit:300];
	if (!detail.length) detail = @"(máy chủ không gửi nội dung giải thích)";

	NSString *hint = @"";
	switch (status) {
		case 400: hint = @" — kiểm tra mô hình và tham số."; break;
		case 401: hint = @" — khóa API sai hoặc đã bị thu hồi."; break;
		case 403: hint = @" — khóa không có quyền dùng mô hình này."; break;
		case 404: hint = @" — endpoint hoặc mô hình không tồn tại."; break;
		case 429: hint = @" — bị giới hạn tần suất, thử lại sau ít giây."; break;
		default:
			if (status >= 500) hint = @" — máy chủ nhà cung cấp đang lỗi, thử lại sau.";
			break;
	}
	return [NSString stringWithFormat:@"HTTP %ld: %@%@", (long)status, detail, hint];
}

+ (NSError *)errorWithStatus:(NSInteger)status data:(NSData *)data {
	return [self errorWithCode:status message:[self userMessageForStatus:status data:data]];
}

+ (NSError *)transportError:(NSError *)error {
	if (!error) return [self errorWithCode:-1 message:@"Lỗi mạng không rõ."];
	NSString *message = nil;
	switch (error.code) {
		case NSURLErrorTimedOut:
			message = @"Máy chủ không phản hồi kịp — kiểm tra mạng hoặc thử mô hình nhanh hơn.";
			break;
		case NSURLErrorNotConnectedToInternet:
			message = @"Máy không có kết nối mạng.";
			break;
		case NSURLErrorCannotFindHost:
		case NSURLErrorCannotConnectToHost:
			message = [NSString stringWithFormat:@"Không kết nối được tới máy chủ (%@).",
					   error.userInfo[NSURLErrorFailingURLStringErrorKey] ?: @"?"];
			break;
		case NSURLErrorAppTransportSecurityRequiresSecureConnection:
			message = @"iOS chặn kết nối không bảo mật tới địa chỉ này (ATS). Dùng https://.";
			break;
		case NSURLErrorCancelled:
			message = @"Yêu cầu đã bị huỷ.";
			break;
		default:
			message = error.localizedDescription;
			break;
	}
	return [self errorWithCode:error.code message:message];
}

/// Chạy một request và chờ đồng bộ. Tách riêng để POST/GET dùng chung.
+ (SXHTTPResult *)executeRequest:(NSURLRequest *)request
						  maxBytes:(NSUInteger)maxBytes
						  onData:(SXHTTPDataHandler)onData
						onStatus:(SXHTTPStatusHandler)onStatus
						 timeout:(NSTimeInterval)timeout
					 idleTimeout:(NSTimeInterval)idleTimeout {
	SXHTTPResult *result = [[SXHTTPResult alloc] init];

	NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	configuration.timeoutIntervalForRequest = MAX(1.0, idleTimeout);
	configuration.timeoutIntervalForResource = MAX(1.0, timeout);
	configuration.HTTPMaximumConnectionsPerHost = 3;
	configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	// Không dựa vào cookie dùng chung: mỗi request là một phiên riêng.
	configuration.HTTPCookieStorage = nil;
	configuration.URLCache = nil;

	SXHTTPReceiver *receiver = [[SXHTTPReceiver alloc] init];
	receiver.maxBytes = maxBytes;
	receiver.onData = onData;
	receiver.onStatus = onStatus;

	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration
														  delegate:receiver
													 delegateQueue:nil];
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	__block NSError *taskError = nil;
	NSURLSessionDataTask *task = [session dataTaskWithRequest:request
										   completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		(void)data;
		(void)response;
		taskError = error;
		dispatch_semaphore_signal(semaphore);
	}];
	[task resume];

	long waited = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW,
		(int64_t)((MAX(1.0, timeout) + 1.0) * NSEC_PER_SEC)));
	[session finishTasksAndInvalidate];

	if (waited != 0) {
		[task cancel];
		result.error = [self errorWithCode:NSURLErrorTimedOut
								   message:[NSString stringWithFormat:
											@"Yêu cầu vượt quá %.0f giây — đã huỷ.", timeout]];
		return result;
	}

	result.status = receiver.status;
	result.mimeType = receiver.mimeType;
	result.body = receiver.buffer ?: [NSData data];

	if (receiver.overflowError) {
		result.error = receiver.overflowError;
		return result;
	}
	if (taskError && taskError.code != NSURLErrorCancelled) {
		result.error = [self transportError:taskError];
		return result;
	}
	if (receiver.status == 0) {
		result.error = [self errorWithCode:-3 message:@"Máy chủ đóng kết nối mà không trả lời."];
	}
	return result;
}

+ (SXHTTPResult *)postURL:(NSString *)urlString
					 body:(NSDictionary *)body
				  headers:(NSDictionary<NSString *, NSString *> *)headers
				  timeout:(NSTimeInterval)timeout
			  idleTimeout:(NSTimeInterval)idleTimeout
				   onData:(SXHTTPDataHandler)onData {
	return [self postURL:urlString body:body headers:headers timeout:timeout
			 idleTimeout:idleTimeout onStatus:nil onData:onData];
}

+ (SXHTTPResult *)postURL:(NSString *)urlString
					 body:(NSDictionary *)body
				  headers:(NSDictionary<NSString *, NSString *> *)headers
				  timeout:(NSTimeInterval)timeout
			  idleTimeout:(NSTimeInterval)idleTimeout
				 onStatus:(SXHTTPStatusHandler)onStatus
				   onData:(SXHTTPDataHandler)onData {
	NSURL *url = [NSURL URLWithString:urlString ?: @""];
	if (!url || !url.scheme.length) {
		SXHTTPResult *result = [[SXHTTPResult alloc] init];
		result.error = [self errorWithCode:-1
								   message:[NSString stringWithFormat:@"Địa chỉ không hợp lệ: %@",
											urlString ?: @"(rỗng)"]];
		return result;
	}
	NSError *jsonError = nil;
	NSData *payload = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:&jsonError];
	if (!payload) {
		SXHTTPResult *result = [[SXHTTPResult alloc] init];
		result.error = [self errorWithCode:-4 message:[NSString stringWithFormat:
			@"Không tạo được JSON yêu cầu: %@", jsonError.localizedDescription ?: @"?"]];
		return result;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = payload;
	request.timeoutInterval = MAX(1.0, timeout);
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json, text/event-stream" forHTTPHeaderField:@"Accept"];
	[request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
	[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		(void)stop;
		if (key.length && value.length) [request setValue:value forHTTPHeaderField:key];
	}];

	SXLogDbg(@"http", @"POST %@ (%lu byte, %lu header)", url.host ?: urlString,
			 (unsigned long)payload.length, (unsigned long)headers.count);
	return [self executeRequest:request
					  maxBytes:0
						onData:onData
					  onStatus:onStatus
					   timeout:timeout
				   idleTimeout:idleTimeout];
}

+ (SXHTTPResult *)getURL:(NSString *)urlString
				 headers:(NSDictionary<NSString *, NSString *> *)headers
				 timeout:(NSTimeInterval)timeout
			 idleTimeout:(NSTimeInterval)idleTimeout
				maxBytes:(NSUInteger)maxBytes {
	NSURL *url = [NSURL URLWithString:urlString ?: @""];
	if (!url || !url.scheme.length) {
		SXHTTPResult *result = [[SXHTTPResult alloc] init];
		result.error = [self errorWithCode:-1
								   message:[NSString stringWithFormat:@"Địa chỉ không hợp lệ: %@",
											urlString ?: @"(rỗng)"]];
		return result;
	}
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	request.timeoutInterval = MAX(1.0, timeout);
	[request setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
	[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		(void)stop;
		if (key.length && value.length) [request setValue:value forHTTPHeaderField:key];
	}];
	return [self executeRequest:request
					  maxBytes:maxBytes
						onData:nil
					  onStatus:nil
					   timeout:timeout
				   idleTimeout:idleTimeout];
}

@end
