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
								NSTimeInterval timeoutSeconds,
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
	NSTimeInterval timeout = MIN(kSXHTTPTimeout, MAX(1.5, timeoutSeconds));
	request.timeoutInterval = timeout;
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
	long waitResult = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 1.0) * NSEC_PER_SEC)));

	if (sessionError) {
		if (outErr) *outErr = sessionError;
		return nil;
	}
	if (waitResult != 0) {
		// Không có response trong 60s: báo đúng là hết giờ, không phải "HTTP 0".
		if (outErr) *outErr = [NSError errorWithDomain:@"com.sirix.llm" code:-1004
			userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
				@"Máy chủ không phản hồi trong %.0f giây. Kiểm tra mạng hoặc endpoint.", timeout]}];
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

/// Chạy công cụ với lưới an toàn: exception của công cụ (UIKit, pasteboard, mạng…)
/// KHÔNG được làm chết process SpringBoard. Mọi lỗi → NSError để model đọc.
static NSDictionary *SXRunTool(SXToolExec executor, NSString *name, NSDictionary *arguments,
							   NSInteger round, NSError **outError) {
	CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
	NSError *toolError = nil;
	NSDictionary *result = nil;
	@try {
		result = executor(name, arguments, &toolError);
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"công cụ “%@” ném exception %@: %@ | %@",
				 name, exception.name, exception.reason,
				 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
		toolError = SXErr(-1010, [NSString stringWithFormat:@"Công cụ “%@” gặp lỗi nội bộ.", name]);
	} @catch (id other) {
		SXLogErr(@"err", @"công cụ “%@” ném lỗi không phải NSException", name);
		toolError = SXErr(-1010, [NSString stringWithFormat:@"Công cụ “%@” gặp lỗi nội bộ.", name]);
	}
	SXLogDbg(@"tool", @"vòng %ld: %@ → %ld ms%@", (long)round, name,
			 (long)((CFAbsoluteTimeGetCurrent() - began) * 1000),
			 toolError ? @" (lỗi)" : @"");
	if (toolError) {
		SXLogWrn(@"tool", @"%@ lỗi: %@", name, toolError.localizedDescription);
		if (outError) *outError = toolError;
		return nil;
	}
	return result;
}

/// Tham số công cụ đến dưới dạng chuỗi JSON (OpenAI gửi từng mảnh, Gemini gửi
/// object sẵn). Sai cú pháp → {} để handler tự báo thiếu tham số, thay vì làm
/// hỏng cả lượt.
static NSDictionary *SXToolArguments(id raw) {
	if ([raw isKindOfClass:[NSDictionary class]]) return raw;
	if (![raw isKindOfClass:[NSString class]] || ![raw length]) return @{};
	id parsed = [NSJSONSerialization JSONObjectWithData:[(NSString *)raw dataUsingEncoding:NSUTF8StringEncoding]
													   options:0 error:NULL];
	return [parsed isKindOfClass:[NSDictionary class]] ? parsed : @{};
}

static NSString *SXToolResultText(NSError *toolError, NSDictionary *toolResult) {
	if (toolError) return [@"Lỗi công cụ: " stringByAppendingString:toolError.localizedDescription ?: @"không rõ"];
	id value = toolResult[@"result"];
	return [value isKindOfClass:[NSString class]] && [value length] ? value : @"Đã thực hiện xong.";
}

/// System prompt = cấu hình người dùng + bối cảnh + bản mô tả công cụ.
/// Model nhỏ (7B–14B tự host) thường bỏ qua `description` trong schema, nên
/// danh sách công cụ phải được nhắc lại bằng lời trong system prompt.
static NSString *SXComposeSystemPrompt(SXPrefs *prefs) {
	NSMutableString *prompt = [prefs.systemPrompt mutableCopy] ?: [NSMutableString string];
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"vi_VN"];
	formatter.dateFormat = @"EEEE, dd/MM/yyyy HH:mm";
	NSString *zone = [NSTimeZone localTimeZone].name ?: @"?";
	[prompt appendFormat:@"\n\nBối cảnh: bây giờ là %@ (%@); trả lời bằng tiếng Việt.",
		[formatter stringFromDate:[NSDate date]] ?: @"?", zone];
	NSString *brief = [SXTools promptBrief];
	if (brief.length) [prompt appendFormat:@"\n\n%@", brief];
	return [prompt copy];
}

/// Thực thi các functionCall Gemini rồi thêm kết quả vào `contents`. Dùng chung
/// cho cả nhánh stream và non-stream để hai đường không lệch hành vi.
static void SXAppendGeminiToolResults(NSMutableArray *contents, SXToolExec executor,
									  NSArray *functionCalls, NSInteger round) {
	for (NSDictionary *call in functionCalls) {
		if (![call isKindOfClass:[NSDictionary class]]) continue;
		NSString *name = [call[@"name"] isKindOfClass:[NSString class]] ? call[@"name"] : nil;
		if (!name.length) continue;
		NSDictionary *args = SXToolArguments(call[@"args"]);
		NSError *toolError = nil;
		NSDictionary *toolResult = SXRunTool(executor, name, args, round, &toolError);
		NSString *resultText = SXToolResultText(toolError, toolResult);
		// Gemini chỉ nhận role "user"/"model" — functionResponse phải đi kèm "user"
		// ("tool"/"function" là quy ước của OpenAI và bị API trả 400).
		[contents addObject:@{@"role": @"user", @"parts": @[@{@"functionResponse": @{
			@"name": name,
			@"response": @{@"result": resultText},
		}}]}];
	}
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

/// Thực thi toàn bộ tool_calls của một lượt, trả về các message `role: tool`
/// đúng thứ tự — dùng cho cả nhánh stream và non-stream.
static NSArray<NSDictionary *> *SXAppendOpenAIToolResults(NSMutableArray *messages,
													 SXToolExec executor, NSArray *toolCalls, NSInteger round) {
	NSMutableArray *appended = [NSMutableArray array];
	for (NSDictionary *call in toolCalls) {
		if (![call isKindOfClass:[NSDictionary class]]) continue;
		NSDictionary *function = [call[@"function"] isKindOfClass:[NSDictionary class]] ? call[@"function"] : nil;
		NSString *name = [function[@"name"] isKindOfClass:[NSString class]] ? function[@"name"] : nil;
		if (!name.length) continue;
		NSString *callId = [call[@"id"] isKindOfClass:[NSString class]] && [call[@"id"] length]
			? call[@"id"] : name;
		NSDictionary *args = SXToolArguments(function[@"arguments"]);
		NSError *toolError = nil;
		NSDictionary *toolResult = SXRunTool(executor, name, args, round, &toolError);
		NSDictionary *message = @{@"role": @"tool", @"tool_call_id": callId,
								  @"content": SXToolResultText(toolError, toolResult)};
		[messages addObject:message];
		[appended addObject:message];
	}
	return appended;
}

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
	// Nối danh sách công cụ + bối cảnh thời gian vào system prompt.
	NSString *systemPrompt = SXComposeSystemPrompt(prefs);
	[messages addObject:@{@"role": @"system", @"content": systemPrompt}];
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
	// Trần thời gian cho CẢ lượt (kể cả các vòng gọi công cụ): model không thể
	// quay vô hạn trong nền trong khi Siri đã bỏ lượt chờ.
	NSTimeInterval turnLimit = MIN(MAX(4.0, prefs.responseTimeout), 15.0);
	CFAbsoluteTime deadline = start + turnLimit;
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL forceNonStream = !prefs.streaming;

	while (YES) {
		NSTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
		if (remaining < 1.0) {
			NSError *err = SXErr(-1009, [NSString stringWithFormat:
				@"AI chưa trả lời xong trong %.0f giây (đã %ld vòng công cụ).",
				turnLimit, (long)rounds]);
			SXLogWrn(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}
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
													  timeout:remaining
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
				NSArray *streamCalls = [streamResp[@"toolCalls"] isKindOfClass:[NSArray class]]
					? streamResp[@"toolCalls"] : nil;
				if (streamCalls.count && executor && rounds < prefs.maxToolRounds) {
					// Chạy công cụ ngay trên dữ liệu stream: bỏ được trọn một vòng
					// request (1–3 s), đủ để Siri kịp chờ trên máy thật.
					rounds++;
					retryCount = 0;
					NSString *streamed = [streamResp[@"content"] isKindOfClass:[NSString class]]
						? streamResp[@"content"] : nil;
					SXLogDbg(@"llm", @"stream có %lu tool_call → chạy ngay (vòng %ld)",
							 (unsigned long)streamCalls.count, (long)rounds);
					[messages addObject:@{@"role": @"assistant",
										  @"content": streamed.length ? streamed : (id)[NSNull null],
										  @"tool_calls": streamCalls}];
					SXAppendOpenAIToolResults(messages, executor, streamCalls, rounds);
					continue;
				}
				if ([streamResp[@"sawToolCalls"] boolValue]) {
					SXLogDbg(@"llm", @"stream báo tool_calls nhưng không gộp đủ → non-stream vòng %ld", (long)(rounds + 1));
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
		}, remaining, &postError);
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

			SXAppendOpenAIToolResults(messages, executor, toolCalls, rounds);
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
	NSTimeInterval turnLimit = MIN(MAX(4.0, prefs.responseTimeout), 15.0);
	CFAbsoluteTime deadline = start + turnLimit;
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL forceNonStream = !prefs.streaming;

	while (YES) {
		NSTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
		if (remaining < 1.0) {
			NSError *err = SXErr(-1009, [NSString stringWithFormat:
				@"AI chưa trả lời xong trong %.0f giây (đã %ld vòng công cụ).",
				turnLimit, (long)rounds]);
			SXLogWrn(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}
		NSMutableDictionary *body = [@{
			@"contents": contents,
			@"systemInstruction": @{@"parts": @[@{@"text": SXComposeSystemPrompt(prefs)}]},
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
													  timeout:remaining
													  error:&streamError];
			if (!streamResp) {
				// Như nhánh OpenAI: SSE lỗi/treo → fallback non-stream.
				SXLogWrn(@"llm", @"gemini stream lỗi (%@) → thử non-stream", streamError.localizedDescription);
				forceNonStream = YES;
				continue;
			}
			NSInteger streamStatus = [streamResp[@"status"] integerValue];
			if (streamStatus >= 200 && streamStatus < 300) {
				NSArray *streamCalls = [streamResp[@"functionCalls"] isKindOfClass:[NSArray class]]
					? streamResp[@"functionCalls"] : nil;
				if (streamCalls.count && executor && rounds < prefs.maxToolRounds) {
					rounds++;
					retryCount = 0;
					NSString *streamed = [streamResp[@"content"] isKindOfClass:[NSString class]]
						? streamResp[@"content"] : nil;
					SXLogDbg(@"llm", @"stream có %lu functionCall → chạy ngay (vòng %ld)",
							 (unsigned long)streamCalls.count, (long)rounds);
					NSMutableArray *modelParts = [NSMutableArray array];
					if (streamed.length) [modelParts addObject:@{@"text": streamed}];
					for (NSDictionary *call in streamCalls) {
						if ([call isKindOfClass:[NSDictionary class]]) {
							[modelParts addObject:@{@"functionCall": call}];
						}
					}
					[contents addObject:@{@"role": @"model", @"parts": modelParts}];
					SXAppendGeminiToolResults(contents, executor, streamCalls, rounds);
					continue;
				}
				if ([streamResp[@"sawToolCalls"] boolValue]) {
					SXLogDbg(@"llm", @"stream báo functionCall chưa đủ → non-stream vòng %ld", (long)(rounds + 1));
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
		NSDictionary *resp = SXHTTPPost(url, body, @{@"x-goog-api-key": key}, remaining, &postError);
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
			SXAppendGeminiToolResults(contents, executor, functionCalls, rounds);
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

	// Mỗi câu hỏi là một lượt mới: xoá cache chống gọi lặp của tầng công cụ.
	[SXTools beginTurn];

	if (provider == SXProviderGemini) {
		SXAskGemini(prefs, question, history, tools, executor, completion);
	} else {
		SXAskOpenAI(prefs, question, history, tools, executor, completion);
	}
}

@end
