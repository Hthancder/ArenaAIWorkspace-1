#import "SXStream.h"

static const NSTimeInterval kSXStreamTimeout = 60;

/// Receiver delegate — NSURLSession không có API dataTask với 3 block
/// (nhận response/data/completion), nên dùng delegate thật (iOS API đúng).
@interface SXStreamReceiver : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^onResponse)(NSInteger status);
@property (nonatomic, copy) void (^onData)(NSData *data);
@property (nonatomic, copy) void (^onComplete)(NSError *error);
@end

@implementation SXStreamReceiver

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
	didReceiveResponse:(NSURLResponse *)response
	completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
	if (self.onResponse) {
		self.onResponse([(NSHTTPURLResponse *)response statusCode]);
	}
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
	didReceiveData:(NSData *)data {
	if (self.onData) self.onData(data);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
	didCompleteWithError:(NSError *)error {
	if (self.onComplete) self.onComplete(error);
}

@end

@implementation SXStream

+ (NSDictionary *)postJSON:(NSDictionary *)body
					 toURL:(NSString *)urlString
				   headers:(NSDictionary<NSString *, NSString *> *)headers
					format:(SXStreamFormat)format
					 error:(NSError **)outErr {
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) {
		if (outErr) *outErr = [NSError errorWithDomain:@"com.sirix.llm" code:-1
			userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"URL không hợp lệ: %@", urlString]}];
		return nil;
	}
	NSError *jsonError = nil;
	NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
	if (!payload) {
		if (outErr) *outErr = jsonError ?: [NSError errorWithDomain:@"com.sirix.llm" code:-2
			userInfo:@{NSLocalizedDescriptionKey: @"Không tạo được JSON yêu cầu."}];
		return nil;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = payload;
	request.timeoutInterval = kSXStreamTimeout;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
	[request setValue:@"SiriX/1.1" forHTTPHeaderField:@"User-Agent"];
	[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		[request setValue:value forHTTPHeaderField:key];
	}];

	NSMutableString *content = [NSMutableString string];
	NSMutableString *errorBody = [NSMutableString string];
	__block BOOL sawToolCalls = NO;
	__block NSInteger status = 0;
	__block NSError *taskError = nil;
	__block NSInteger firstTokenMs = -1;
	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

	NSMutableData *buffer = [NSMutableData data];
	__block NSString *pendingTail = @"";

	void (^consumeLine)(NSString *) = ^(NSString *line) {
		NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (![trimmed hasPrefix:@"data:"]) return;
		NSString *chunkText = [[trimmed substringFromIndex:5] stringByTrimmingCharactersInSet:
							   [NSCharacterSet whitespaceCharacterSet]];
		if (!chunkText.length || [chunkText isEqualToString:@"[DONE]"]) return;

		id json = [NSJSONSerialization JSONObjectWithData:[chunkText dataUsingEncoding:NSUTF8StringEncoding]
												  options:0 error:NULL];
		if (![json isKindOfClass:[NSDictionary class]]) return;

		if (format == SXStreamFormatOpenAI) {
			NSArray *choices = [json[@"choices"] isKindOfClass:[NSArray class]] ? json[@"choices"] : nil;
			id delta = (choices.count && [choices[0] isKindOfClass:[NSDictionary class]])
				? choices[0][@"delta"] : nil;
			if (![delta isKindOfClass:[NSDictionary class]]) return;
			if ([delta[@"tool_calls"] isKindOfClass:[NSArray class]] && [delta[@"tool_calls"] count]) {
				sawToolCalls = YES;
				return;
			}
			NSString *piece = [delta[@"content"] isKindOfClass:[NSString class]] ? delta[@"content"] : nil;
			if (piece.length) {
				if (firstTokenMs < 0) firstTokenMs = (NSInteger)((CFAbsoluteTimeGetCurrent() - start) * 1000);
				[content appendString:piece];
			}
		} else {
			NSArray *candidates = [json[@"candidates"] isKindOfClass:[NSArray class]] ? json[@"candidates"] : nil;
			id cand = (candidates.count && [candidates[0] isKindOfClass:[NSDictionary class]])
				? candidates[0] : nil;
			id candContent = [cand isKindOfClass:[NSDictionary class]] ? cand[@"content"] : nil;
			NSArray *parts = ([candContent isKindOfClass:[NSDictionary class]]
							  && [candContent[@"parts"] isKindOfClass:[NSArray class]])
				? candContent[@"parts"] : nil;
			for (id part in parts) {
				if (![part isKindOfClass:[NSDictionary class]]) continue;
				if ([part[@"functionCall"] isKindOfClass:[NSDictionary class]]) {
					sawToolCalls = YES;
					return;
				}
				NSString *piece = [part[@"text"] isKindOfClass:[NSString class]] ? part[@"text"] : nil;
				if (piece.length) {
					if (firstTokenMs < 0) firstTokenMs = (NSInteger)((CFAbsoluteTimeGetCurrent() - start) * 1000);
					[content appendString:piece];
				}
			}
		}
	};

	void (^consumeBuffer)(BOOL) = ^(BOOL flush) {
		if (!buffer.length && !flush) return;
		NSString *text = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
		if (!text) {
			// UTF-8 bị cắt giữa chunk — giữ buffer chờ chunk kế.
			if (flush) {
				NSString *whole = [[NSString alloc] initWithData:buffer encoding:NSISOLatin1StringEncoding];
				for (NSString *line in [whole componentsSeparatedByString:@"\n"]) consumeLine(line);
				[buffer setLength:0];
			}
			return;
		}
		[buffer setLength:0];
		NSString *joined = [pendingTail stringByAppendingString:text];
		NSArray<NSString *> *lines = [joined componentsSeparatedByString:@"\n"];
		pendingTail = flush ? @"" : (lines.lastObject ?: @"");
		NSUInteger count = lines.count - (flush ? 0 : 1);
		for (NSUInteger i = 0; i < count; i++) consumeLine(lines[i]);
	};

	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	SXStreamReceiver *receiver = [[SXStreamReceiver alloc] init];
	receiver.onResponse = ^(NSInteger statusCode) {
		status = statusCode;
	};
	receiver.onData = ^(NSData *data) {
		if (sawToolCalls) return;
		[buffer appendData:data];
		if (status >= 400 && errorBody.length < 4096) {
			NSString *errChunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			if (errChunk) [errorBody appendString:errChunk];
		}
		consumeBuffer(NO);
	};
	receiver.onComplete = ^(NSError *error) {
		taskError = error;
		consumeBuffer(YES);
		dispatch_semaphore_signal(sem);
	};
	NSURLSession *session = [NSURLSession
		sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
						delegate:receiver
				   delegateQueue:nil]; // nil = hàng đợi tuần tự do session tạo
	[[session dataTaskWithRequest:request] resume];

	long waited = dispatch_semaphore_wait(sem,
		dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kSXStreamTimeout + 5) * NSEC_PER_SEC)));
	[session finishTasksAndInvalidate];
	if (waited != 0) {
		if (outErr) *outErr = [NSError errorWithDomain:@"com.sirix.llm" code:-8
			userInfo:@{NSLocalizedDescriptionKey: @"SSE hết thời gian chờ."}];
		return nil;
	}
	if (taskError && status < 400 && !content.length && !sawToolCalls) {
		if (outErr) *outErr = taskError;
		return nil;
	}

	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
		@"content": [content copy],
		@"sawToolCalls": @(sawToolCalls),
		@"status": @(status),
		@"firstTokenMs": @(firstTokenMs),
	}];
	if (errorBody.length) result[@"errorText"] = [errorBody copy];
	return result;
}

@end
