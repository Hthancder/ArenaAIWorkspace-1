// Kiểm thử vòng gọi công cụ của SXLLM trên macOS với HTTP giả.
//
// Trước đây tầng này không có test → lỗi như "tool result sai định dạng",
// "Gemini gửi role tool bị 400", "stream xong không có nội dung" chỉ lộ trên
// thiết bị. Ở đây mọi thứ vẫn là mã thật (SXLLM, SXStream, SXToolkit,
// SXHeaders) trừ ba điểm nối: HTTP, prefs, mạng.
#import <Foundation/Foundation.h>
#import "SXLLM.h"
#import "SXPrefs.h"

/// Selector có cả `onDelta` là phần nội bộ (khai báo trong lớp, không đưa vào
/// header công khai) — test gọi thẳng qua category.
@interface SXLLM (TestHooks)
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)tools
		   executor:(nullable SXToolExec)executor
		   provider:(SXProvider)provider
			onDelta:(nullable SXLLMDelta)onDelta
		 completion:(SXLLMCompletion)completion;
@end
#import "SXHTTP.h"
#import "SXToolkit.h"
#import "SXLog.h"
#include <assert.h>
#include <stdio.h>

#pragma mark - HTTP giả

static NSMutableArray<NSDictionary *> *queue;
static NSMutableArray<NSDictionary *> *requests;

void SXMockHTTPReset(void) {
	queue = [NSMutableArray array];
	requests = [NSMutableArray array];
}
void SXMockHTTPReply(NSInteger status, NSString *body) {
	[queue addObject:@{@"status": @(status), @"body": body ?: @""}];
}
void SXMockHTTPReplyJSON(NSInteger status, id object) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
	SXMockHTTPReply(status, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}
NSArray<NSDictionary *> *SXMockHTTPRequests(void) { return requests; }
NSString *SXMockLastRequestBody(void) { return requests.lastObject[@"body"]; }

@implementation SXHTTP
+ (SXHTTPResult *)postURL:(NSString *)urlString
					 body:(NSDictionary *)body
				  headers:(NSDictionary<NSString *, NSString *> *)headers
				  timeout:(NSTimeInterval)timeout
			  idleTimeout:(NSTimeInterval)idleTimeout
				 onStatus:(SXHTTPStatusHandler)onStatus
				   onData:(SXHTTPDataHandler)onData {
	NSData *encoded = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:NULL];
	[requests addObject:@{@"url": urlString ?: @"",
						  @"device": urlString,
						  @"body": encoded ? [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding] : @"",
						  @"headers": headers ?: @{}}];
	(void)timeout; (void)idleTimeout;
	SXHTTPResult *result = [[SXHTTPResult alloc] init];
	if (!queue.count) {
		result.error = [NSError errorWithDomain:@"mock" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"hết kịch bản"}];
		return result;
	}
	NSDictionary *script = queue.firstObject;
	[queue removeObjectAtIndex:0];
	result.status = [script[@"status"] integerValue];
	result.body = [script[@"body"] dataUsingEncoding:NSUTF8StringEncoding];
	if (onStatus) onStatus(result.status);
	if (onData && result.body.length) {
		NSUInteger step = MAX((NSUInteger)5, result.body.length / 3 + 1);
		for (NSUInteger offset = 0; offset < result.body.length; offset += step) {
			NSUInteger length = MIN(step, result.body.length - offset);
			if (!onData([result.body subdataWithRange:NSMakeRange(offset, length)])) break;
		}
	}
	return result;
}
+ (SXHTTPResult *)postURL:(NSString *)u body:(NSDictionary *)b headers:(NSDictionary *)h
				  timeout:(NSTimeInterval)t idleTimeout:(NSTimeInterval)i onData:(SXHTTPDataHandler)d {
	return [self postURL:u body:b headers:h timeout:t idleTimeout:i onStatus:nil onData:d];
}
+ (SXHTTPResult *)getURL:(NSString *)u headers:(NSDictionary *)h timeout:(NSTimeInterval)t
			 idleTimeout:(NSTimeInterval)i maxBytes:(NSUInteger)m {
	(void)u; (void)h; (void)t; (void)i; (void)m;
	SXHTTPResult *result = [[SXHTTPResult alloc] init];
	result.error = [NSError errorWithDomain:@"mock" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"GET không dùng"}];
	return result;
}
+ (NSString *)userAgent { return @"SiriX/test"; }
+ (NSString *)userMessageForStatus:(NSInteger)status data:(NSData *)data {
	(void)data;
	return [NSString stringWithFormat:@"HTTP %ld", (long)status];
}
+ (NSError *)errorWithStatus:(NSInteger)status data:(NSData *)data {
	return [NSError errorWithDomain:@"mock" code:status
						   userInfo:@{NSLocalizedDescriptionKey: [self userMessageForStatus:status data:data]}];
}
+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
	return [NSError errorWithDomain:@"mock" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"lỗi"}];
}
@end

#pragma mark - Prefs giả

static BOOL testStreaming = NO;
static NSString *testBase = @"https://mock.test/v1";

@implementation SXPrefs
+ (instancetype)shared { static SXPrefs *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [SXPrefs new]; }); return p; }
- (BOOL)enabled { return YES; }
- (SXProvider)provider { return SXProviderOpenAI; }
- (NSString *)openaiKey { return @"sk-test"; }
- (NSString *)openaiBase { return testBase; }
- (NSString *)openaiModel { return @"mock-model"; }
- (NSString *)geminiKey { return @"gemini-test"; }
- (NSString *)geminiModel { return @"gemini-2.0-flash"; }
- (double)temperature { return 0.2; }
- (NSTimeInterval)responseTimeout { return 8; }
- (NSInteger)contextTurns { return 4; }
- (NSInteger)maxToolRounds { return 2; }
- (BOOL)streaming { return testStreaming; }
- (BOOL)markdown { return NO; }
- (BOOL)verbose { return NO; }
- (NSString *)customPrompt { return nil; }
- (NSArray<NSDictionary *> *)openaiHeaders { return @[]; }
- (NSArray<NSDictionary *> *)geminiHeaders { return @[]; }
- (NSArray<NSDictionary *> *)headersForProvider:(SXProvider)p { (void)p; return @[]; }
- (NSString *)systemPrompt { return @"Bạn là trợ lý kiểm thử."; }
@end

void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) {
	(void)level; (void)category; (void)format;
}

#pragma mark - Tiện ích

static NSString *SSE(NSArray<NSString *> *chunks) {
	NSMutableString *body = [NSMutableString string];
	for (NSString *chunk in chunks) [body appendFormat:@"data: %@\n\n", chunk];
	[body appendString:@"data: [DONE]\n\n"];
	return body;
}

static NSDictionary *Run(SXProvider provider, NSArray<NSDictionary *> *tools, SXToolExec executor,
						 NSMutableArray<NSString *> *deltas, NSError **outError) {
	__block NSString *answer = nil;
	__block NSError *failure = nil;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	SXLLMDelta onDelta = deltas ? ^(NSString *delta, NSInteger ms) {
		(void)ms;
		[deltas addObject:delta];
	} : nil;
	[SXLLM askQuestion:@"xin chào" history:@[] tools:tools ?: @[] executor:executor
			  provider:provider onDelta:onDelta completion:^(NSString *text, NSError *error, NSDictionary *info) {
		(void)info;
		answer = [text copy];
		failure = error;
		dispatch_semaphore_signal(done);
	}];
	dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
	if (outError) *outError = failure;
	return @{@"answer": answer ?: [NSNull null]};
}

static NSDictionary *ToolDefinition(void) {
	return @{@"name": @"clock", @"description": @"Đọc giờ máy.",
			 @"parameters": @{@"type": @"object", @"properties": @{}}};
}

int main(void) {
	@autoreleasepool {
		[SXToolkit removeAllTools];
		[SXToolkit registerTool:[SXTool toolWithName:@"clock" title:@"Giờ" summary:@"Đọc giờ."
											 prompt:@"Đọc giờ máy." category:SXToolCategoryDevice
										 parameters:@{@"type": @"object", @"properties": @{}}
											handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			(void)arguments; (void)error;
			return @{@"result": @"12:00"};
		}]];

		// ── 1. Một lượt, không công cụ.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{@"message": @{@"role": @"assistant", @"content": @"Chào bạn!"}}]});
		NSError *error = nil;
		NSDictionary *out = Run(SXProviderOpenAI, @[], nil, nil, &error);
		assert(!error && [out[@"answer"] isEqualToString:@"Chào bạn!"]);
		assert([SXMockLastRequestBody() containsString:@"\"model\":\"mock-model\""]);

		// ── 2. Model gọi công cụ → kết quả tool đúng chuẩn, vòng hai trả lời.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{
			@"message": @{@"role": @"assistant", @"content": [NSNull null],
						  @"tool_calls": @[@{@"id": @"call_1", @"type": @"function",
											 @"function": @{@"name": @"clock", @"arguments": @"{}"}}]}}]});
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{
			@"message": @{@"role": @"assistant", @"content": @"Bây giờ là 12:00."}}]});
		__block NSInteger runs = 0;
		SXToolExec executor = ^NSDictionary *(NSString *name, NSDictionary *arguments, NSError **e) {
			(void)name; (void)arguments; (void)e;
			runs++;
			return @{@"result": @"12:00"};
		};
		out = Run(SXProviderOpenAI, @[ToolDefinition()], executor, nil, &error);
		assert(!error && runs == 1);
		assert([out[@"answer"] isEqualToString:@"Bây giờ là 12:00."]);
		assert(SXMockHTTPRequests().count == 2);
		NSString *secondBody = SXMockHTTPRequests()[1][@"body"];
		assert([secondBody containsString:@"\"role\":\"tool\""]);
		assert([secondBody containsString:@"\"tool_call_id\":\"call_1\""]);
		assert([secondBody containsString:@"result"] && [secondBody containsString:@"12:00"]);
		assert([secondBody containsString:@"\"tools\""]);

		// ── 3. Stream SSE: mảnh văn bản đến tăng dần, đúng thứ tự.
		testStreaming = YES;
		SXMockHTTPReset();
		SXMockHTTPReply(200, SSE(@[@"{\"choices\":[{\"delta\":{\"content\":\"Xin \"}}]}",
								   @"{\"choices\":[{\"delta\":{\"content\":\"chào\"}}]}"]));
		NSMutableArray<NSString *> *deltas = [NSMutableArray array];
		out = Run(SXProviderOpenAI, @[], nil, deltas, &error);
		assert(!error && [out[@"answer"] isEqualToString:@"Xin chào"]);
		assert(deltas.count == 2 && [deltas[0] isEqualToString:@"Xin "] && [deltas[1] isEqualToString:@"chào"]);

		// ── 4. Endpoint không hỗ trợ stream (400) → tự chuyển non-stream.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(400, @{@"error": @{@"message": @"stream unsupported"}});
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{@"message": @{@"content": @"không stream"}}]});
		out = Run(SXProviderOpenAI, @[], nil, nil, &error);
		assert(!error && [out[@"answer"] isEqualToString:@"không stream"]);

		// ── 5. Stream có tool_calls: gộp mảnh arguments, chạy công cụ, rồi trả lời.
		SXMockHTTPReset();
		SXMockHTTPReply(200, SSE(@[
			@"{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_9\",\"function\":{\"name\":\"clock\",\"arguments\":\"\"}}]}}]}",
			@"{\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{}\"}}]}}]}" ]));
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{@"message": @{@"content": @"Đã xong."}}]});
		runs = 0;
		out = Run(SXProviderOpenAI, @[ToolDefinition()], executor, nil, &error);
		assert(!error && runs == 1 && [out[@"answer"] isEqualToString:@"Đã xong."]);
		testStreaming = NO;

		// ── 6. Gemini: functionResponse dùng role user + response là OBJECT.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(200, @{@"candidates": @[@{
			@"content": @{@"parts": @[@{@"functionCall": @{@"name": @"clock", @"args": @{}}}]}}]});
		SXMockHTTPReplyJSON(200, @{@"candidates": @[@{
			@"content": @{@"parts": @[@{@"text": @"12 giờ."}]}}]});
		runs = 0;
		out = Run(SXProviderGemini, @[ToolDefinition()], executor, nil, &error);
		assert(!error && runs == 1 && [out[@"answer"] isEqualToString:@"12 giờ."]);
		NSString *geminiBody = SXMockHTTPRequests()[1][@"body"];
		assert([geminiBody containsString:@"\"functionResponse\""]);
		assert([geminiBody containsString:@"\"role\":\"user\""]);
		assert([geminiBody containsString:@"\"response\":{\"result\":\"12:00\"}"]);
		assert(![geminiBody containsString:@"\"role\":\"tool\""]);

		// ── 7. Lỗi 401 → báo lỗi ngay, không thử lại; thông điệp có nội dung máy chủ.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(401, @{@"error": @{@"message": @"Incorrect API key"}});
		error = nil;
		out = Run(SXProviderOpenAI, @[], nil, nil, &error);
		assert(error && error.code == 401);
		assert([error.localizedDescription containsString:@"Incorrect API key"]);

		// ── 8. 429 rồi 200: thử lại và vẫn thành công.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(429, @{@"error": @{@"message": @"slow down"}});
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{@"message": @{@"content": @"vẫn ổn"}}]});
		out = Run(SXProviderOpenAI, @[], nil, nil, &error);
		assert(!error && [out[@"answer"] isEqualToString:@"vẫn ổn"]);

		// ── 9. Endpoint rỗng trả về → lỗi rõ ràng, không treo.
		SXMockHTTPReset();
		SXMockHTTPReply(200, @"");
		error = nil;
		out = Run(SXProviderOpenAI, @[], nil, nil, &error);
		assert(error && error.code == -3);

		// ── 10. Header tuỳ chỉnh + khóa hợp nhất vào request.
		SXMockHTTPReset();
		SXMockHTTPReplyJSON(200, @{@"choices": @[@{@"message": @{@"content": @"ok"}}]});
		Run(SXProviderOpenAI, @[], nil, nil, &error);
		NSDictionary *sentHeaders = SXMockHTTPRequests().lastObject[@"headers"];
		assert([sentHeaders[@"Authorization"] isEqualToString:@"Bearer sk-test"]);

		// ── 11. Base URL rỗng: báo lỗi cấu hình chứ không âm thầm gửi api.openai.com.
		testBase = @"";
		SXMockHTTPReset();
		error = nil;
		out = Run(SXProviderOpenAI, @[], nil, nil, &error);
		assert(error && [error.localizedDescription containsString:@"Địa chỉ API"]);
		testBase = @"https://mock.test/v1";

		puts("sxllm mock tests: OK");
	}
	return 0;
}
