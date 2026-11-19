#import "SXStream.h"
#import "SXLog.h"
#import "SXHTTP.h"

/// Bộ phân tích SSE chạy theo từng mẩu byte.
///
/// Bản cũ gom toàn bộ thân trả về rồi mới tách dòng, nên "stream" thực chất chỉ
/// là non-stream có thêm một chặng chờ: token đầu tiên đến lúc nào người dùng
/// cũng không thấy. Ở đây mỗi mẩu byte được xử lý ngay khi tới; một dòng chưa
/// hoàn chỉnh được giữ lại (kể cả khi nó bị cắt giữa ký tự UTF-8) để ghép với
/// mẩu sau.
@interface SXSSEParser : NSObject
@property (nonatomic) SXStreamFormat format;
@property (nonatomic, copy, nullable) SXStreamDelta onDelta;
@property (nonatomic, strong) NSMutableString *content;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *geminiCalls;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary *> *partialCalls;
@property (nonatomic) BOOL sawToolCalls;
@property (nonatomic) NSInteger firstTokenMs;
@property (nonatomic, copy, nullable) NSString *errorText;
@end

@implementation SXSSEParser {
	NSMutableData *_lineBuffer;
	CFAbsoluteTime _start;
	BOOL _finished;
}

- (instancetype)initWithFormat:(SXStreamFormat)format onDelta:(SXStreamDelta)onDelta {
	self = [super init];
	if (self) {
		_format = format;
		_onDelta = [onDelta copy];
		_content = [NSMutableString string];
		_geminiCalls = [NSMutableArray array];
		_partialCalls = [NSMutableDictionary dictionary];
		_firstTokenMs = -1;
		_lineBuffer = [NSMutableData data];
		_start = CFAbsoluteTimeGetCurrent();
	}
	return self;
}

- (void)consumeData:(NSData *)data {
	if (_finished || !data.length) return;
	[_lineBuffer appendData:data];
	// Tách theo byte '\n' tại chỗ: dòng có thể kết thúc giữa hai mẩu.
	const uint8_t *bytes = _lineBuffer.bytes;
	NSUInteger length = _lineBuffer.length;
	NSUInteger start = 0;
	for (NSUInteger i = 0; i < length; i++) {
		if (bytes[i] != '\n') continue;
		NSUInteger lineLength = i - start;
		if (lineLength && bytes[i > start ? i - 1 : i] == '\r' && i > start) lineLength--;
		NSData *lineData = [_lineBuffer subdataWithRange:NSMakeRange(start, lineLength)];
		start = i + 1;
		[self consumeLine:lineData];
		if (_finished) break;
	}
	if (start > 0) [_lineBuffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
	if (_finished) [_lineBuffer setLength:0];
}

- (void)finish {
	if (_finished) return;
	if (_lineBuffer.length) {
		NSData *rest = [_lineBuffer copy];
		[_lineBuffer setLength:0];
		[self consumeLine:rest];
	}
	_finished = YES;
}

- (void)consumeLine:(NSData *)lineData {
	if (_finished || !lineData.length) return;
	NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
	if (!line) line = [[NSString alloc] initWithData:lineData encoding:NSISOLatin1StringEncoding];
	if (!line.length) return;
	line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (![line hasPrefix:@"data:"]) return;
	NSString *chunk = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceCharacterSet]];
	if (!chunk.length || [chunk isEqualToString:@"[DONE]"]) return;

	id json = [NSJSONSerialization JSONObjectWithData:[chunk dataUsingEncoding:NSUTF8StringEncoding]
											  options:0 error:NULL];
	if (![json isKindOfClass:[NSDictionary class]]) return;

	if (self.format == SXStreamFormatOpenAI) {
		[self consumeOpenAIChunk:(NSDictionary *)json];
	} else {
		[self consumeGeminiChunk:(NSDictionary *)json];
	}
}

- (void)appendPiece:(NSString *)piece {
	if (!piece.length) return;
	if (_firstTokenMs < 0) {
		_firstTokenMs = (NSInteger)((CFAbsoluteTimeGetCurrent() - _start) * 1000.0);
	}
	[_content appendString:piece];
	if (self.onDelta) self.onDelta(piece, _firstTokenMs);
}

- (void)consumeOpenAIChunk:(NSDictionary *)json {
	id error = json[@"error"];
	if (error && !self.errorText.length) {
		id message = [error isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)error)[@"message"] : error;
		if ([message isKindOfClass:[NSString class]]) self.errorText = message;
	}
	NSArray *choices = [json[@"choices"] isKindOfClass:[NSArray class]] ? json[@"choices"] : nil;
	if (!choices.count || ![choices[0] isKindOfClass:[NSDictionary class]]) return;
	id delta = ((NSDictionary *)choices[0])[@"delta"];
	if (![delta isKindOfClass:[NSDictionary class]]) return;
	NSDictionary *deltaDict = (NSDictionary *)delta;

	NSArray *calls = [deltaDict[@"tool_calls"] isKindOfClass:[NSArray class]] ? deltaDict[@"tool_calls"] : nil;
	if (calls.count) {
		self.sawToolCalls = YES;
		for (id item in calls) {
			if (![item isKindOfClass:[NSDictionary class]]) continue;
			NSDictionary *call = (NSDictionary *)item;
			NSInteger index = [call[@"index"] isKindOfClass:[NSNumber class]]
				? [call[@"index"] integerValue] : (NSInteger)self.partialCalls.count;
			NSMutableDictionary *entry = self.partialCalls[@(index)];
			if (!entry) {
				entry = [@{@"id": @"", @"name": @"", @"arguments": @""} mutableCopy];
				self.partialCalls[@(index)] = entry;
			}
			id identifier = call[@"id"];
			if ([identifier isKindOfClass:[NSString class]] && [identifier length]) entry[@"id"] = identifier;
			id function = call[@"function"];
			if ([function isKindOfClass:[NSDictionary class]]) {
				id name = ((NSDictionary *)function)[@"name"];
				if ([name isKindOfClass:[NSString class]] && [name length]) entry[@"name"] = name;
				id fragment = ((NSDictionary *)function)[@"arguments"];
				if ([fragment isKindOfClass:[NSString class]]) {
					entry[@"arguments"] = [(NSString *)entry[@"arguments"] stringByAppendingString:fragment];
				}
			}
		}
		return;
	}
	id piece = deltaDict[@"content"];
	if ([piece isKindOfClass:[NSString class]]) [self appendPiece:piece];
}

- (void)consumeGeminiChunk:(NSDictionary *)json {
	id error = json[@"error"];
	if (error && !self.errorText.length) {
		id message = [error isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)error)[@"message"] : error;
		if ([message isKindOfClass:[NSString class]]) self.errorText = message;
	}
	NSArray *candidates = [json[@"candidates"] isKindOfClass:[NSArray class]] ? json[@"candidates"] : nil;
	if (!candidates.count || ![candidates[0] isKindOfClass:[NSDictionary class]]) return;
	id content = ((NSDictionary *)candidates[0])[@"content"];
	id parts = [content isKindOfClass:[NSDictionary class]] && [content[@"parts"] isKindOfClass:[NSArray class]]
		? content[@"parts"] : nil;
	for (id part in parts) {
		if (![part isKindOfClass:[NSDictionary class]]) continue;
		id functionCall = ((NSDictionary *)part)[@"functionCall"];
		if ([functionCall isKindOfClass:[NSDictionary class]]) {
			self.sawToolCalls = YES;
			[self.geminiCalls addObject:functionCall];
			continue;
		}
		id piece = ((NSDictionary *)part)[@"text"];
		if ([piece isKindOfClass:[NSString class]]) [self appendPiece:piece];
	}
}

- (NSArray<NSDictionary *> *)orderedToolCalls {
	NSMutableArray<NSDictionary *> *calls = [NSMutableArray array];
	NSArray<NSNumber *> *indexes = [[self.partialCalls allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSNumber *index in indexes) {
		NSDictionary *entry = self.partialCalls[index];
		NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : nil;
		if (!name.length) continue;
		NSString *arguments = [entry[@"arguments"] isKindOfClass:[NSString class]] ? entry[@"arguments"] : @"";
		NSString *identifier = [entry[@"id"] isKindOfClass:[NSString class]] && [entry[@"id"] length]
			? entry[@"id"] : name;
		[calls addObject:@{
			@"id": identifier,
			@"type": @"function",
			@"function": @{@"name": name, @"arguments": arguments.length ? arguments : @"{}"},
		}];
	}
	return calls;
}

@end

@implementation SXStream

+ (NSDictionary *)postJSON:(NSDictionary *)body
					 toURL:(NSString *)urlString
				   headers:(NSDictionary<NSString *, NSString *> *)headers
					format:(SXStreamFormat)format
				   timeout:(NSTimeInterval)timeoutSeconds
			   idleTimeout:(NSTimeInterval)idleTimeout
				   onDelta:(SXStreamDelta)onDelta
					 error:(NSError **)outErr {
	SXSSEParser *parser = [[SXSSEParser alloc] initWithFormat:format onDelta:onDelta];
	NSMutableData *errorBody = [NSMutableData data];
	__block NSInteger status = 0;

	NSMutableDictionary<NSString *, NSString *> *requestHeaders = [headers mutableCopy]
		?: [NSMutableDictionary dictionary];
	requestHeaders[@"Accept"] = @"text/event-stream";

	SXHTTPResult *result = [SXHTTP postURL:urlString
									  body:body
								   headers:requestHeaders
								   timeout:timeoutSeconds
							   idleTimeout:idleTimeout
								  onStatus:^(NSInteger code) {
		status = code;
	}
									onData:^BOOL(NSData *data) {
		// Lỗi HTTP: gom thân để lấy thông điệp giải thích (thường là một JSON).
		if (status >= 400) {
			if (errorBody.length < 64 * 1024) [errorBody appendData:data];
			return YES;
		}
		[parser consumeData:data];
		return YES;
	}];
	[parser finish];

	if (result.error && result.status == 0) {
		if (outErr) *outErr = result.error;
		return nil;
	}
	if (result.status < 200 || result.status >= 300) {
		// Mã lỗi thật → trả về cho SXLLM quyết định (retry/fallback/báo lỗi).
		NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{
			@"content": [parser.content copy] ?: @"",
			@"sawToolCalls": @(parser.sawToolCalls),
			@"status": @(result.status),
			@"firstTokenMs": @(parser.firstTokenMs),
			@"toolCalls": [NSArray array],
			@"functionCalls": [NSArray array],
		}];
		NSString *text = errorBody.length && parser.errorText.length == 0
			? [[NSString alloc] initWithData:errorBody encoding:NSUTF8StringEncoding] : nil;
		NSString *finalError = parser.errorText.length ? parser.errorText : text;
		if (finalError.length) response[@"errorText"] = finalError;
		return response;
	}

	NSDictionary *response = @{
		@"content": [parser.content copy] ?: @"",
		@"sawToolCalls": @(parser.sawToolCalls),
		@"status": @(result.status),
		@"firstTokenMs": @(parser.firstTokenMs),
		@"toolCalls": [parser orderedToolCalls],
		@"functionCalls": parser.geminiCalls ?: @[],
	};
	return response;
}

@end
