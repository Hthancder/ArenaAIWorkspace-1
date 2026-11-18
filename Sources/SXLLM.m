#import "SXLLM.h"
#import "SXPrefs.h"
#import "SXLog.h"
#import "SXStream.h"

static NSDictionary *SXHTTPPost(NSString *url, NSDictionary *body, NSDictionary *headers, SXRequest *request, NSError **error) {
	NSMutableURLRequest *post = SXJSONRequest(url, body, headers);
	if (!post) {
		if (error) *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:@{NSLocalizedDescriptionKey: @"Địa chỉ API HTTPS không hợp lệ."}];
		return nil;
	}
	return SXHTTP(post, request, 512 * 1024, error);
}

static NSError *SXHTTPError(NSInteger status) {
	return [NSError errorWithDomain:@"com.sirix.llm" code:status userInfo:@{NSLocalizedDescriptionKey:
		[NSString stringWithFormat:@"Máy chủ AI trả HTTP %ld.", (long)status]}];
}

static NSDictionary *SXInfo(NSString *provider, NSString *model, NSInteger status,
							NSInteger rounds, CFAbsoluteTime start) {
	return @{@"provider": provider, @"model": model, @"status": @(status),
			 @"rounds": @(rounds), @"ms": @((NSInteger)((CFAbsoluteTimeGetCurrent() - start) * 1000))};
}

static NSError *SXErr(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:@"com.sirix.llm" code:code
						   userInfo:@{NSLocalizedDescriptionKey: message}];
}

// Retry giới hạn theo từng vòng HTTP, chỉ với 429/5xx; không chạy lại tool.
static BOOL SXRetryHTTP(NSInteger status, NSInteger *attempt, SXRequest *request) {
	if (!((status == 429) || (status >= 500 && status < 600)) || *attempt >= 2) return NO;
	NSTimeInterval delay = *attempt == 0 ? 0.5 : 1.5;
	(*attempt)++;
	SXLogWrn(@"llm", @"HTTP %ld — thử lại %ld/2 sau %.1fs", (long)status, (long)*attempt, delay);
	return [request waitForDelay:delay];
}

#pragma mark - OpenAI tương thích

static void SXAskOpenAI(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
						NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
						NSString *overrideModel, NSString *prompt, NSUInteger maxTokens,
						SXRequest *request, SXStreamProgress progress, SXLLMCompletion completion) {
	NSString *key = [prefs.openaiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *model = overrideModel ?: [prefs.openaiModel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!model.length) model = @"gpt-4o-mini";
	NSString *base = prefs.activeBaseURL;
	NSString *url = SXEndpoint(base, @"/chat/completions");
	NSMutableArray *messages = [NSMutableArray array];
	[messages addObject:@{@"role": @"system", @"content": (prompt ?: prefs.systemPrompt)}];
	for (NSDictionary *turn in history) {
		NSString *q = [turn[@"q"] isKindOfClass:[NSString class]] ? turn[@"q"] : nil;
		NSString *a = [turn[@"a"] isKindOfClass:[NSString class]] ? turn[@"a"] : nil;
		if (q.length) [messages addObject:@{@"role": @"user", @"content": q}];
		if (a.length) [messages addObject:@{@"role": @"assistant", @"content": a}];
	}
	[messages addObject:@{@"role": @"user", @"content": question}];

	NSMutableArray *toolsPayload = [NSMutableArray array];
	for (NSDictionary *def in toolDefs) {
		[toolsPayload addObject:@{@"type": @"function", @"function": @{
			@"name": def[@"name"] ?: @"",
			@"description": def[@"description"] ?: @"",
			@"parameters": def[@"parameters"] ?: @{@"type": @"object", @"properties": @{}},
		}}];
	}

	SXLogDbg(@"llm", @"openai → POST (%lu message, %lu tool, temp=%.1f)",
			 (unsigned long)messages.count,
			 (unsigned long)toolsPayload.count, prefs.temperature);

	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL forceNonStream = !prefs.streaming || maxTokens > 0;
	NSSet *allowedTools = [NSSet setWithArray:[toolDefs valueForKey:@"name"]];

	while (YES) {
		if (request.remaining <= 0) { completion(nil, SXRequestError(request), nil); return; }
		NSMutableDictionary *body = [@{
			@"model": model,
			@"messages": messages,
			@"temperature": @(prefs.temperature),
		} mutableCopy];
		if (maxTokens) body[@"max_tokens"] = @(maxTokens);
		if (toolsPayload.count) body[@"tools"] = toolsPayload;

		// ---- Streaming (SSE): vòng đầu; nếu model trả tool_calls / rỗng / endpoint
		// không hỗ trợ → chuyển non-stream cho vòng này và các vòng sau ----
		if (!forceNonStream) {
			NSMutableDictionary *streamBody = [body mutableCopy];
			streamBody[@"stream"] = @YES;
			NSError *streamError = nil;
			NSDictionary *streamResp = [SXStream postJSON:streamBody
													 toURL:url
												   headers:@{@"Authorization":
														[NSString stringWithFormat:@"Bearer %@", key]}
													 format:SXStreamFormatOpenAI
													  request:request progress:progress
											  error:&streamError];
			if (!streamResp) {
				if (request.remaining <= 0 || streamError.code == NSURLErrorNotConnectedToInternet || streamError.code == NSURLErrorTimedOut) {
					completion(nil, (request.remaining <= 0 ? SXRequestError(request) : streamError), nil); return;
				}
				// Lỗi transport/hết giờ trên SSE → thử non-stream một lần
				// (nhiều proxy nhận POST thường nhưng treo SSE). Non-stream lỗi → báo lỗi như cũ.
				SXLogWrn(@"llm", @"openai stream lỗi (%ld) → thử non-stream", (long)streamError.code);
				forceNonStream = YES;
				continue;
			}
			NSInteger streamStatus = [streamResp[@"status"] integerValue];
			if (streamStatus >= 200 && streamStatus < 300) {
				if ([streamResp[@"sawToolCalls"] boolValue]) {
					SXLogDbg(@"llm", @"stream báo tool_calls → non-stream vòng %ld", (long)(rounds + 1));
					forceNonStream = YES;
				} else {
					NSString *streamed = [streamResp[@"content"] isKindOfClass:[NSString class]]
						? streamResp[@"content"] : nil;
					if (streamed.length) {
						NSInteger ft = [streamResp[@"firstTokenMs"] integerValue];
						NSDictionary *info = SXInfo(@"openai", model, streamStatus, rounds, start);
						SXLogInf(@"llm", @"openai OK (stream) — first-token %ld ms · tổng %ld ms · %lu ký tự",
								 (long)ft, (long)[info[@"ms"] integerValue], (unsigned long)streamed.length);
						completion(streamed, nil, info);
						return;
					}
					forceNonStream = YES; // stream “thành công” nhưng rỗng → thử non-stream
				}
			} else if (streamStatus != 501 && SXRetryHTTP(streamStatus, &retryCount, request)) {
				continue;
			} else if (streamStatus == 400 || streamStatus == 404 || streamStatus == 405 || streamStatus == 415 || streamStatus == 501) {
				SXLogWrn(@"llm", @"endpoint không hỗ trợ stream (HTTP %ld) → non-stream", (long)streamStatus);
				forceNonStream = YES;
			} else {
				NSError *err = SXHTTPError(streamStatus);
				SXLogErr(@"llm", @"openai stream HTTP %ld: %@", (long)streamStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"openai", model, streamStatus, rounds, start));
				return;
			}
		}

		NSError *postError = nil;
		NSDictionary *resp = SXHTTPPost(url, body, @{
			@"Authorization": [NSString stringWithFormat:@"Bearer %@", key],
		}, request, &postError);
		if (!resp) {
			SXLogErr(@"llm", @"openai lỗi mạng: %ld", (long)postError.code);
			completion(nil, postError, SXInfo(@"openai", model, 0, rounds, start));
			return;
		}
		lastStatus = [resp[@"status"] integerValue];
		NSData *data = resp[@"data"];
		if (lastStatus < 200 || lastStatus >= 300) {
			if (SXRetryHTTP(lastStatus, &retryCount, request)) continue;
			NSError *err = SXHTTPError(lastStatus);
			SXLogErr(@"llm", @"openai HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
			completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}

		id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		NSDictionary *choice = nil;
		if ([json isKindOfClass:[NSDictionary class]]) {
			id choices = json[@"choices"];
			if ([choices isKindOfClass:[NSArray class]] && [choices count]) {
				id first = choices[0];
				if ([first isKindOfClass:[NSDictionary class]]) choice = first[@"message"];
			}
		}
		if (![choice isKindOfClass:[NSDictionary class]]) {
			NSError *err = SXErr(-3, @"Phản hồi của AI không hợp lệ.");
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}

		NSString *content = [choice[@"content"] isKindOfClass:[NSString class]] ? choice[@"content"] : nil;
		id toolCalls = choice[@"tool_calls"];

		if ([toolCalls isKindOfClass:[NSArray class]] && [toolCalls count] && executor && rounds < prefs.maxToolRounds) {
			rounds++;
			retryCount = 0;
			NSMutableDictionary *assistantMsg = [@{@"role": @"assistant"} mutableCopy];
			assistantMsg[@"content"] = content ?: [NSNull null];
			assistantMsg[@"tool_calls"] = toolCalls;
			[messages addObject:assistantMsg];

			for (NSDictionary *call in toolCalls) {
				if (![call isKindOfClass:[NSDictionary class]]) continue;
				NSString *name = [call[@"function"] isKindOfClass:[NSDictionary class]] ? call[@"function"][@"name"] : nil;
				NSString *argsString = [call[@"function"] isKindOfClass:[NSDictionary class]] ? call[@"function"][@"arguments"] : nil;
				NSString *callId = [call[@"id"] isKindOfClass:[NSString class]] ? call[@"id"] : (name ?: @"");
				if (![name isKindOfClass:[NSString class]]) continue;

				NSDictionary *args = @{};
				if ([argsString isKindOfClass:[NSString class]] && argsString.length) {
					id parsed = [NSJSONSerialization JSONObjectWithData:[argsString dataUsingEncoding:NSUTF8StringEncoding]
															   options:0 error:NULL];
					if ([parsed isKindOfClass:[NSDictionary class]]) args = parsed;
				}
				NSError *toolError = nil;
				if (request.remaining <= 0) { completion(nil, SXRequestError(request), nil); return; }
				NSDictionary *toolResult = [allowedTools containsObject:name] ? executor(name, args, &toolError) : nil;
				if (!toolResult && !toolError) toolError = SXErr(-9, @"Công cụ không được phép hoặc đã tắt.");
				NSString *resultText = toolError
					? [@"Lỗi công cụ: " stringByAppendingString:toolError.localizedDescription]
					: ([toolResult[@"result"] isKindOfClass:[NSString class]] ? toolResult[@"result"] : @"Đã thực hiện xong.");
				SXLogDbg(@"llm", @"round %ld: tool ok=%d", (long)rounds, toolError == nil);
				[messages addObject:@{@"role": @"tool", @"tool_call_id": callId, @"content": resultText}];
			}
			continue;
		}

		if (![content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
			NSError *err = SXErr(-6, @"AI không trả lời." );
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}
		NSDictionary *info = SXInfo(@"openai", model, lastStatus, rounds, start);
		SXLogInf(@"llm", @"openai OK — %ld ms, %ld round, trả lời %lu ký tự",
				 (long)[info[@"ms"] integerValue], (long)rounds, (unsigned long)content.length);
		completion(content, nil, info);
		return;
	}
}

#pragma mark - Gemini

/// JSON schema (lowercase) → Schema của Gemini (type IN HOA).
static id SXGeminiSchema(id node) {
	if ([node isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[node count]];
		for (NSString *key in node) {
			id value = node[key];
			if ([key isEqualToString:@"type"] && [value isKindOfClass:[NSString class]]) {
				out[key] = [(NSString *)value uppercaseString];
			} else {
				out[key] = SXGeminiSchema(value);
			}
		}
		return out;
	}
	if ([node isKindOfClass:[NSArray class]]) {
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:[node count]];
		for (id item in node) [out addObject:SXGeminiSchema(item)];
		return out;
	}
	return node;
}

static void SXAskGemini(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
						NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
						NSString *overrideModel, NSString *prompt, NSUInteger maxTokens,
						SXRequest *request, SXStreamProgress progress, SXLLMCompletion completion) {
	NSString *key = [prefs.geminiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *model = overrideModel ?: [prefs.geminiModel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!model.length) model = @"gemini-2.0-flash";
	NSString *url = SXGeminiEndpoint(model, NO);
	NSString *streamURL = SXGeminiEndpoint(model, YES);
	if (!url || !streamURL) { completion(nil, SXErr(-1, @"Tên mô hình Gemini không hợp lệ."), nil); return; }

	NSMutableArray *contents = [NSMutableArray array];
	for (NSDictionary *turn in history) {
		NSString *q = [turn[@"q"] isKindOfClass:[NSString class]] ? turn[@"q"] : nil;
		NSString *a = [turn[@"a"] isKindOfClass:[NSString class]] ? turn[@"a"] : nil;
		if (q.length) [contents addObject:@{@"role": @"user", @"parts": @[@{@"text": q}]}];
		if (a.length) [contents addObject:@{@"role": @"model", @"parts": @[@{@"text": a}]}];
	}
	[contents addObject:@{@"role": @"user", @"parts": @[@{@"text": question}]}];

	SXLogDbg(@"llm", @"gemini → POST (%lu message, %lu tool, temp=%.1f)",
			 (unsigned long)contents.count,
			 (unsigned long)toolDefs.count, prefs.temperature);

	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL forceNonStream = !prefs.streaming || maxTokens > 0;
	NSSet *allowedTools = [NSSet setWithArray:[toolDefs valueForKey:@"name"]];

	while (YES) {
		if (request.remaining <= 0) { completion(nil, SXRequestError(request), nil); return; }
		NSMutableDictionary *body = [@{
			@"contents": contents,
			@"systemInstruction": @{@"parts": @[@{@"text": (prompt ?: prefs.systemPrompt)}]},
			@"generationConfig": maxTokens ? @{@"temperature": @0.0, @"maxOutputTokens": @(maxTokens)} : @{@"temperature": @(prefs.temperature)},
		} mutableCopy];
		if (toolDefs.count) {
			NSMutableArray *decls = [NSMutableArray array];
			for (NSDictionary *def in toolDefs) {
				[decls addObject:@{
					@"name": def[@"name"] ?: @"",
					@"description": def[@"description"] ?: @"",
					@"parameters": SXGeminiSchema(def[@"parameters"] ?: @{@"type": @"object", @"properties": @{}}),
				}];
			}
			body[@"tools"] = @[@{@"functionDeclarations": decls}];
		}

		// ---- Streaming (SSE) — như nhánh OpenAI ----
		if (!forceNonStream) {
			NSError *streamError = nil;
			NSDictionary *streamResp = [SXStream postJSON:body
													 toURL:streamURL
												   headers:@{@"x-goog-api-key": key}
													 format:SXStreamFormatGemini
													  request:request progress:progress
											  error:&streamError];
			if (!streamResp) {
				if (request.remaining <= 0 || streamError.code == NSURLErrorNotConnectedToInternet || streamError.code == NSURLErrorTimedOut) {
					completion(nil, (request.remaining <= 0 ? SXRequestError(request) : streamError), nil); return;
				}
				// Như nhánh OpenAI: SSE lỗi/treo → fallback non-stream.
				SXLogWrn(@"llm", @"gemini stream lỗi (%ld) → thử non-stream", (long)streamError.code);
				forceNonStream = YES;
				continue;
			}
			NSInteger streamStatus = [streamResp[@"status"] integerValue];
			if (streamStatus >= 200 && streamStatus < 300) {
				if ([streamResp[@"sawToolCalls"] boolValue]) {
					SXLogDbg(@"llm", @"stream báo functionCall → non-stream vòng %ld", (long)(rounds + 1));
					forceNonStream = YES;
				} else {
					NSString *streamed = [streamResp[@"content"] isKindOfClass:[NSString class]]
						? streamResp[@"content"] : nil;
					if (streamed.length) {
						NSInteger ft = [streamResp[@"firstTokenMs"] integerValue];
						NSDictionary *info = SXInfo(@"gemini", model, streamStatus, rounds, start);
						SXLogInf(@"llm", @"gemini OK (stream) — first-token %ld ms · tổng %ld ms · %lu ký tự",
								 (long)ft, (long)[info[@"ms"] integerValue], (unsigned long)streamed.length);
						completion(streamed, nil, info);
						return;
					}
					forceNonStream = YES;
				}
			} else if (streamStatus != 501 && SXRetryHTTP(streamStatus, &retryCount, request)) {
				continue;
			} else if (streamStatus == 400 || streamStatus == 404 || streamStatus == 405 || streamStatus == 415 || streamStatus == 501) {
				SXLogWrn(@"llm", @"gemini stream không khả dụng (HTTP %ld) → non-stream", (long)streamStatus);
				forceNonStream = YES;
			} else {
				NSError *err = SXHTTPError(streamStatus);
				SXLogErr(@"llm", @"gemini stream HTTP %ld: %@", (long)streamStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, streamStatus, rounds, start));
				return;
			}
		}

		NSError *postError = nil;
		NSDictionary *resp = SXHTTPPost(url, body, @{@"x-goog-api-key": key}, request, &postError);
		if (!resp) {
			SXLogErr(@"llm", @"gemini lỗi mạng: %ld", (long)postError.code);
			completion(nil, postError, SXInfo(@"gemini", model, 0, rounds, start));
			return;
		}
		lastStatus = [resp[@"status"] integerValue];
		NSData *data = resp[@"data"];
		if (lastStatus < 200 || lastStatus >= 300) {
			if (SXRetryHTTP(lastStatus, &retryCount, request)) continue;
			NSError *err = SXHTTPError(lastStatus);
			SXLogErr(@"llm", @"gemini HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
			completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}

		id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		NSDictionary *candidate = nil;
		if ([json isKindOfClass:[NSDictionary class]]) {
			id candidates = json[@"candidates"];
			if ([candidates isKindOfClass:[NSArray class]] && [candidates count] && [candidates[0] isKindOfClass:[NSDictionary class]]) {
				candidate = candidates[0];
			} else {
				NSError *err = SXErr(-5, @"Provider không cho phép câu trả lời này.");
				SXLogWrn(@"llm", @"%@", err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
				return;
			}
		}
		if (!candidate) {
			NSError *err = SXErr(-3, @"Phản hồi của AI không hợp lệ.");
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}

		id contentObj = candidate[@"content"];
		NSArray *parts = [contentObj isKindOfClass:[NSDictionary class]] && [contentObj[@"parts"] isKindOfClass:[NSArray class]]
			? contentObj[@"parts"] : @[];

		NSMutableString *text = [NSMutableString string];
		NSMutableArray *functionCalls = [NSMutableArray array];
		for (id part in parts) {
			if (![part isKindOfClass:[NSDictionary class]]) continue;
			if ([part[@"text"] isKindOfClass:[NSString class]] && ![part[@"thought"] isEqual:@YES]) [text appendString:part[@"text"]];
			if ([part[@"functionCall"] isKindOfClass:[NSDictionary class]]) [functionCalls addObject:part[@"functionCall"]];
		}

		if (functionCalls.count && executor && rounds < prefs.maxToolRounds) {
			rounds++;
			retryCount = 0;
			[contents addObject:@{@"role": @"model", @"parts": parts}];
			for (NSDictionary *call in functionCalls) {
				NSString *name = [call[@"name"] isKindOfClass:[NSString class]] ? call[@"name"] : nil;
				if (!name) continue;
				NSDictionary *args = [call[@"args"] isKindOfClass:[NSDictionary class]] ? call[@"args"] : @{};
				NSError *toolError = nil;
				if (request.remaining <= 0) { completion(nil, SXRequestError(request), nil); return; }
				NSDictionary *toolResult = [allowedTools containsObject:name] ? executor(name, args, &toolError) : nil;
				if (!toolResult && !toolError) toolError = SXErr(-9, @"Công cụ không được phép hoặc đã tắt.");
				NSString *resultText = toolError
					? [@"Lỗi công cụ: " stringByAppendingString:toolError.localizedDescription]
					: ([toolResult[@"result"] isKindOfClass:[NSString class]] ? toolResult[@"result"] : @"Đã thực hiện xong.");
				SXLogDbg(@"llm", @"round %ld: tool ok=%d", (long)rounds, toolError == nil);
				[contents addObject:@{@"role": @"tool", @"parts": @[@{@"functionResponse": @{
					@"name": name,
					@"response": @{@"result": resultText},
				}}]}];
			}
			continue;
		}

		if (![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
			NSError *err = SXErr(-6, @"AI không trả lời." );
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}
		NSString *answer = [text copy];
		NSDictionary *info = SXInfo(@"gemini", model, lastStatus, rounds, start);
		SXLogInf(@"llm", @"gemini OK — %ld ms, %ld round, trả lời %lu ký tự",
				 (long)[info[@"ms"] integerValue], (long)rounds, (unsigned long)answer.length);
		completion(answer, nil, info);
		return;
	}
}

#pragma mark - Điểm vào

@implementation SXLLM

+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)tools
			executor:(SXToolExec)executor
		 completion:(SXLLMCompletion)completion {
	[self askQuestion:question history:history tools:tools executor:executor
			 provider:[SXPrefs shared].provider completion:completion];
}

+ (void)askQuestion:(NSString *)question
            history:(NSArray<NSDictionary *> *)history
              tools:(NSArray<NSDictionary *> *)tools
           executor:(SXToolExec)executor
           provider:(SXProvider)provider
         completion:(SXLLMCompletion)completion {
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	[self performQuestion:question history:history tools:tools executor:executor prefs:prefs provider:provider
		model:nil prompt:nil maxTokens:0 request:[[SXRequest alloc] initWithTimeout:30 firstOutput:prefs.responseTimeout] progress:nil completion:completion];
}

+ (void)performQuestion:(NSString *)question history:(NSArray *)history tools:(NSArray *)toolDefs executor:(SXToolExec)executor
	prefs:(SXPrefs *)prefs provider:(SXProvider)provider model:(NSString *)model prompt:(NSString *)prompt maxTokens:(NSUInteger)maxTokens
	request:(SXRequest *)request progress:(SXStreamProgress)progress completion:(SXLLMCompletion)completion {
	if (prefs.localOnly || request.cancelled) { completion(nil, SXErr(-1002, @"SiriX đang không gửi yêu cầu mạng."), nil); return; }
	if (SXDefinitelyOffline()) { completion(nil, SXErr(-1003, @"Không có mạng — SiriX không gọi được AI."), nil); return; }
	NSString *key = [(provider == SXProviderGemini ? prefs.geminiKey : prefs.openaiKey)
		stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

	if (!key.length) {
		NSString *providerName = provider == SXProviderGemini ? @"Gemini" : @"OpenAI tương thích";
		NSError *err = SXErr(-1000, [NSString stringWithFormat:
			@"Chưa đặt khóa API cho %@. Mở Cài đặt → SiriX → Cấu hình OpenAI / Cấu hình Gemini rồi dán khóa.", providerName]);
		SXLogWrn(@"llm", @"bỏ yêu cầu — %@", err.localizedDescription);
		completion(nil, err, nil);
		return;
	}
	if (!question.length) {
		completion(nil, SXErr(-1001, @"Câu hỏi rỗng."), nil);
		return;
	}

	if (provider == SXProviderGemini) {
		SXAskGemini(prefs, question, history, toolDefs, executor, model, prompt, maxTokens, request, progress, completion);
	} else {
		SXAskOpenAI(prefs, question, history, toolDefs, executor, model, prompt, maxTokens, request, progress, completion);
	}
}

@end
