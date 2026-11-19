#import "SXLLM.h"
#import "SXLog.h"
#import "SXHeaders.h"
#import "SXHTTP.h"
#import "SXStream.h"

NSNotificationName const SXLLMToolActivityNotification = @"SXLLMToolActivityNotification";

/// Ngân sách thời gian của một lượt hỏi (từ lúc gửi tới lúc có câu trả lời,
/// gồm mọi vòng gọi công cụ). Siri chỉ giữ hội thoại được vài giây nên đây là
/// con số quan trọng nhất — vượt quá thì người dùng thấy “trả lời quá muộn”.
static NSTimeInterval SXTurnBudget(SXPrefs *prefs) {
	return MIN(MAX(6.0, prefs.responseTimeout), 120.0);
}

/// Model dự phòng khi model người dùng đặt không tồn tại trên endpoint (404).
static NSString *SXFallbackModel(SXProvider provider) {
	return provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini";
}

/// Trần các vòng gọi công cụ trong một lượt.
static NSInteger SXToolRoundLimit(SXPrefs *prefs) {
	return MAX(1, MIN(prefs.maxToolRounds, 6));
}

static void SXPostToolActivity(NSString *name, NSTimeInterval elapsed, NSError *error) {
	NSDictionary *info = @{@"name": name ?: @"?",
						   @"ms": @((NSInteger)(elapsed * 1000.0)),
						   @"failed": @(error != nil)};
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:SXLLMToolActivityNotification
															object:nil
														  userInfo:info];
	});
}

static NSDictionary *SXInfo(NSString *provider, NSString *model, NSInteger status,
							NSInteger rounds, CFAbsoluteTime start) {
	return @{@"provider": provider, @"model": model, @"status": @(status),
			 @"rounds": @(rounds),
			 @"ms": @((NSInteger)((CFAbsoluteTimeGetCurrent() - start) * 1000))};
}

#pragma mark - Bối cảnh & header

/// System prompt = prompt người dùng + bối cảnh máy/thời gian + danh sách công
/// cụ. Model nhỏ (7B–14B tự host) thường bỏ qua `description` trong schema nên
/// danh sách công cụ phải được nhắc lại bằng lời.
static NSString *SXComposeSystemPrompt(SXPrefs *prefs, NSArray<NSDictionary *> *toolDefs) {
	NSMutableString *prompt = [[prefs systemPrompt] mutableCopy] ?: [NSMutableString string];
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"vi_VN"];
	formatter.dateFormat = @"EEEE, dd/MM/yyyy HH:mm";
	NSString *zone = [NSTimeZone localTimeZone].name ?: @"?";
	[prompt appendFormat:@"\n\nBối cảnh: bây giờ là %@ (%@); trả lời bằng tiếng Việt trừ khi người dùng dùng ngôn ngữ khác.",
		[formatter stringFromDate:[NSDate date]] ?: @"?", zone];
	if (toolDefs.count) {
		NSString *brief = [SXTools promptBrief];
		if (brief.length) [prompt appendFormat:@"\n\n%@", brief];
	}
	return [prompt copy];
}

/// Header cho request: xác thực mặc định + header tuỳ chỉnh người dùng đã bật.
/// Header tuỳ chỉnh áp SAU nên có thể thay cả Authorization/api-key khi gateway
/// yêu cầu; các header hệ thống đã bị lọc trong SXHeaders.
static NSDictionary<NSString *, NSString *> *SXRequestHeaders(SXPrefs *prefs,
															   SXProvider provider,
															   NSString *key) {
	NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
	if (provider == SXProviderGemini) headers[@"x-goog-api-key"] = key;
	else headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", key];

	NSDictionary<NSString *, NSString *> *custom = SXHeadersApplied([prefs headersForProvider:provider]);
	if (custom.count) {
		[headers addEntriesFromDictionary:custom];
		NSString *names = [[custom.allKeys sortedArrayUsingSelector:@selector(compare:)]
						   componentsJoinedByString:@", "];
		SXLogDbg(@"llm", @"áp %lu header tuỳ chỉnh cho %@ (%@)", (unsigned long)custom.count,
				 SXProviderDisplayName(provider), names);
	}
	return headers;
}

/// Có nên thử lại ngay request này không (429/5xx). Tối đa hai lần mỗi vòng.
static BOOL SXShouldRetry(NSInteger status, NSInteger *attempt, CFAbsoluteTime deadline) {
	if (!((status == 429) || (status >= 500 && status < 600))) return NO;
	if (*attempt >= 2) return NO;
	NSTimeInterval delay = *attempt == 0 ? 0.4 : 1.2;
	if (CFAbsoluteTimeGetCurrent() + delay > deadline) return NO;
	(*attempt)++;
	SXLogWrn(@"llm", @"HTTP %ld — thử lại %ld/2 sau %.1fs", (long)status, (long)*attempt, delay);
	[NSThread sleepForTimeInterval:delay];
	return YES;
}

#pragma mark - Công cụ

/// Tham số công cụ: OpenAI gửi chuỗi JSON từng mảnh, Gemini gửi object sẵn.
/// Sai cú pháp → {} để handler tự báo thiếu tham số thay vì làm hỏng lượt.
static NSDictionary *SXToolArguments(id raw) {
	if ([raw isKindOfClass:[NSDictionary class]]) return raw;
	if (![raw isKindOfClass:[NSString class]] || ![(NSString *)raw length]) return @{};
	id parsed = [NSJSONSerialization JSONObjectWithData:[(NSString *)raw dataUsingEncoding:NSUTF8StringEncoding]
												options:0 error:NULL];
	return [parsed isKindOfClass:[NSDictionary class]] ? parsed : @{};
}

/// Chạy công cụ với lưới an toàn: exception của công cụ (UIKit, pasteboard,
/// mạng…) không được làm chết SpringBoard. Mọi lỗi → NSError cho model đọc.
static NSString *SXRunTool(SXToolExec executor, NSString *name, NSDictionary *arguments,
						   NSInteger round, BOOL *failed) {
	if (!executor || !name.length) return @"Lỗi công cụ: không có executor.";
	CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
	NSError *toolError = nil;
	NSDictionary *result = nil;
	@try {
		result = executor(name, arguments ?: @{}, &toolError);
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"công cụ “%@” ném exception %@: %@ | %@", name, exception.name,
				 exception.reason, [exception.callStackSymbols componentsJoinedByString:@" ; "]);
		toolError = [SXHTTP errorWithCode:-1010
								  message:[NSString stringWithFormat:@"Công cụ “%@” gặp lỗi nội bộ.", name]];
	} @catch (id other) {
		(void)other;
		toolError = [SXHTTP errorWithCode:-1010
								  message:[NSString stringWithFormat:@"Công cụ “%@” gặp lỗi nội bộ.", name]];
	}
	SXPostToolActivity(name, CFAbsoluteTimeGetCurrent() - began, toolError);
	if (failed) *failed = toolError != nil;
	if (toolError) {
		SXLogWrn(@"tool", @"vòng %ld: %@ lỗi: %@", (long)round, name, toolError.localizedDescription);
		return [NSString stringWithFormat:@"Lỗi công cụ: %@", toolError.localizedDescription ?: @"không rõ"];
	}
	id text = [result isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)result)[@"result"] : result;
	if (![text isKindOfClass:[NSString class]] || ![(NSString *)text length]) return @"Đã thực hiện xong.";
	return text;
}

#pragma mark - OpenAI tương thích

/// Thêm các message `role: tool` cho mọi tool_call của lượt vừa rồi, đúng thứ
/// tự (OpenAI yêu cầu mỗi tool_call có đúng một message tool cùng id).
static void SXAppendOpenAIToolResults(NSMutableArray *messages, SXToolExec executor,
									  NSArray *toolCalls, NSInteger round) {
	NSMutableSet<NSString *> *answered = [NSMutableSet set];
	for (NSDictionary *call in toolCalls) {
		if (![call isKindOfClass:[NSDictionary class]]) continue;
		NSDictionary *function = [call[@"function"] isKindOfClass:[NSDictionary class]]
			? call[@"function"] : nil;
		NSString *name = [function[@"name"] isKindOfClass:[NSString class]] ? function[@"name"] : nil;
		NSString *callId = [call[@"id"] isKindOfClass:[NSString class]] && [call[@"id"] length]
			? call[@"id"] : name;
		if (!callId.length) continue;
		if ([answered containsObject:callId]) continue;
		[answered addObject:callId];
		BOOL failed = NO;
		NSString *text = name.length
			? SXRunTool(executor, name, SXToolArguments(function[@"arguments"]), round, &failed)
			: @"Lỗi công cụ: thiếu tên công cụ.";
		(void)failed;
		[messages addObject:@{@"role": @"tool", @"tool_call_id": callId,
							  @"content": SXToolJSONString(@{@"result": text})}];
	}
}

static void SXAskOpenAIResponses(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
								 NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
								 NSString *url, NSDictionary<NSString *, NSString *> *headers,
								 NSString *model, SXLLMDelta onDelta, SXLLMCompletion completion);
static NSString *SXOpenAIURL(NSString *base, BOOL responses);
static BOOL SXModelRejectsTemperature(NSString *model);

/// Stream đứt giữa chừng (mạng rớt, idle timeout) nhưng đã có chữ: thà trả lời
/// bằng phần đã nhận còn hơn để người dùng chờ hết ngân sách rồi nhận “hết giờ”.
/// Chỉ áp dụng khi CHƯA có tool call — nếu model đang gọi công cụ thì phải làm
/// nốt, không thể cắt giữa.
static BOOL SXStreamSalvage(NSDictionary *streamResp, NSString *provider, NSString *model,
							NSInteger rounds, CFAbsoluteTime start, SXLLMCompletion completion) {
	if (![streamResp isKindOfClass:[NSDictionary class]] || !completion) return NO;
	if ([streamResp[@"sawToolCalls"] boolValue]) return NO;
	NSString *partial = [streamResp[@"content"] isKindOfClass:[NSString class]] ? streamResp[@"content"] : nil;
	partial = [partial stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!partial.length) return NO;
	NSDictionary *info = SXInfo(provider, model, [streamResp[@"status"] integerValue], rounds, start);
	SXLogWrn(@"llm", @"stream đứt — dùng phần đã nhận (%lu ký tự, %ld ms)",
			 (unsigned long)partial.length, (long)[info[@"ms"] integerValue]);
	completion(partial, nil, info);
	return YES;
}

static void SXAskOpenAIChat(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
							NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
							SXLLMDelta onDelta, SXLLMCompletion completion) {
	NSString *key = [[prefs openaiKey] stringByTrimmingCharactersInSet:
					 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *model = [[prefs openaiModel] stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!model.length) model = @"gpt-4o-mini";
	NSString *rawBase = [[prefs openaiBase] stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *base = [SXPrefs normalizedBaseURL:rawBase];
	if (!base.length) {
		// Không bao giờ âm thầm rơi về api.openai.com khi người dùng đã nhập địa
		// chỉ sai: làm vậy sẽ gửi khóa của họ tới máy chủ không mong muốn.
		NSString *message = rawBase.length
			? [NSString stringWithFormat:@"Địa chỉ API không hợp lệ: %@", rawBase]
			: @"Chưa đặt địa chỉ API. Mở Cấu hình OpenAI để nhập endpoint.";
		completion(nil, [SXHTTP errorWithCode:-1003 message:message], nil);
		return;
	}
	NSString *url = SXOpenAIURL(base, NO);
	NSDictionary<NSString *, NSString *> *headers = SXRequestHeaders(prefs, SXProviderOpenAI, key);

	NSMutableArray *messages = [NSMutableArray array];
	[messages addObject:@{@"role": @"system", @"content": SXComposeSystemPrompt(prefs, toolDefs)}];
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

	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	CFAbsoluteTime deadline = start + SXTurnBudget(prefs);
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL streamAllowed = prefs.streaming;

	SXLogDbg(@"llm", @"openai → %@ (model=%@, %lu message, %lu tool, temp=%.1f, stream=%d)",
			 url, model, (unsigned long)messages.count, (unsigned long)toolsPayload.count,
			 prefs.temperature, streamAllowed);

	while (YES) {
		NSTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
		if (remaining < 1.0) {
			completion(nil, [SXHTTP errorWithCode:-1009
										  message:[NSString stringWithFormat:
												   @"AI chưa trả lời xong trong %.0f giây (đã %ld vòng công cụ).",
												   SXTurnBudget(prefs), (long)rounds]],
					   SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}
		// Không stream lại sau khi đã dùng công cụ: vòng tổng hợp cuối thường
		// ngắn, non-stream cho câu trả lời trọn vẹn trong một lần.
		BOOL streamThisRound = streamAllowed && rounds == 0;

		NSMutableDictionary *body = [@{@"model": model, @"messages": messages} mutableCopy];
		// o1/o3/o4/gpt-5 từ chối `temperature` (HTTP 400). Bỏ hẳn thay vì gửi 0.
		if (!SXModelRejectsTemperature(model)) body[@"temperature"] = @(prefs.temperature);
		if (toolsPayload.count) {
			body[@"tools"] = toolsPayload;
			body[@"tool_choice"] = @"auto";
		}

		NSString *content = nil;
		id toolCalls = nil;

		if (streamThisRound) {
			body[@"stream"] = @YES;
			NSMutableDictionary *streamBody = body;
			// Stream có ngân sách riêng: nếu endpoint "nhận" SSE rồi im lặng
			// (một số proxy), ta bỏ sang non-stream thay vì chờ hết lượt.
			NSTimeInterval streamBudget = MIN(remaining, MAX(4.0, remaining * 0.65));
			NSError *streamError = nil;
			NSDictionary *streamResp = [SXStream postJSON:streamBody
													toURL:url
												  headers:headers
												   format:SXStreamFormatOpenAI
												  timeout:streamBudget
											   idleTimeout:MIN(12.0, streamBudget)
													 onDelta:onDelta
													  error:&streamError];
			if (!streamResp) {
				SXLogWrn(@"llm", @"openai stream lỗi (%@) → non-stream", streamError.localizedDescription);
				if (SXStreamSalvage(streamError.userInfo[@"sx.partial"], @"openai", model, rounds, start, completion)) return;
				streamAllowed = NO;
				continue;
			}
			lastStatus = [streamResp[@"status"] integerValue];
			if (lastStatus >= 200 && lastStatus < 300) {
				content = [streamResp[@"content"] isKindOfClass:[NSString class]] ? streamResp[@"content"] : nil;
				toolCalls = [streamResp[@"toolCalls"] isKindOfClass:[NSArray class]] ? streamResp[@"toolCalls"] : nil;
				if (![toolCalls isKindOfClass:[NSArray class]] && streamResp[@"toolCalls"]) toolCalls = nil;
				if (!((NSArray *)toolCalls).count && content.length) {
					NSDictionary *info = SXInfo(@"openai", model, lastStatus, rounds, start);
					NSInteger firstToken = [streamResp[@"firstTokenMs"] integerValue];
					SXLogInf(@"llm", @"openai OK (stream) — token đầu %ld ms · tổng %ld ms · %lu ký tự",
							 (long)firstToken, (long)[info[@"ms"] integerValue],
							 (unsigned long)content.length);
					completion(content, nil, info);
					return;
				}
				if (!((NSArray *)toolCalls).count) {
					SXLogWrn(@"llm", @"stream rỗng → non-stream");
					streamAllowed = NO;
					continue;
				}
			} else if (SXShouldRetry(lastStatus, &retryCount, deadline)) {
				continue;
			} else if (lastStatus == 400 || lastStatus == 404 || lastStatus == 405 ||
					   lastStatus == 415 || lastStatus == 501 || lastStatus == 422) {
				SXLogWrn(@"llm", @"endpoint không hỗ trợ stream (HTTP %ld) → non-stream", (long)lastStatus);
				streamAllowed = NO;
				continue;
			} else {
				NSString *errorText = [streamResp[@"errorText"] isKindOfClass:[NSString class]]
					? streamResp[@"errorText"] : nil;
				NSData *errData = [errorText dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
				NSError *err = [SXHTTP errorWithStatus:lastStatus data:errData];
				SXLogErr(@"llm", @"openai stream HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
				return;
			}
		} else {
			SXHTTPResult *result = [SXHTTP postURL:url
											  body:body
										   headers:headers
										   timeout:remaining
									   idleTimeout:MIN(30.0, remaining)
											onData:nil];
			if (result.error && result.status == 0) {
				SXLogErr(@"llm", @"openai lỗi mạng: %@", result.error.localizedDescription);
				completion(nil, result.error, SXInfo(@"openai", model, 0, rounds, start));
				return;
			}
			lastStatus = result.status;
			if (lastStatus < 200 || lastStatus >= 300) {
				if (SXShouldRetry(lastStatus, &retryCount, deadline)) continue;
				NSString *fallback = SXFallbackModel(SXProviderOpenAI);
				if (lastStatus == 404 && rounds == 0 && ![model isEqualToString:fallback]) {
					SXLogWrn(@"llm", @"model %@ không có trên endpoint (404) → thử %@", model, fallback);
					model = fallback;
					retryCount = 0;
					continue;
				}
				NSError *err = [SXHTTP errorWithStatus:lastStatus data:result.body];
				SXLogErr(@"llm", @"openai HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
				return;
			}
			retryCount = 0;

			id json = [NSJSONSerialization JSONObjectWithData:result.body options:0 error:NULL];
			NSDictionary *choice = nil;
			if ([json isKindOfClass:[NSDictionary class]]) {
				id choices = ((NSDictionary *)json)[@"choices"];
				if ([choices isKindOfClass:[NSArray class]] && [choices count] &&
					[choices[0] isKindOfClass:[NSDictionary class]]) {
					choice = ((NSDictionary *)choices[0])[@"message"];
				}
			}
			if (![choice isKindOfClass:[NSDictionary class]]) {
				NSString *snippet = [[NSString alloc] initWithData:result.body
														  encoding:NSUTF8StringEncoding] ?: @"";
				if (snippet.length > 200) snippet = [[snippet substringToIndex:200] stringByAppendingString:@"…"];
				NSError *err = [SXHTTP errorWithCode:-3
											 message:[NSString stringWithFormat:@"Phản hồi không hợp lệ: %@", snippet]];
				SXLogErr(@"llm", @"%@", err.localizedDescription);
				completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
				return;
			}
			content = [choice[@"content"] isKindOfClass:[NSString class]] ? choice[@"content"] : nil;
			toolCalls = [choice[@"tool_calls"] isKindOfClass:[NSArray class]] ? choice[@"tool_calls"] : nil;
		}

		if ([toolCalls isKindOfClass:[NSArray class]] && [toolCalls count] &&
			executor && rounds < SXToolRoundLimit(prefs)) {
			rounds++;
			retryCount = 0;
			SXLogDbg(@"llm", @"chạy %lu tool_call (vòng %ld)", (unsigned long)[toolCalls count], (long)rounds);
			[messages addObject:@{@"role": @"assistant",
								  @"content": content.length ? content : (id)[NSNull null],
								  @"tool_calls": toolCalls}];
			SXAppendOpenAIToolResults(messages, executor, toolCalls, rounds);
			continue;
		}

		if (!content.length) {
			NSError *err = [SXHTTP errorWithCode:-4 message:@"Model trả về nội dung rỗng."];
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"openai", model, lastStatus, rounds, start));
			return;
		}
		NSDictionary *info = SXInfo(@"openai", model, lastStatus, rounds, start);
		SXLogInf(@"llm", @"openai OK — %ld ms, %ld vòng công cụ, %lu ký tự",
				 (long)[info[@"ms"] integerValue], (long)rounds, (unsigned long)content.length);
		completion(content, nil, info);
		return;
	}
}

#pragma mark - OpenAI Responses API

/// Model suy luận (o-series, gpt-5) từ chối `temperature`; gửi kèm sẽ ăn 400.
static BOOL SXModelRejectsTemperature(NSString *model) {
	if (![model isKindOfClass:[NSString class]]) return NO;
	NSString *lower = model.lowercaseString;
	if ([lower hasPrefix:@"o1"] || [lower hasPrefix:@"o3"] || [lower hasPrefix:@"o4"] ||
		[lower hasPrefix:@"gpt-5"]) return YES;
	return [lower containsString:@"reasoning"];
}

/// Đổi schema công cụ kiểu chat completions (lồng function) sang kiểu phẳng của
/// Responses API: {type:"function", name, description, parameters}.
static NSArray<NSDictionary *> *SXResponsesTools(NSArray<NSDictionary *> *toolDefs) {
	NSMutableArray *tools = [NSMutableArray array];
	for (NSDictionary *def in toolDefs) {
		NSDictionary *parameters = [def[@"parameters"] isKindOfClass:[NSDictionary class]]
			? def[@"parameters"] : @{@"type": @"object", @"properties": @{}};
		[tools addObject:@{@"type": @"function",
						   @"name": def[@"name"] ?: @"",
						   @"description": def[@"description"] ?: @"",
						   @"parameters": parameters,
						   @"strict": @NO}];
	}
	return tools;
}

/// `input` của Responses API: mảng item. Lịch sử + câu hỏi mới, dạng message.
static NSMutableArray *SXResponsesInput(NSString *question, NSArray<NSDictionary *> *history) {
	NSMutableArray *input = [NSMutableArray array];
	for (NSDictionary *turn in history) {
		NSString *q = [turn[@"q"] isKindOfClass:[NSString class]] ? turn[@"q"] : nil;
		NSString *a = [turn[@"a"] isKindOfClass:[NSString class]] ? turn[@"a"] : nil;
		if (q.length) [input addObject:@{@"role": @"user", @"content": q}];
		if (a.length) [input addObject:@{@"role": @"assistant", @"content": a}];
	}
	[input addObject:@{@"role": @"user", @"content": question}];
	return input;
}

/// Ghi kết quả công cụ vào `input` đúng dạng function_call_output.
static void SXAppendResponsesToolResults(NSMutableArray *input, SXToolExec executor,
										 NSArray<NSDictionary *> *calls, NSInteger round) {
	for (NSDictionary *call in calls) {
		if (![call isKindOfClass:[NSDictionary class]]) continue;
		NSString *name = [call[@"name"] isKindOfClass:[NSString class]] ? call[@"name"] : nil;
		NSString *callId = [call[@"call_id"] isKindOfClass:[NSString class]] ? call[@"call_id"] : nil;
		if (!callId.length) callId = name;
		if (!callId.length) continue;
		BOOL failed = NO;
		NSString *text = name.length
			? SXRunTool(executor, name, SXToolArguments(call[@"arguments"]), round, &failed)
			: @"Lỗi công cụ: thiếu tên công cụ.";
		(void)failed;
		[input addObject:@{@"type": @"function_call_output",
						   @"call_id": callId,
						   @"output": SXToolJSONString(@{@"result": text})}];
	}
}

/// Đọc câu trả lời từ JSON không stream của /v1/responses:
/// {output:[{type:"message", content:[{type:"output_text", text}]},
///          {type:"function_call", call_id, name, arguments}]}
static NSDictionary *SXResponsesParseJSON(NSData *data) {
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![json isKindOfClass:[NSDictionary class]]) return nil;
	NSMutableString *text = [NSMutableString string];
	NSMutableArray<NSDictionary *> *calls = [NSMutableArray array];
	NSMutableString *reasoning = [NSMutableString string];
	NSArray *output = [((NSDictionary *)json)[@"output"] isKindOfClass:[NSArray class]]
		? ((NSDictionary *)json)[@"output"] : nil;
	for (id item in output) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		NSString *type = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"";
		if ([type isEqualToString:@"function_call"]) {
			NSString *name = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : nil;
			if (!name.length) continue;
			NSString *callId = [item[@"call_id"] isKindOfClass:[NSString class]] ? item[@"call_id"] : name;
			NSString *arguments = [item[@"arguments"] isKindOfClass:[NSString class]] ? item[@"arguments"] : @"{}";
			[calls addObject:@{@"call_id": callId, @"name": name, @"arguments": arguments}];
			continue;
		}
		if ([type isEqualToString:@"reasoning"]) {
			NSArray *summary = [item[@"summary"] isKindOfClass:[NSArray class]] ? item[@"summary"] : nil;
			for (id part in summary) {
				if ([part isKindOfClass:[NSDictionary class]] && [part[@"text"] isKindOfClass:[NSString class]]) {
					[reasoning appendString:part[@"text"]];
				}
			}
			continue;
		}
		NSArray *parts = [item[@"content"] isKindOfClass:[NSArray class]] ? item[@"content"] : nil;
		for (id part in parts) {
			if (![part isKindOfClass:[NSDictionary class]]) continue;
			id value = part[@"text"];
			if ([value isKindOfClass:[NSString class]]) [text appendString:value];
		}
	}
	NSMutableDictionary *result = [@{
		@"content": [text copy],
		@"calls": calls,
	} mutableCopy];
	NSString *identifier = [((NSDictionary *)json)[@"id"] isKindOfClass:[NSString class]]
		? ((NSDictionary *)json)[@"id"] : nil;
	if (identifier.length) result[@"responseId"] = identifier;
	if (reasoning.length) result[@"reasoning"] = [reasoning copy];
	id error = ((NSDictionary *)json)[@"error"];
	if ([error isKindOfClass:[NSDictionary class]] && [error[@"message"] isKindOfClass:[NSString class]]) {
		result[@"errorText"] = error[@"message"];
	}
	return result;
}

static void SXAskOpenAIResponses(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
								 NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
								 NSString *url, NSDictionary<NSString *, NSString *> *headers,
								 NSString *model, SXLLMDelta onDelta, SXLLMCompletion completion) {
	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	CFAbsoluteTime deadline = start + SXTurnBudget(prefs);
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL streamAllowed = prefs.streaming;
	BOOL allowTemperature = !SXModelRejectsTemperature(model);
	NSMutableArray *input = SXResponsesInput(question, history);
	NSString *previousResponseId = nil;

	SXLogDbg(@"llm", @"openai/responses → %@ (model=%@, %lu item, %lu tool, stream=%d, temperature=%d)",
			 url, model, (unsigned long)input.count, (unsigned long)toolDefs.count,
			 streamAllowed, allowTemperature);

	while (YES) {
		NSTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
		if (remaining < 1.0) {
			completion(nil, [SXHTTP errorWithCode:-1009
									  message:[NSString stringWithFormat:
											   @"AI chưa trả lời xong trong %.0f giây (đã %ld vòng công cụ).",
											   SXTurnBudget(prefs), (long)rounds]],
					   SXInfo(@"openai/responses", model, lastStatus, rounds, start));
			return;
		}
		BOOL streamThisRound = streamAllowed && rounds == 0;

		NSMutableDictionary *body = [@{@"model": model,
									   @"input": input,
									   @"instructions": SXComposeSystemPrompt(prefs, toolDefs)}
									 mutableCopy];
		if (allowTemperature) body[@"temperature"] = @(prefs.temperature);
		if (toolDefs.count) {
			body[@"tools"] = SXResponsesTools(toolDefs);
			body[@"tool_choice"] = @"auto";
		}
		if (previousResponseId.length && rounds > 0) body[@"previous_response_id"] = previousResponseId;

		NSString *content = nil;
		NSArray<NSDictionary *> *calls = nil;
		NSString *streamError = nil;

		if (streamThisRound) {
			body[@"stream"] = @YES;
			NSTimeInterval streamBudget = MIN(remaining, MAX(4.0, remaining * 0.65));
			NSError *error = nil;
			NSDictionary *streamResp = [SXStream postJSON:body
													toURL:url
												  headers:headers
												   format:SXStreamFormatResponses
												  timeout:streamBudget
											  idleTimeout:MIN(12.0, streamBudget)
												  onDelta:onDelta
													error:&error];
			if (!streamResp) {
				SXLogWrn(@"llm", @"responses stream lỗi (%@) → non-stream", error.localizedDescription);
				if (error.userInfo[@"sx.partial"] &&
					SXStreamSalvage(error.userInfo[@"sx.partial"], @"openai/responses", model, rounds, start, completion)) return;
				streamAllowed = NO;
				continue;
			}
			lastStatus = [streamResp[@"status"] integerValue];
			if (lastStatus >= 200 && lastStatus < 300) {
				content = [streamResp[@"content"] isKindOfClass:[NSString class]] ? streamResp[@"content"] : nil;
				calls = [streamResp[@"responseCalls"] isKindOfClass:[NSArray class]] ? streamResp[@"responseCalls"] : @[];
				if ([streamResp[@"responseId"] isKindOfClass:[NSString class]]) {
					previousResponseId = streamResp[@"responseId"];
				}
				if (streamResp[@"reasoning"]) {
					SXLogDbg(@"llm", @"responses suy luận: %@", SXShort(streamResp[@"reasoning"], 300));
				}
				if (!calls.count && content.length) {
					NSDictionary *info = SXInfo(@"openai/responses", model, lastStatus, rounds, start);
					NSInteger firstToken = [streamResp[@"firstTokenMs"] integerValue];
					SXLogInf(@"llm", @"openai/responses OK (stream) — token đầu %ld ms · tổng %ld ms · %lu ký tự",
							 (long)firstToken, (long)[info[@"ms"] integerValue], (unsigned long)content.length);
					completion(content, nil, info);
					return;
				}
				if (!calls.count) {
					SXLogWrn(@"llm", @"responses stream rỗng → non-stream");
					streamAllowed = NO;
					continue;
				}
			} else if (SXShouldRetry(lastStatus, &retryCount, deadline)) {
				continue;
			} else if (lastStatus == 400 || lastStatus == 404 || lastStatus == 405 ||
					   lastStatus == 415 || lastStatus == 501 || lastStatus == 422) {
				SXLogWrn(@"llm", @"responses stream không hỗ trợ (HTTP %ld) → non-stream", (long)lastStatus);
				streamAllowed = NO;
				continue;
			} else {
				streamError = [streamResp[@"errorText"] isKindOfClass:[NSString class]]
					? streamResp[@"errorText"] : nil;
				NSData *data = [streamError dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
				NSError *err = [SXHTTP errorWithStatus:lastStatus data:data];
				SXLogErr(@"llm", @"responses stream HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"openai/responses", model, lastStatus, rounds, start));
				return;
			}
		} else {
			SXHTTPResult *result = [SXHTTP postURL:url
											  body:body
										   headers:headers
										   timeout:remaining
									   idleTimeout:MIN(30.0, remaining)
											onData:nil];
			if (result.error && result.status == 0) {
				SXLogErr(@"llm", @"responses lỗi mạng: %@", result.error.localizedDescription);
				completion(nil, result.error, SXInfo(@"openai/responses", model, 0, rounds, start));
				return;
			}
			lastStatus = result.status;
			if (lastStatus < 200 || lastStatus >= 300) {
				if (SXShouldRetry(lastStatus, &retryCount, deadline)) continue;
				NSString *fallback = SXFallbackModel(SXProviderOpenAI);
				if (lastStatus == 404 && rounds == 0 && ![model isEqualToString:fallback]) {
					SXLogWrn(@"llm", @"responses: model %@ không có (404) → thử %@", model, fallback);
					model = fallback;
					retryCount = 0;
					continue;
				}
				if ((lastStatus == 404 || lastStatus == 405 || lastStatus == 501) && rounds == 0) {
					// Máy chủ không có /responses (nhiều gateway chỉ làm chat
					// completions). Rơi về nhánh cũ thay vì báo lỗi cho người dùng.
					SXLogWrn(@"llm", @"/responses trả HTTP %ld → dùng chat completions", (long)lastStatus);
					SXAskOpenAIChat(prefs, question, history, toolDefs, executor, onDelta, completion);
					return;
				}
				NSError *err = [SXHTTP errorWithStatus:lastStatus data:result.body];
				SXLogErr(@"llm", @"responses HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"openai/responses", model, lastStatus, rounds, start));
				return;
			}
			retryCount = 0;
			NSDictionary *parsed = SXResponsesParseJSON(result.body);
			if (!parsed) {
				NSString *snippet = [[NSString alloc] initWithData:result.body encoding:NSUTF8StringEncoding] ?: @"";
				if (snippet.length > 200) snippet = [[snippet substringToIndex:200] stringByAppendingString:@"…"];
				NSError *err = [SXHTTP errorWithCode:-3
											 message:[NSString stringWithFormat:@"Phản hồi không hợp lệ: %@", snippet]];
				SXLogErr(@"llm", @"%@", err.localizedDescription);
				completion(nil, err, SXInfo(@"openai/responses", model, lastStatus, rounds, start));
				return;
			}
			if (parsed[@"errorText"]) {
				NSError *err = [SXHTTP errorWithCode:-5 message:parsed[@"errorText"]];
				SXLogErr(@"llm", @"responses báo lỗi: %@", err.localizedDescription);
				completion(nil, err, SXInfo(@"openai/responses", model, lastStatus, rounds, start));
				return;
			}
			content = [parsed[@"content"] isKindOfClass:[NSString class]] ? parsed[@"content"] : nil;
			calls = [parsed[@"calls"] isKindOfClass:[NSArray class]] ? parsed[@"calls"] : @[];
			if ([parsed[@"responseId"] isKindOfClass:[NSString class]]) previousResponseId = parsed[@"responseId"];
		}

		if (calls.count && executor && rounds < SXToolRoundLimit(prefs)) {
			rounds++;
			retryCount = 0;
			SXLogDbg(@"llm", @"responses: chạy %lu function_call (vòng %ld)", (unsigned long)calls.count, (long)rounds);
			// Chỉ gửi các item mới (function_call_output); phần trước đó đã nằm ở
			// máy chủ qua `previous_response_id` khi máy chủ hỗ trợ.
			if (!previousResponseId.length) {
				for (NSDictionary *call in calls) {
					[input addObject:@{@"type": @"function_call",
									   @"call_id": call[@"call_id"] ?: @"",
									   @"name": call[@"name"] ?: @"",
									   @"arguments": call[@"arguments"] ?: @"{}"}];
				}
			}
			NSMutableArray *toolInput = [NSMutableArray array];
			SXAppendResponsesToolResults(toolInput, executor, calls, rounds);
			if (previousResponseId.length) {
				input = toolInput;
			} else {
				[input addObjectsFromArray:toolInput];
			}
			continue;
		}

		if (!content.length) {
			NSError *err = [SXHTTP errorWithCode:-4 message:@"Model trả về nội dung rỗng."];
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"openai/responses", model, lastStatus, rounds, start));
			return;
		}
		NSDictionary *info = SXInfo(@"openai/responses", model, lastStatus, rounds, start);
		SXLogInf(@"llm", @"openai/responses OK — %ld ms, %ld vòng công cụ, %lu ký tự",
				 (long)[info[@"ms"] integerValue], (long)rounds, (unsigned long)content.length);
		completion(content, nil, info);
		return;
	}
}

/// URL của một giao thức trên endpoint hiện tại. Người dùng có thể đã dán sẵn
/// ".../v1", ".../v1/chat/completions" hoặc ".../v1/responses" — cắt đuôi đó rồi
/// ghép lại cho đúng, để đổi giao thức không tạo ra ".../chat/completions/responses".
static NSString *SXOpenAIURL(NSString *base, BOOL responses) {
	NSString *root = base;
	for (NSString *suffix in @[@"/chat/completions", @"/responses"]) {
		if ([root hasSuffix:suffix]) {
			root = [root substringToIndex:root.length - suffix.length];
			break;
		}
	}
	return [root stringByAppendingString:responses ? @"/responses" : @"/chat/completions"];
}

/// Máy chủ có /responses không? Một META/OPTIONS rẻ hơn một lượt gọi thật và
/// không tốn token. Chỉ dùng cho giao thức "Tự dò".
static BOOL SXOpenAIHasResponses(NSString *url, NSDictionary<NSString *, NSString *> *headers) {
	@try {
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
		request.HTTPMethod = @"OPTIONS";
		request.timeoutInterval = 4.0;
		for (NSString *name in headers) {
			if ([name.lowercaseString isEqualToString:@"content-type"]) continue;
			[request setValue:headers[name] forHTTPHeaderField:name];
		}
		__block NSInteger status = 0;
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
																 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
			(void)data; (void)error;
			if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
				status = ((NSHTTPURLResponse *)response).statusCode;
			}
			dispatch_semaphore_signal(done);
		}];
		[task resume];
		dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.5 * NSEC_PER_SEC)));
		if (status == 0) return NO;
		// 200/204/405 = đường dẫn tồn tại (một số máy chủ không trả 2xx cho OPTIONS).
		return status != 404 && status != 501;
	} @catch (NSException *exception) {
		SXLogWrn(@"llm", @"dò /responses lỗi: %@", exception.reason);
		return NO;
	}
}

/// Nhánh OpenAI tương thích: chọn giao thức theo cấu hình, tự dò khi cần, và
/// rơi về chat completions nếu /responses không có (404/405/501).
static void SXAskOpenAI(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
						NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
						SXLLMDelta onDelta, SXLLMCompletion completion) {
	NSString *key = [[prefs openaiKey] stringByTrimmingCharactersInSet:
					 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *model = [[prefs openaiModel] stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!model.length) model = @"gpt-4o-mini";
	NSString *rawBase = [[prefs openaiBase] stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *base = [SXPrefs normalizedBaseURL:rawBase];
	if (!base.length) {
		NSString *message = rawBase.length
			? [NSString stringWithFormat:@"Địa chỉ API không hợp lệ: %@", rawBase]
			: @"Chưa đặt địa chỉ API. Mở Cấu hình OpenAI để nhập endpoint.";
		completion(nil, [SXHTTP errorWithCode:-1003 message:message], nil);
		return;
	}
	NSDictionary<NSString *, NSString *> *headers = SXRequestHeaders(prefs, SXProviderOpenAI, key);
	NSString *responsesURL = SXOpenAIURL(base, YES);

	SXOpenAIApi api = prefs.openaiApi;
	if (api == SXOpenAIApiAuto) {
		// Dấu hiệu rẻ để đoán trước khi dò: endpoint chính chủ OpenAI hoặc model
		// thuộc dòng chỉ có trên Responses API.
		NSString *host = [NSURL URLWithString:base].host.lowercaseString ?: @"";
		NSString *lowerModel = model.lowercaseString;
		BOOL looksResponsesOnly = [lowerModel hasPrefix:@"gpt-5"] || [lowerModel hasPrefix:@"o3"] ||
			[lowerModel hasPrefix:@"o4"] || [lowerModel hasPrefix:@"codex"];
		BOOL official = [host isEqualToString:@"api.openai.com"];
		if (official || looksResponsesOnly) {
			api = SXOpenAIApiResponses;
		} else {
			api = SXOpenAIHasResponses(responsesURL, headers) ? SXOpenAIApiResponses : SXOpenAIApiChat;
		}
		SXLogInf(@"llm", @"tự dò giao thức OpenAI (host=%@ model=%@) → %@",
				 host, model, api == SXOpenAIApiResponses ? @"responses" : @"chat");
	}

	if (api == SXOpenAIApiResponses) {
		SXAskOpenAIResponses(prefs, question, history, toolDefs, executor,
							 responsesURL, headers, model, onDelta, completion);
		return;
	}
	SXAskOpenAIChat(prefs, question, history, toolDefs, executor, onDelta, completion);
}

#pragma mark - Gemini

/// JSON schema (chữ thường) → Schema của Gemini (type chữ HOA).
static id SXGeminiSchema(id node) {
	if ([node isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)node count]];
		[(NSDictionary *)node enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if ([key isEqualToString:@"type"] && [value isKindOfClass:[NSString class]]) {
				out[key] = [(NSString *)value uppercaseString];
			} else {
				out[key] = SXGeminiSchema(value);
			}
		}];
		return out;
	}
	if ([node isKindOfClass:[NSArray class]]) {
		NSMutableArray *out = [NSMutableArray arrayWithCapacity:[(NSArray *)node count]];
		for (id item in (NSArray *)node) [out addObject:SXGeminiSchema(item)];
		return out;
	}
	return node;
}

static void SXAppendGeminiToolResults(NSMutableArray *contents, SXToolExec executor,
									  NSArray *functionCalls, NSInteger round) {
	for (NSDictionary *call in functionCalls) {
		if (![call isKindOfClass:[NSDictionary class]]) continue;
		NSString *name = [call[@"name"] isKindOfClass:[NSString class]] ? call[@"name"] : nil;
		if (!name.length) continue;
		BOOL failed = NO;
		NSString *text = SXRunTool(executor, name, SXToolArguments(call[@"args"]), round, &failed);
		(void)failed;
		// Gemini chỉ nhận role "user"/"model" — functionResponse phải đi kèm "user"
		// ("tool"/"function" là quy ước của OpenAI và bị API trả 400).
		[contents addObject:@{@"role": @"user", @"parts": @[@{@"functionResponse": @{
			@"name": name,
			@"response": @{@"result": text},
		}}]}];
	}
}

static void SXAskGemini(SXPrefs *prefs, NSString *question, NSArray<NSDictionary *> *history,
						NSArray<NSDictionary *> *toolDefs, SXToolExec executor,
						SXLLMDelta onDelta, SXLLMCompletion completion) {
	NSString *key = [[prefs geminiKey] stringByTrimmingCharactersInSet:
					 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *model = [[prefs geminiModel] stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!model.length) model = @"gemini-2.0-flash";
	if ([model hasPrefix:@"models/"]) model = [model substringFromIndex:7];
	NSString *url = [NSString stringWithFormat:
		@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent", model];
	NSString *streamURL = [NSString stringWithFormat:
		@"https://generativelanguage.googleapis.com/v1beta/models/%@:streamGenerateContent?alt=sse", model];
	NSDictionary<NSString *, NSString *> *headers = SXRequestHeaders(prefs, SXProviderGemini, key);

	NSMutableArray *contents = [NSMutableArray array];
	for (NSDictionary *turn in history) {
		NSString *q = [turn[@"q"] isKindOfClass:[NSString class]] ? turn[@"q"] : nil;
		NSString *a = [turn[@"a"] isKindOfClass:[NSString class]] ? turn[@"a"] : nil;
		if (q.length) [contents addObject:@{@"role": @"user", @"parts": @[@{@"text": q}]}];
		if (a.length) [contents addObject:@{@"role": @"model", @"parts": @[@{@"text": a}]}];
	}
	[contents addObject:@{@"role": @"user", @"parts": @[@{@"text": question}]}];

	NSMutableArray *declarations = [NSMutableArray array];
	for (NSDictionary *def in toolDefs) {
		[declarations addObject:@{
			@"name": def[@"name"] ?: @"",
			@"description": def[@"description"] ?: @"",
			@"parameters": SXGeminiSchema(def[@"parameters"] ?: @{@"type": @"object", @"properties": @{}}),
		}];
	}

	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	CFAbsoluteTime deadline = start + SXTurnBudget(prefs);
	NSInteger rounds = 0;
	NSInteger lastStatus = 0;
	NSInteger retryCount = 0;
	BOOL streamAllowed = prefs.streaming;

	SXLogDbg(@"llm", @"gemini → models/%@ (%lu message, %lu tool, temp=%.1f, stream=%d)",
			 model, (unsigned long)contents.count, (unsigned long)declarations.count,
			 prefs.temperature, streamAllowed);

	while (YES) {
		NSTimeInterval remaining = deadline - CFAbsoluteTimeGetCurrent();
		if (remaining < 1.0) {
			completion(nil, [SXHTTP errorWithCode:-1009
										  message:[NSString stringWithFormat:
												   @"AI chưa trả lời xong trong %.0f giây (đã %ld vòng công cụ).",
												   SXTurnBudget(prefs), (long)rounds]],
					   SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}
		BOOL streamThisRound = streamAllowed && rounds == 0;

		NSMutableDictionary *body = [@{
			@"contents": contents,
			@"systemInstruction": @{@"parts": @[@{@"text": SXComposeSystemPrompt(prefs, toolDefs)}]},
			@"generationConfig": @{@"temperature": @(prefs.temperature)},
		} mutableCopy];
		if (declarations.count) body[@"tools"] = @{@"functionDeclarations": declarations};

		NSString *text = nil;
		NSArray *functionCalls = nil;

		if (streamThisRound) {
			NSTimeInterval streamBudget = MIN(remaining, MAX(4.0, remaining * 0.65));
			NSError *streamError = nil;
			NSDictionary *streamResp = [SXStream postJSON:body
													toURL:streamURL
												  headers:headers
												   format:SXStreamFormatGemini
												  timeout:streamBudget
											   idleTimeout:MIN(12.0, streamBudget)
													 onDelta:onDelta
													  error:&streamError];
			if (!streamResp) {
				SXLogWrn(@"llm", @"gemini stream lỗi (%@) → non-stream", streamError.localizedDescription);
				if (SXStreamSalvage(streamError.userInfo[@"sx.partial"], @"gemini", model, rounds, start, completion)) return;
				streamAllowed = NO;
				continue;
			}
			lastStatus = [streamResp[@"status"] integerValue];
			if (lastStatus >= 200 && lastStatus < 300) {
				text = [streamResp[@"content"] isKindOfClass:[NSString class]] ? streamResp[@"content"] : nil;
				functionCalls = [streamResp[@"functionCalls"] isKindOfClass:[NSArray class]]
					? streamResp[@"functionCalls"] : nil;
				if (!functionCalls.count && text.length) {
					NSDictionary *info = SXInfo(@"gemini", model, lastStatus, rounds, start);
					NSInteger firstToken = [streamResp[@"firstTokenMs"] integerValue];
					SXLogInf(@"llm", @"gemini OK (stream) — token đầu %ld ms · tổng %ld ms · %lu ký tự",
							 (long)firstToken, (long)[info[@"ms"] integerValue], (unsigned long)text.length);
					completion(text, nil, info);
					return;
				}
				if (!functionCalls.count) {
					streamAllowed = NO;
					continue;
				}
			} else if (SXShouldRetry(lastStatus, &retryCount, deadline)) {
				continue;
			} else if (lastStatus == 400 || lastStatus == 404 || lastStatus == 405 ||
					   lastStatus == 415 || lastStatus == 501) {
				SXLogWrn(@"llm", @"gemini stream không khả dụng (HTTP %ld) → non-stream", (long)lastStatus);
				streamAllowed = NO;
				continue;
			} else {
				NSString *errorText = [streamResp[@"errorText"] isKindOfClass:[NSString class]]
					? streamResp[@"errorText"] : nil;
				NSData *errData = [errorText dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
				NSError *err = [SXHTTP errorWithStatus:lastStatus data:errData];
				SXLogErr(@"llm", @"gemini stream HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
				return;
			}
		} else {
			SXHTTPResult *result = [SXHTTP postURL:url body:body headers:headers
										   timeout:remaining idleTimeout:MIN(30.0, remaining) onData:nil];
			if (result.error && result.status == 0) {
				SXLogErr(@"llm", @"gemini lỗi mạng: %@", result.error.localizedDescription);
				completion(nil, result.error, SXInfo(@"gemini", model, 0, rounds, start));
				return;
			}
			lastStatus = result.status;
			if (lastStatus < 200 || lastStatus >= 300) {
				if (SXShouldRetry(lastStatus, &retryCount, deadline)) continue;
				NSString *fallback = SXFallbackModel(SXProviderGemini);
				if (lastStatus == 404 && rounds == 0 && ![model isEqualToString:fallback]) {
					SXLogWrn(@"llm", @"gemini: model %@ không có (404) → thử %@", model, fallback);
					model = fallback;
					retryCount = 0;
					continue;
				}
				NSError *err = [SXHTTP errorWithStatus:lastStatus data:result.body];
				SXLogErr(@"llm", @"gemini HTTP %ld: %@", (long)lastStatus, err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
				return;
			}
			retryCount = 0;

			id json = [NSJSONSerialization JSONObjectWithData:result.body options:0 error:NULL];
			NSDictionary *candidate = nil;
			if ([json isKindOfClass:[NSDictionary class]] &&
				[((NSDictionary *)json)[@"candidates"] isKindOfClass:[NSArray class]] &&
				[((NSDictionary *)json)[@"candidates"] count] &&
				[((NSDictionary *)json)[@"candidates"][0] isKindOfClass:[NSDictionary class]]) {
				candidate = ((NSDictionary *)json)[@"candidates"][0];
			}
			if (!candidate) {
				NSString *reason = nil;
				if ([json isKindOfClass:[NSDictionary class]]) {
					id feedback = ((NSDictionary *)json)[@"promptFeedback"];
					if ([feedback isKindOfClass:[NSDictionary class]]) {
						id block = ((NSDictionary *)feedback)[@"blockReason"];
						if ([block isKindOfClass:[NSString class]]) reason = block;
					}
				}
				NSError *err = reason.length
					? [SXHTTP errorWithCode:-5 message:[NSString stringWithFormat:
						@"Gemini chặn yêu cầu này (%@). Hãy hỏi lại khác đi.", reason]]
					: [SXHTTP errorWithStatus:lastStatus data:result.body];
				SXLogErr(@"llm", @"%@", err.localizedDescription);
				completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
				return;
			}
			NSDictionary *content = [candidate[@"content"] isKindOfClass:[NSDictionary class]]
				? candidate[@"content"] : nil;
			NSArray *parts = [content[@"parts"] isKindOfClass:[NSArray class]] ? content[@"parts"] : @[];
			NSMutableString *buffer = [NSMutableString string];
			NSMutableArray *calls = [NSMutableArray array];
			for (id part in parts) {
				if (![part isKindOfClass:[NSDictionary class]]) continue;
				if ([((NSDictionary *)part)[@"text"] isKindOfClass:[NSString class]]) {
					[buffer appendString:((NSDictionary *)part)[@"text"]];
				}
				if ([((NSDictionary *)part)[@"functionCall"] isKindOfClass:[NSDictionary class]]) {
					[calls addObject:((NSDictionary *)part)[@"functionCall"]];
				}
			}
			text = buffer.length ? [buffer copy] : nil;
			functionCalls = calls;
		}

		if (functionCalls.count && executor && rounds < SXToolRoundLimit(prefs)) {
			rounds++;
			retryCount = 0;
			NSMutableArray *modelParts = [NSMutableArray array];
			if (text.length) [modelParts addObject:@{@"text": text}];
			for (NSDictionary *call in functionCalls) {
				if ([call isKindOfClass:[NSDictionary class]]) [modelParts addObject:@{@"functionCall": call}];
			}
			[contents addObject:@{@"role": @"model", @"parts": modelParts}];
			SXAppendGeminiToolResults(contents, executor, functionCalls, rounds);
			continue;
		}

		if (!text.length) {
			NSError *err = [SXHTTP errorWithCode:-4 message:@"Model trả về nội dung rỗng."];
			SXLogErr(@"llm", @"%@", err.localizedDescription);
			completion(nil, err, SXInfo(@"gemini", model, lastStatus, rounds, start));
			return;
		}
		NSDictionary *info = SXInfo(@"gemini", model, lastStatus, rounds, start);
		SXLogInf(@"llm", @"gemini OK — %ld ms, %ld vòng công cụ, %lu ký tự",
				 (long)[info[@"ms"] integerValue], (long)rounds, (unsigned long)text.length);
		completion(text, nil, info);
		return;
	}
}

#pragma mark - Điểm vào

@interface SXLLM ()
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)tools
		   executor:(SXToolExec)executor
		   provider:(SXProvider)provider
			onDelta:(SXLLMDelta)onDelta
		 completion:(SXLLMCompletion)completion;
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)tools
		   executor:(SXToolExec)executor
			onDelta:(SXLLMDelta)onDelta
		 completion:(SXLLMCompletion)completion;
@end

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
			onDelta:(SXLLMDelta)onDelta
		 completion:(SXLLMCompletion)completion {
	[self askQuestion:question history:history tools:tools executor:executor
			 provider:[SXPrefs shared].provider onDelta:onDelta completion:completion];
}

+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)tools
		   executor:(SXToolExec)executor
		   provider:(SXProvider)provider
		 completion:(SXLLMCompletion)completion {
	[self askQuestion:question history:history tools:tools executor:executor
			 provider:provider onDelta:nil completion:completion];
}

+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)tools
		   executor:(SXToolExec)executor
		   provider:(SXProvider)provider
			onDelta:(SXLLMDelta)onDelta
		 completion:(SXLLMCompletion)completion {
	if (!completion) return;
	SXPrefs *prefs = [SXPrefs shared];
	NSString *key = [(provider == SXProviderGemini ? [prefs geminiKey] : [prefs openaiKey])
					 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if (!key.length) {
		NSString *providerName = provider == SXProviderGemini ? @"Gemini" : @"OpenAI tương thích";
		NSError *err = [SXHTTP errorWithCode:-1000 message:[NSString stringWithFormat:
			@"Chưa đặt khóa API cho %@. Mở Cài đặt → SiriX → Cấu hình OpenAI / Cấu hình Gemini rồi dán khóa.",
			providerName]];
		SXLogWrn(@"llm", @"bỏ yêu cầu — %@", err.localizedDescription);
		completion(nil, err, nil);
		return;
	}
	question = [question stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!question.length) {
		completion(nil, [SXHTTP errorWithCode:-1001 message:@"Câu hỏi rỗng."], nil);
		return;
	}

	[SXTools beginTurn];
	NSArray<NSDictionary *> *definitions = tools ?: @[];
	if (provider == SXProviderGemini) {
		SXAskGemini(prefs, question, history ?: @[], definitions, executor, onDelta, completion);
	} else {
		SXAskOpenAI(prefs, question, history ?: @[], definitions, executor, onDelta, completion);
	}
}

@end
