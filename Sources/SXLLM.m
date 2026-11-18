#import "SXLLM.h"
#import "SXPrefs.h"
#import "SXLog.h"
#import "SXStream.h"

static const NSTimeInterval kSXHTTPTimeout = 60;

#pragma mark - HTTP

/// POST JSON → @{ @"status": NSNumber, @"data": NSData } ; lỗi mạng → *outErr.
static NSDictionary *SXHTTPPost(NSString *urlString,
								NSDictionary *body,
								NSDictionary<NSString *, NSString *> *headers,
								NSError **outErr) {
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
	request.timeoutInterval = kSXHTTPTimeout;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"SiriX/%@", SX_VERSION] forHTTPHeaderField:@"User-Agent"];
	[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		[request setValue:value forHTTPHeaderField:key];
	}];

	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block NSData *data = nil;
	__block NSInteger status = 0;
	__block NSError *sessionError = nil;
	[[[NSURLSession sharedSession] dataTaskWithRequest:request
									completionHandler:^(NSData *d, NSURLResponse *response, NSError *err) {
		data = d;
		status = [(NSHTTPURLResponse *)response statusCode];
		sessionError = err;
		dispatch_semaphore_signal(sem);
	}] resume];
	long waitResult = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSXHTTPTimeout * NSEC_PER_SEC)));

	if (sessionError) {
		if (outErr) *outErr = sessionError;
		return nil;
	}
	if (waitResult != 0) {
		// Không có response trong 60s: báo đúng là hết giờ, không phải "HTTP 0".
		if (outErr) *outErr = [NSError errorWithDomain:@"com.sirix.llm" code:-1004
			userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
				@"Máy chủ không phản hồi trong %.0f giây. Kiểm tra mạng hoặc endpoint.", kSXHTTPTimeout]}];
		return nil;
	}
	return @{@"status": @(status), @"data": data ?: [NSData data]};
}

static NSString *SXSnippet(NSData *data, NSUInteger max) {
	NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
	if (s.length > max) s = [[s substringToIndex:max] stringByAppendingString:@"…"];
	return s;
}

static NSError *SXHTTPError(NSInteger status, NSData *data) {
	NSString *detail = nil;
	id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
	if ([json isKindOfClass:[NSDictionary class]]) {
		id errObj = json[@"error"];
		if ([errObj isKindOfClass:[NSDictionary class]]) {
			id msg = errObj[@"message"];
			if ([msg isKindOfClass:[NSString class]]) detail = msg;
		} else if ([errObj isKindOfClass:[NSString class]]) {
			detail = errObj;
		}
	}
	if (!detail.length) detail = SXSnippet(data, 300) ?: @"(không có nội dung)";
	return [NSError errorWithDomain:@"com.sirix.llm" code:status
						   userInfo:@{NSLocalizedDescriptionKey:
									  [NSString stringWithFormat:@"Máy chủ trả về HTTP %ld: %@", (long)status, detail]}];
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
static BOOL SXRetryHTTP(NSInteger status, NSInteger *attempt) {
	if (!((status == 429) || (status >= 500 && status < 600)) || *attempt >= 2) return NO;
	NSTimeInterval delay = *attempt == 0 ? 0.5 : 1.5;
	(*attempt)++;
	SXLogWrn(@"llm", @"HTTP %ld — thử lại %ld/2 sau %.1fs", (long)status, (long)*attempt, delay);
	[NSThread sleepForTimeInterval:delay]; // chạy trên luồng network, không phải luồng ACE/UI
	return YES;
}

#pragma mark - OpenAI tương thích

static void SXAskOpenAI(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
						NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
						SXLLMCompletion completion) {
	NSString *key = [prefs.openaiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *model = [prefs.openaiModel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!model.length) model = @"gpt-4o-mini";
	NSString *rawBase = [prefs.openaiBase stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *base = [SXPrefs normalizedBaseURL:rawBase];
	if (!base.length) {
		// Không bao giờ âm thầm rơi về api.openai.com khi người dùng đã nhập một địa chỉ sai:
		// làm vậy sẽ gửi khóa của họ tới máy chủ không mong muốn.
		NSString *message = rawBase.length
			? [NSString stringWithFormat:@"Địa chỉ API không hợp lệ: %@", rawBase]
			: @"Chưa đặt địa chỉ API. Mở Cấu hình OpenAI để nhập endpoint.";
		SXLogErr(@"llm", @"%@", message);
		completion(nil, SXErr(-1003, message), nil);
		return;
	}
	NSString *url = [base hasSuffix:@"/chat/completions"] ? base : [base stringByAppendingString:@"/chat/completions"];
	NSMutableArray *messages = [NSMutableArray array];
	[messages addObject:@{@"role": @"system", @"content": prefs.systemPrompt}];
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

	SXLogDbg(@"llm", @"openai → POST %@ (model=%@, %lu message, %lu tool, temp=%.1f)",
			 url, model, (unsigned long)messages.count,
			 (unsigned long)toolsPayload.count, prefs.temperature);

	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL forceNonStream = !prefs.streaming;

	while (YES) {
		NSMutableDictionary *body = [@{
			@"model": model,
			@"messages": messages,
			@"temperature": @(prefs.temperature),
		} mutableCopy];
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
													  error:&streamError];
			if (!streamResp) {
				// Lỗi transport/hết giờ trên SSE → thử non-stream một lần
				// (nhiều proxy nhận POST thường nhưng treo SSE). Non-stream lỗi → báo lỗi như cũ.
				SXLogWrn(@"llm", @"openai stream lỗi (%@) → thử non-stream", streamError.localizedDescription);
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
			} else if (streamStatus != 501 && SXRetryHTTP(streamStatus, &retryCount)) {
				continue;
			} else if (streamStatus == 400 || streamStatus == 404 || streamStatus == 405 || streamStatus == 415 || streamStatus == 501) {
				SXLogWrn(@"llm", @"endpoint không hỗ trợ stream (HTTP %ld) → non-stream", (long)streamStatus);
				forceNonStream = YES;
			} else {
				NSString *errorText = [streamResp[@"errorText"] isKindOfClass:[NSString class]]
					? streamResp[@"errorText"] : nil;
				NSData *errData = [errorText dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
				NSError *err = SXHTTPError(streamStatus, errData);
				SXLogErr(@"llm", @"openai stream HTTP %ld: %@", (long)streamStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"openai", model, streamStatus, rounds, start));
				return;
			}
		}

		NSError *postError = nil;
		NSDictionary *resp = SXHTTPPost(url, body, @{
			@"Authorization": [NSString stringWithFormat:@"Bearer %@", key],
		}, &postError);
		if (!resp) {
			SXLogErr(@"llm", @"openai lỗi mạng: %@", postError.localizedDescription);
			completion(nil, postError, SXInfo(@"openai", model, 0, rounds, start));
			return;
		}
		lastStatus = [resp[@"status"] integerValue];
		NSData *data = resp[@"data"];
		if (lastStatus < 200 || lastStatus >= 300) {
			if (SXRetryHTTP(lastStatus, &retryCount)) continue;
			NSError *err = SXHTTPError(lastStatus, data);
			SXLogErr(@"llm", @"openai HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
			completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}
		retryCount = 0; // request thành công → trả lại ngân sách retry cho vòng sau

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
			NSError *err = SXErr(-3, [NSString stringWithFormat:@"Phản hồi không hợp lệ: %@", SXSnippet(data, 200)]);
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
				NSDictionary *toolResult = executor(name, args, &toolError);
				NSString *resultText = toolError
					? [@"Lỗi công cụ: " stringByAppendingString:toolError.localizedDescription]
					: ([toolResult[@"result"] isKindOfClass:[NSString class]] ? toolResult[@"result"] : @"Đã thực hiện xong.");
				SXLogDbg(@"llm", @"round %ld: tool %@ → %@", (long)rounds, name, SXShort(resultText, 160));
				[messages addObject:@{@"role": @"tool", @"tool_call_id": callId, @"content": resultText}];
			}
			continue;
		}

		if (!content.length) {
			NSError *err = SXErr(-4, @"Model trả về nội dung rỗng.");
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
						SXLLMCompletion completion) {
	NSString *key = [prefs.geminiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *model = [prefs.geminiModel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!model.length) model = @"gemini-2.0-flash";
	if ([model hasPrefix:@"models/"]) model = [model substringFromIndex:7];
	NSString *url = [NSString stringWithFormat:
		@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent", model];
	NSString *streamURL = [NSString stringWithFormat:
		@"https://generativelanguage.googleapis.com/v1beta/models/%@:streamGenerateContent?alt=sse", model];

	NSMutableArray *contents = [NSMutableArray array];
	for (NSDictionary *turn in history) {
		NSString *q = [turn[@"q"] isKindOfClass:[NSString class]] ? turn[@"q"] : nil;
		NSString *a = [turn[@"a"] isKindOfClass:[NSString class]] ? turn[@"a"] : nil;
		if (q.length) [contents addObject:@{@"role": @"user", @"parts": @[@{@"text": q}]}];
		if (a.length) [contents addObject:@{@"role": @"model", @"parts": @[@{@"text": a}]}];
	}
	[contents addObject:@{@"role": @"user", @"parts": @[@{@"text": question}]}];

	SXLogDbg(@"llm", @"gemini → POST models/%@ (%lu message, %lu tool, temp=%.1f)",
			 model, (unsigned long)contents.count,
			 (unsigned long)toolDefs.count, prefs.temperature);

	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL forceNonStream = !prefs.streaming;

	while (YES) {
		NSMutableDictionary *body = [@{
			@"contents": contents,
			@"systemInstruction": @{@"parts": @[@{@"text": prefs.systemPrompt}]},
			@"generationConfig": @{@"temperature": @(prefs.temperature)},
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
			body[@"tools"] = @{@"functionDeclarations": decls};
		}

		// ---- Streaming (SSE) — như nhánh OpenAI ----
		if (!forceNonStream) {
			NSError *streamError = nil;
			NSDictionary *streamResp = [SXStream postJSON:body
													 toURL:streamURL
												   headers:@{@"x-goog-api-key": key}
													 format:SXStreamFormatGemini
													  error:&streamError];
			if (!streamResp) {
				// Như nhánh OpenAI: SSE lỗi/treo → fallback non-stream.
				SXLogWrn(@"llm", @"gemini stream lỗi (%@) → thử non-stream", streamError.localizedDescription);
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
			} else if (streamStatus != 501 && SXRetryHTTP(streamStatus, &retryCount)) {
				continue;
			} else if (streamStatus == 400 || streamStatus == 404 || streamStatus == 405 || streamStatus == 415 || streamStatus == 501) {
				SXLogWrn(@"llm", @"gemini stream không khả dụng (HTTP %ld) → non-stream", (long)streamStatus);
				forceNonStream = YES;
			} else {
				NSString *errorText = [streamResp[@"errorText"] isKindOfClass:[NSString class]]
					? streamResp[@"errorText"] : nil;
				NSData *errData = [errorText dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
				NSError *err = SXHTTPError(streamStatus, errData);
				SXLogErr(@"llm", @"gemini stream HTTP %ld: %@", (long)streamStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, streamStatus, rounds, start));
				return;
			}
		}

		NSError *postError = nil;
		NSDictionary *resp = SXHTTPPost(url, body, @{@"x-goog-api-key": key}, &postError);
		if (!resp) {
			SXLogErr(@"llm", @"gemini lỗi mạng: %@", postError.localizedDescription);
			completion(nil, postError, SXInfo(@"gemini", model, 0, rounds, start));
			return;
		}
		lastStatus = [resp[@"status"] integerValue];
		NSData *data = resp[@"data"];
		if (lastStatus < 200 || lastStatus >= 300) {
			if (SXRetryHTTP(lastStatus, &retryCount)) continue;
			NSError *err = SXHTTPError(lastStatus, data);
			SXLogErr(@"llm", @"gemini HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
			completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}
		retryCount = 0; // request thành công → trả lại ngân sách retry cho vòng sau

		id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		NSDictionary *candidate = nil;
		if ([json isKindOfClass:[NSDictionary class]]) {
			id candidates = json[@"candidates"];
			if ([candidates isKindOfClass:[NSArray class]] && [candidates count] && [candidates[0] isKindOfClass:[NSDictionary class]]) {
				candidate = candidates[0];
			} else {
				id feedback = json[@"promptFeedback"];
				NSString *block = [feedback isKindOfClass:[NSDictionary class]] && [feedback[@"blockReason"] isKindOfClass:[NSString class]]
					? feedback[@"blockReason"] : nil;
				NSError *err = SXErr(-5, [NSString stringWithFormat:@"Bị chặn bởi bộ lọc an toàn%@.",
										  block.length ? [NSString stringWithFormat:@" (%@)", block] : @""]);
				SXLogWrn(@"llm", @"%@", err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
				return;
			}
		}
		if (!candidate) {
			NSError *err = SXErr(-3, [NSString stringWithFormat:@"Phản hồi không hợp lệ: %@", SXSnippet(data, 200)]);
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
			if ([part[@"text"] isKindOfClass:[NSString class]]) [text appendString:part[@"text"]];
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
				NSDictionary *toolResult = executor(name, args, &toolError);
				NSString *resultText = toolError
					? [@"Lỗi công cụ: " stringByAppendingString:toolError.localizedDescription]
					: ([toolResult[@"result"] isKindOfClass:[NSString class]] ? toolResult[@"result"] : @"Đã thực hiện xong.");
				SXLogDbg(@"llm", @"round %ld: tool %@ → %@", (long)rounds, name, SXShort(resultText, 160));
				// Gemini chỉ nhận role "user"/"model" — functionResponse phải đi kèm "user"
				// ("tool"/"function" là quy ước của OpenAI và bị API trả 400).
				[contents addObject:@{@"role": @"user", @"parts": @[@{@"functionResponse": @{
					@"name": name,
					@"response": @{@"result": resultText},
				}}]}];
			}
			continue;
		}

		if (!text.length) {
			NSError *err = SXErr(-4, @"Model trả về nội dung rỗng.");
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
	SXPrefs *prefs = [SXPrefs shared];
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
		SXAskGemini(prefs, question, history, tools, executor, completion);
	} else {
		SXAskOpenAI(prefs, question, history, tools, executor, completion);
	}
}

@end
