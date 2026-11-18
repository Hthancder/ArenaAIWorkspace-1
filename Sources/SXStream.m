#import "SXStream.h"
#import "SXLog.h"
#include <string.h>

/// Receiver delegate — NSURLSession không có API dataTask với 3 block
/// (nhận response/data/completion), nên dùng delegate thật (iOS API đúng).
@interface SXStreamReceiver : SXNoRedirect <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^onResponse)(NSInteger status);
@property (nonatomic, copy) BOOL (^onData)(NSData *data);
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
	if (self.onData && !self.onData(data)) [dataTask cancel];
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
                      request:(SXRequest *)budget
                     progress:(SXStreamProgress)progress
                        error:(NSError **)outErr {
	NSMutableURLRequest *request = SXJSONRequest(urlString, body, headers);
	if (!request) {
		if (outErr) *outErr = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
		return nil;
	}
	[request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];

	NSMutableString *content = [NSMutableString string];
	__block BOOL sawToolCalls = NO;
	__block NSInteger status = 0;
	__block NSError *taskError = nil;
	__block NSInteger firstTokenMs = -1;
	NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
	__block NSTimeInterval lastFlush = 0;
	__block BOOL doneMarker = NO, oversized = NO;

	NSMutableData *buffer = [NSMutableData data];
	void (^append)(NSString *) = ^(NSString *piece) {
		if (!piece.length || content.length >= 4000 || budget.remaining <= 0) return;
		[content appendString:SXPrefix(piece, 4000 - content.length)];
		NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
		if (firstTokenMs < 0 && [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
			firstTokenMs = (NSInteger)((now - start) * 1000);
			[budget markFirstOutput];
		}
		if (progress && firstTokenMs >= 0 && now - lastFlush >= 0.25) { lastFlush = now; progress([content copy]); }
	};

	void (^consumeLine)(NSString *) = ^(NSString *line) {
		NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (![trimmed hasPrefix:@"data:"]) return;
		NSString *chunkText = [[trimmed substringFromIndex:5] stringByTrimmingCharactersInSet:
							   [NSCharacterSet whitespaceCharacterSet]];
		if ([chunkText isEqualToString:@"[DONE]"]) { doneMarker = YES; return; }
		if (!chunkText.length) return;

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
			append(piece);
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
				if (![part[@"thought"] isEqual:@YES]) append(piece);
			}
		}
	};

	// Split bytes before decoding so a boundary in a Vietnamese/emoji codepoint
	// doesn't delay already-complete events or corrupt UTF-8.
	void (^consumeBuffer)(BOOL) = ^(BOOL flush) {
		const uint8_t *bytes = buffer.bytes;
		NSUInteger startOffset = 0;
		for (NSUInteger i = 0; i < buffer.length && !sawToolCalls && !doneMarker; i++) {
			if (bytes[i] != '\n') continue;
			NSString *line = [[NSString alloc] initWithBytes:bytes + startOffset length:i - startOffset encoding:NSUTF8StringEncoding];
			if (line) consumeLine(line);
			startOffset = i + 1;
		}
		if (flush && startOffset < buffer.length && !sawToolCalls && !doneMarker) {
			NSString *line = [[NSString alloc] initWithBytes:bytes + startOffset length:buffer.length - startOffset encoding:NSUTF8StringEncoding];
			if (line) consumeLine(line);
			startOffset = buffer.length;
		}
		if (startOffset) [buffer replaceBytesInRange:NSMakeRange(0, startOffset) withBytes:NULL length:0];
	};

	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	SXStreamReceiver *receiver = [SXStreamReceiver new];
	receiver.onResponse = ^(NSInteger statusCode) { status = statusCode; };
	receiver.onData = ^BOOL(NSData *data) {
		if (budget.remaining <= 0) return NO;
		if (status < 200 || status >= 300) return YES; // never parse error bodies as SSE
		if (data.length > 512 * 1024 - buffer.length) { oversized = YES; return NO; }
		[buffer appendData:data];
		consumeBuffer(NO);
		return !sawToolCalls && !doneMarker;
	};
	receiver.onComplete = ^(NSError *error) {
		taskError = error;
		if (!error && status >= 200 && status < 300) consumeBuffer(YES);
		dispatch_semaphore_signal(sem);
	};
	NSURLSession *session = [NSURLSession sessionWithConfiguration:SXEphemeralSession() delegate:receiver delegateQueue:nil];
	NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
	BOOL finished = [budget startTask:task] && [budget waitForCompletion:sem];
	[budget finishTask:task];
	if (!finished) {
		[session invalidateAndCancel];
		if (outErr) *outErr = SXRequestError(budget);
		return nil;
	}
	[session finishTasksAndInvalidate];
	if (oversized) {
		if (outErr) *outErr = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil];
		return nil;
	}
	if (taskError && !sawToolCalls && !doneMarker) {
		if (firstTokenMs < 0) { if (outErr) *outErr = taskError; return nil; }
		SXLogWrn(@"llm", @"SSE ngắt sau token đầu; dùng nội dung đã nhận.");
	}

	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
		@"content": [content copy],
		@"sawToolCalls": @(sawToolCalls),
		@"status": @(status),
		@"firstTokenMs": @(firstTokenMs),
	}];
	return result;
}

@end
