#import "SXIntercept.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXTools.h"
#import "SXMarkdown.h"
#import "SXDisplayPolicy.h"
#import "SXStore.h"
#import "SXNative.h"
#import "SXTTS.h"
#import <objc/message.h>
#import <notify.h>

#pragma mark - Tiện ích

static id SXMsg(id object, SEL selector) {
	if (!object || ![object respondsToSelector:selector]) return nil;
	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static void SXSet(id object, SEL selector, id value) {
	if (object && [object respondsToSelector:selector]) {
		((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
	}
}

/// Lệnh ACE tác vụ hệ thống — Siri gốc phải tự xử lý, không được can thiệp.
static BOOL SXIsActionClass(NSString *className) {
	static NSArray<NSString *> *needles;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		needles = @[@"Alarm", @"Timer", @"Call", @"Message", @"Mail", @"Email", @"Event",
					@"Reminder", @"Activity", @"OpenApp", @"Punchout", @"Route",
					@"Navigation", @"Voicemail", @"Playback", @"NowPlaying", @"Phone",
					@"Maps", @"Contact", @"Workflow"];
	});
	for (NSString *needle in needles) {
		if ([className containsString:needle]) return YES;
	}
	return NO;
}

static BOOL SXIsCardView(id view) {
	NSString *name = NSStringFromClass([view class]);
	if ([name containsString:@"Card"]) return YES;
	SEL groupSelector = NSSelectorFromString(@"groupIdentifier");
	id group = SXMsg(view, groupSelector);
	if ([group isKindOfClass:[NSString class]] && [group isEqualToString:@"com.apple.ace.ui.card"]) return YES;
	return NO;
}

// Snapshot trước khi sửa; chỉ nối vào bản hiển thị, không đọc lại bằng TTS.
static NSString *SXOriginalResponse(id command, NSString *className) {
	if (![className containsString:@"AddViews"]) return nil;
	id views = SXMsg(command, NSSelectorFromString(@"views"));
	if (![views isKindOfClass:[NSArray class]]) return nil;
	for (id view in views) {
		if (SXIsCardView(view)) continue;
		id value = SXMsg(view, NSSelectorFromString(@"text"));
		if (![value isKindOfClass:[NSString class]] || ![value length])
			value = SXMsg(view, NSSelectorFromString(@"speakableText"));
		if ([value isKindOfClass:[NSString class]] && [value length]) {
			NSString *original = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
			if (original.length > 1000) original = SXShort(original, 1000);
			if (original.length) return original;
		}
	}
	return nil;
}

/// Gõ lại câu trả lời thành văn bản thuần để Siri phát thành giọng nói tự nhiên.
static NSString *SXSanitizeAnswer(NSString *raw) {
	if (!raw.length) return @"";
	NSString *text = raw;

	static NSRegularExpression *linkPattern, *markdownChars, *whitespace;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		linkPattern = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\([^)]*\\)"
															   options:0 error:NULL];
		markdownChars = [NSRegularExpression regularExpressionWithPattern:@"[`#*_~]"
																  options:0
																	error:NULL];
		whitespace = [NSRegularExpression regularExpressionWithPattern:@"\\s+"
															   options:0
																 error:NULL];
	});
	NSRange full = NSMakeRange(0, text.length);
	text = [linkPattern stringByReplacingMatchesInString:text options:0 range:full withTemplate:@"$1"];
	text = [markdownChars stringByReplacingMatchesInString:text options:0
													range:NSMakeRange(0, text.length) withTemplate:@""];
	text = [whitespace stringByReplacingMatchesInString:text options:0
												 range:NSMakeRange(0, text.length) withTemplate:@" "];
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (text.length > 800) text = SXShort(text, 800);
	return text;
}

/// Thay text của view: `speakableText` nhận BẢN ĐỌC (thuần, không markdown),
/// `text` nhận BẢN HIỂN THỊ (đã render markdown nếu bật).
/// Quy tắc: nếu view có chữ ở MỘT trong hai trường → ghi CẢ HAI
/// (trường trống cũng được điền — tránh bubble hiển thị rỗng hoặc TTS đọc nhầm markdown).
static BOOL SXApplyTextToView(id view, NSString *displayText, NSString *speechText,
							  NSMutableArray<void (^)(void)> *rollback) {
	SEL speakableSelector = NSSelectorFromString(@"speakableText");
	SEL setSpeakableSelector = NSSelectorFromString(@"setSpeakableText:");
	SEL textSelector = NSSelectorFromString(@"text");
	SEL setTextSelector = NSSelectorFromString(@"setText:");
	BOOL canSpeak = [view respondsToSelector:setSpeakableSelector];
	BOOL canText = [view respondsToSelector:setTextSelector];

	BOOL hasContent = NO;
	if (canSpeak) {
		id current = SXMsg(view, speakableSelector);
		if ([current isKindOfClass:[NSString class]] && ((NSString *)current).length) hasContent = YES;
	}
	if (!hasContent && canText) {
		id current = SXMsg(view, textSelector);
		if ([current isKindOfClass:[NSString class]] && ((NSString *)current).length) hasContent = YES;
	}
	if (!hasContent) return NO;
	if (speechText.length == 0 && (!canSpeak || !canText))
		[NSException raise:@"SXSpeechFieldsUnavailable" format:@"Missing speech or display setter"];

	if (canSpeak) {
		id old = SXMsg(view, speakableSelector);
		[rollback addObject:^{ SXSet(view, setSpeakableSelector, old); }];
		SXSet(view, setSpeakableSelector, speechText);
		if (!speechText.length && [SXMsg(view, speakableSelector) length]) [NSException raise:@"SXSpeechFieldsUnavailable" format:@"Speech was not cleared"];
	}
	if (canText) {
		id old = SXMsg(view, textSelector);
		[rollback addObject:^{ SXSet(view, setTextSelector, old); }];
		SXSet(view, setTextSelector, displayText);
	}
	return YES;
}

/// Tạo bong bóng trả lời của SiriX khi lệnh không có sẵn trường văn bản
/// (ví dụ Apple chỉ gửi thẻ tìm kiếm — đã ẩn — hoặc rỗng).
static id SXMakeUtteranceView(NSString *displayText, NSString *speechText) {
	Class cls = NSClassFromString(@"SAUIAssistantUtteranceView");
	if (!cls) return nil;
	id view = [[cls alloc] init];
	if (!view) return nil;
	BOOL canSet = NO;
	SEL setSpeakable = NSSelectorFromString(@"setSpeakableText:");
	if ([view respondsToSelector:setSpeakable]) {
		SXSet(view, setSpeakable, speechText);
		canSet = YES;
	}
	SEL setText = NSSelectorFromString(@"setText:");
	if (!speechText.length && (!canSet || ![view respondsToSelector:setText])) return nil;
	if ([view respondsToSelector:setText]) {
		SXSet(view, setText, displayText);
		canSet = YES;
	}
	SEL setDialogId = NSSelectorFromString(@"setDialogId:");
	if ([view respondsToSelector:setDialogId]) {
		SXSet(view, setDialogId, NSUUID.UUID.UUIDString);
	}
	SEL setAceId = NSSelectorFromString(@"setAceId:");
	if ([view respondsToSelector:setAceId]) {
		SXSet(view, setAceId, NSUUID.UUID.UUIDString);
	}
	return canSet ? view : nil;
}

/// Thay nội dung tại chỗ: SAUIAddViews.views[*] + SAUISayIt.message.
/// - displayText: bản hiển thị (có thể đã render markdown)
/// - speechText : bản đọc/phát giọng (thuần, markdown đã gỡ)
/// Ghi nhớ các giá trị cũ trước setter để cố gắng khôi phục nếu API riêng
/// của Apple ném exception (không giả định ACE object hỗ trợ NSCopying).
static BOOL SXMutateCommand(id command, NSString *displayText, NSString *speechText,
							NSString *source, NSString *className, BOOL hideCards) {
	if (!displayText.length || !command) return NO;
	if (!speechText) speechText = displayText;
	BOOL isAddViews = [className containsString:@"AddViews"];
	BOOL isSayIt = [className containsString:@"SayIt"];
	BOOL changed = NO;
	NSUInteger stripped = 0;
	NSMutableArray<void (^)(void)> *rollback = [NSMutableArray array];

	@try {
	if (isAddViews) {
		SEL viewsSelector = NSSelectorFromString(@"views");
		SEL setViewsSelector = NSSelectorFromString(@"setViews:");
		if ([command respondsToSelector:viewsSelector] && [command respondsToSelector:setViewsSelector]) {
			NSArray *views = SXMsg(command, viewsSelector);
			if ([views isKindOfClass:[NSArray class]]) {
				NSMutableArray *kept = [NSMutableArray arrayWithCapacity:views.count];
				for (id view in views) {
					if (hideCards && SXIsCardView(view)) {
						stripped++;
						SXLogDbg(@"resp", @"ẩn thẻ: %@", NSStringFromClass([view class]));
						continue;
					}
					[kept addObject:view];
					if (SXApplyTextToView(view, displayText, speechText, rollback)) changed = YES;
				}
				BOOL injected = NO;
				if (!changed) {
					// Không có trường văn bản sẵn (thẻ đã ẩn / rỗng) → chèn bong bóng của SiriX
					// thay vì thả về câu trả lời gốc của Siri.
					id bubble = SXMakeUtteranceView(displayText, speechText);
					if (bubble) {
						[kept insertObject:bubble atIndex:0];
						changed = YES;
						injected = YES;
						SXLogDbg(@"resp", @"chèn bong bóng trả lời (%lu ký tự)", (unsigned long)displayText.length);
					}
				}
				// KHÔNG BAO GIỜ để views = [] (ACE dialog vỡ → giao diện tự đóng).
				// Nếu strip hết mà chèn không được → không sửa gì, trả về Siri gốc (an toàn).
				if ((stripped || injected) && kept.count > 0) {
					[rollback addObject:^{ SXSet(command, setViewsSelector, views); }];
					SXSet(command, setViewsSelector, kept);
				} else if (stripped && kept.count == 0 && !injected) {
					SXLogWrn(@"resp", @"views sẽ rỗng sau khi ẩn thẻ và không chèn được — bỏ thao tác");
					return NO;
				}
			}
		}
	} else if (isSayIt) {
		SEL messageSelector = NSSelectorFromString(@"message");
		SEL setMessageSelector = NSSelectorFromString(@"setMessage:");
		if ([command respondsToSelector:setMessageSelector]) {
			id current = SXMsg(command, messageSelector);
			if ([current isKindOfClass:[NSString class]] && ((NSString *)current).length) {
				[rollback addObject:^{ SXSet(command, setMessageSelector, current); }];
				SXSet(command, setMessageSelector, speechText);
				if (!speechText.length && [SXMsg(command, messageSelector) length]) [NSException raise:@"SXSpeechFieldsUnavailable" format:@"Message was not cleared"];
				changed = YES;
			}
		}
	}
	} @catch (NSException *exception) {
		BOOL rollbackFailed = NO;
		for (void (^undo)(void) in [rollback reverseObjectEnumerator]) {
			@try { undo(); } @catch (NSException *ignored) { rollbackFailed = YES; }
		}
		SXLogErr(@"err", @"%@: sửa %@ lỗi %@ — khôi phục %@",
				 source, className, exception.name,
				 rollbackFailed ? @"không hoàn toàn" : @"giá trị cũ");
		return NO;
	}

	if (changed) {
		SXLogInf(@"resp", @"THAY THẾ — %@ | %@ | %lu ký tự%@",
				 source, className, (unsigned long)displayText.length,
				 stripped ? [NSString stringWithFormat:@" | ẩn %lu thẻ web", (unsigned long)stripped] : @"");
		return YES;
	}
	SXLogWrn(@"resp", @"%@: không có trường văn bản để thay thế trong %@", source, className);
	return NO;
}

#pragma mark - State of one Siri request

static NSTimeInterval SXUptime(void) { return NSProcessInfo.processInfo.systemUptime; }
static const NSTimeInterval SXTurnLimit = 30.0;
static NSString *SXDisplayText(NSString *answer, BOOL markdown, BOOL pending) {
	if (!markdown) return answer.length > 2000 ? SXShort(answer, 2000) : answer;
	if (pending) {
		if (([answer componentsSeparatedByString:@"```"].count - 1) % 2) answer = [answer stringByAppendingString:@"\n```"];
		if (([answer componentsSeparatedByString:@"**"].count - 1) % 2) answer = [answer stringByAppendingString:@"**"];
	}
	return SXMarkdownRender(answer);
}

@interface SXIntercept () {
	NSCondition *_condition;
	uint64_t _generation;
	BOOL _pending, _actionSeen, _decided, _decisionIsAnswer, _deferred, _closed, _streamingView;
	BOOL _outcomeCounted, _historySaved, _skipHistory, _memoryPrivate, _voiceApple, _ttsScheduled, _suppressed;
	NSTimeInterval _captureTime, _captureUptime, _lastCaptureTime, _lastRequestBegin;
	NSString *_lastCaptureText, *_ref, *_question, *_partial, *_streamOriginal;
	NSString *_answer, *_answerDisplay, *_decisionDisplay, *_decisionSpeech;
	NSString *_historyEpoch, *_statsEpoch;
	NSError *_answerError;
	NSNumber *_llmMs;
	SXPrefs *_prefs;
	SXRequest *_request, *_mediaRequest;
	SXTTSPlan *_ttsPlan;
	SXNativeBubble *_nativeBubble;
	NSHashTable *_handledCommands;
	NSMutableArray<NSDictionary *> *_history;
}
@end

@implementation SXIntercept
+ (instancetype)shared {
	static SXIntercept *instance;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ instance = [SXIntercept new]; });
	return instance;
}
- (instancetype)init {
	if ((self = [super init])) {
		_condition = [NSCondition new]; _history = [NSMutableArray array];
		_handledCommands = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
	}
	return self;
}
- (void)setup {
	int token = 0;
	notify_register_dispatch("com.sirix.tweak/resetHistory", &token, dispatch_get_main_queue(), ^(int t) {
		(void)t; [[SXIntercept shared] clearHistoryMemory];
	});
}
- (void)invalidateLocked {
	_generation++;
	[_request cancel]; [_mediaRequest cancel]; _request = nil; _mediaRequest = nil;
	_pending = NO; _actionSeen = NO; _decided = NO; _closed = NO;
	_decisionIsAnswer = NO; _deferred = NO; _streamingView = NO; _suppressed = NO;
	_voiceApple = NO; _ttsScheduled = NO; _outcomeCounted = NO; _historySaved = NO; _skipHistory = NO;
	_ref = nil; _question = nil; _partial = nil; _streamOriginal = nil; _lastCaptureText = nil;
	_answer = nil; _answerDisplay = nil; _answerError = nil; _decisionDisplay = nil; _decisionSpeech = nil;
	_historyEpoch = nil; _statsEpoch = nil; _llmMs = nil; _nativeBubble = nil; _ttsPlan = nil; _prefs = nil;
	[_handledCommands removeAllObjects];
	dispatch_async(dispatch_get_main_queue(), ^{ SXTTSStop(); });
	[_condition broadcast];
}
- (void)beginRequest {
	[_condition lock];
	NSTimeInterval now = SXUptime();
	if (now - _lastRequestBegin >= 0.25 || !_lastRequestBegin) { [self invalidateLocked]; _lastRequestBegin = now; }
	[_condition unlock];
}
- (void)preferencesDidChange {
	[_condition lock];
	[self invalidateLocked];
	[_history removeAllObjects];
	[_condition unlock];
}
- (void)dialogDidDismiss {
	[_condition lock];
	_closed = YES; _nativeBubble = nil; _partial = nil;
	[_mediaRequest cancel];
	if (_streamingView) {
		_streamingView = NO; _deferred = _prefs.deferredReplies && !_prefs.incognito;
		if (_answerDisplay.length && _deferred) [self saveAnswerLocked:YES];
	} else if (!_deferred) { [_request cancel]; _pending = NO; }
	dispatch_async(dispatch_get_main_queue(), ^{ SXTTSStop(); });
	[_condition broadcast]; [_condition unlock];
}
- (void)noteQuestion:(NSString *)text source:(NSString *)source {
	[self noteQuestion:text source:source reference:nil stt:nil];
}
- (void)noteQuestion:(NSString *)text source:(NSString *)source reference:(NSString *)reference stt:(NSString *)outcome {
	NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!clean.length) return;
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	NSString *normalized = clean.lowercaseString;
	[_condition lock];
	NSTimeInterval now = SXUptime();
	if ([_lastCaptureText isEqual:normalized] && now - _lastCaptureTime < 2.5 && (!_ref || !reference || [_ref isEqual:reference])) {
		if (!_ref) _ref = [reference copy];
		[_condition unlock]; return;
	}
	[self invalidateLocked];
	_lastCaptureText = normalized; _lastCaptureTime = now;
	if (!prefs.enabled || prefs.localOnly || SXBypassesAI(clean, prefs.triggerMode)) {
		SXLogDbg(@"capture", @"passthrough (%@)", source);
		[_condition unlock]; return;
	}
	if ([normalized hasPrefix:@"@ai"] && (normalized.length == 3 || [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[normalized characterAtIndex:3]]))
		clean = [[clean substringFromIndex:3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!clean.length) { [_condition unlock]; return; }
	if (prefs.incognito != _memoryPrivate) { [_history removeAllObjects]; _memoryPrivate = prefs.incognito; }
	_prefs = prefs; _question = clean; _ref = [reference copy];
	_captureTime = CFAbsoluteTimeGetCurrent(); _captureUptime = now; _pending = YES;
	uint64_t generation = _generation;
	NSArray *memory = [_history copy];
	NSString *fallback = [prefs fallbackModelForProvider:prefs.provider];
	if ([fallback isEqual:prefs.activeModel]) fallback = @"";
	NSTimeInterval first = prefs.responseTimeout;
	if ([prefs.timeoutAction isEqual:@"retry"] && fallback.length) first = MAX(1, first * 0.65);
	SXRequest *request = [[SXRequest alloc] initWithTimeout:SXTurnLimit firstOutput:first];
	_request = request;
	[_condition unlock];
	SXLogDbg(@"capture", @"lượt %llu (%@); %lu ký tự", (unsigned long long)generation, source, (unsigned long)clean.length);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		__block NSDictionary *stored = nil;
		dispatch_sync([SXStore queue], ^{ stored = [[SXStore shared] snapshot]; });
		[self->_condition lock];
		BOOL current = generation == self->_generation && self->_pending && !self->_actionSeen && !request.cancelled;
		if (current) {
			if (!self->_skipHistory) self->_historyEpoch = stored[@"historyEpoch"];
			self->_statsEpoch = stored[@"statsEpoch"];
			if (outcome.length) [self queueStatistic:outcome milliseconds:nil];
		}
		[self->_condition unlock];
		if (!current) return;
		NSArray *history = prefs.incognito ? memory : (stored[@"history"] ?: memory);
		NSUInteger maxTurns = (NSUInteger)prefs.contextTurns;
		if (history.count > maxTurns) history = [history subarrayWithRange:NSMakeRange(history.count - maxTurns, maxTurns)];
		[self runQuestion:clean history:history prefs:prefs request:request model:nil fallback:fallback generation:generation];
	});
}
- (BOOL)isCurrent:(uint64_t)generation {
	[_condition lock];
	BOOL current = generation == _generation && _pending && !_actionSeen && SXUptime() - _captureUptime < SXTurnLimit;
	[_condition unlock];
	return current;
}
- (void)runQuestion:(NSString *)question history:(NSArray *)history prefs:(SXPrefs *)prefs request:(SXRequest *)request
	model:(NSString *)model fallback:(NSString *)fallback generation:(uint64_t)generation {
	if (![self isCurrent:generation] || request.cancelled) return;
	NSArray *tools = model ? @[] : [SXTools definitionsForPrefs:prefs question:question];
	SXToolExec executor = tools.count ? ^NSDictionary *(NSString *name, NSDictionary *args, NSError **error) {
		if (![self isCurrent:generation] || request.remaining <= 0) { if (error) *error = SXRequestError(request); return nil; }
		return [SXTools execute:name arguments:args question:question request:request error:error];
	} : (SXToolExec)nil;
	[SXLLM performQuestion:question history:history tools:tools executor:executor prefs:prefs provider:prefs.provider model:model prompt:nil maxTokens:0
		request:request progress:^(NSString *partial) { [self receivePartial:partial generation:generation request:request]; }
		completion:^(NSString *answer, NSError *error, NSDictionary *info) {
			if (request.cancelled || ![self isCurrent:generation]) return;
			BOOL timeout = [error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorTimedOut;
			BOOL retryable = timeout ? [prefs.timeoutAction isEqual:@"retry"] : (error && (error.code == -6 || error.code == 404 ||
				error.code == 400 || error.code == 429 || (error.code >= 500 && error.code < 600) || error.code == NSURLErrorNetworkConnectionLost));
			if (fallback.length && retryable) {
				[self->_condition lock];
				NSTimeInterval elapsed = SXUptime() - self->_captureUptime;
				BOOL canRetry = self->_generation == generation && self->_pending && !self->_actionSeen &&
					(!self->_decided || self->_deferred || self->_streamingView) && elapsed < SXTurnLimit - 1;
				if (canRetry) {
					[request cancel]; self->_partial = nil;
					SXRequest *retry = [[SXRequest alloc] initWithTimeout:SXTurnLimit - elapsed firstOutput:MIN(8, MAX(1, prefs.responseTimeout - elapsed))];
					self->_request = retry;
					[self->_condition unlock];
					SXLogInf(@"llm", @"thử một lần với model dự phòng");
					[self runQuestion:question history:history prefs:prefs request:retry model:fallback fallback:nil generation:generation];
					return;
				}
				[self->_condition unlock];
			}
			[self applyAnswer:answer error:error info:info generation:generation];
		}];
}
- (void)receivePartial:(NSString *)partial generation:(uint64_t)generation request:(SXRequest *)request {
	[_condition lock];
	if (_generation == generation && _request == request && _pending && !_actionSeen && !_closed && _prefs.liveSiriUpdates) {
		_partial = [partial copy];
		[_condition broadcast];
		if (_nativeBubble && _streamingView) [self queueNativeUpdateLocked:NO];
	}
	[_condition unlock];
}
- (void)applyAnswer:(NSString *)answer error:(NSError *)error info:(NSDictionary *)info generation:(uint64_t)generation {
	NSString *display = [answer stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (display.length > 4000) display = SXShort(display, 4000);
	NSString *speech = display.length ? SXSanitizeAnswer(display) : nil;
	[_condition lock];
	if (_generation != generation || !_pending || _actionSeen || SXUptime() - _captureUptime >= SXTurnLimit) { [_condition unlock]; return; }
	SXPrefs *prefs = _prefs;
	_llmMs = [info[@"ms"] isKindOfClass:NSNumber.class] ? info[@"ms"] : nil;
	if (!error && speech.length) {
		_answerDisplay = display; _answer = speech;
		if (!_closed && (!_decided || _streamingView || (_deferred && _nativeBubble)) && SXTTSModeAllows(prefs.ttsMode, YES)) {
			if ([prefs.ttsSource isEqual:@"system"] || prefs.incognito || (_deferred && _nativeBubble)) _ttsPlan = SXTTSSystemPlan(speech, prefs);
			else if (!_decided || _streamingView) {
				SXRequest *audio = [[SXRequest alloc] initWithTimeout:2];
				_mediaRequest = audio;
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
					SXTTSPlan *plan = SXTTSPrepare(speech, prefs, audio);
					[self->_condition lock];
					if (generation == self->_generation && self->_mediaRequest == audio && !self->_voiceApple && !self->_closed && !audio.cancelled) self->_ttsPlan = plan;
					[self->_condition unlock];
				});
			}
		}
		if (_deferred && _nativeBubble && !_closed && _decisionDisplay.length) _streamingView = YES;
		if (_streamingView) [self queueNativeUpdateLocked:YES];
		else if (_deferred) [self saveAnswerLocked:YES];
	} else {
		_answerError = error ?: [NSError errorWithDomain:@"com.sirix.llm" code:-6 userInfo:@{NSLocalizedDescriptionKey: @"AI không trả lời."}];
		if (_streamingView) [self queueNativeUpdateLocked:YES];
	}
	[_condition broadcast]; [_condition unlock];
}

#pragma mark - Persistence and deferred output

- (void)queueStatistic:(NSString *)event milliseconds:(NSNumber *)milliseconds {
	NSString *epoch = _statsEpoch;
	NSTimeInterval startedAt = _captureTime;
	if (epoch.length) dispatch_async([SXStore queue], ^{ [[SXStore shared] recordEvent:event milliseconds:milliseconds epoch:epoch startedAt:startedAt]; });
}
- (void)saveAnswerLocked:(BOOL)late {
	if (_historySaved || _skipHistory || !_answerDisplay.length) return;
	_historySaved = YES;
	SXPrefs *prefs = _prefs;
	NSString *question = _question, *answer = _answerDisplay, *epoch = _historyEpoch;
	NSTimeInterval started = _captureTime;
	NSUInteger limit = MAX(1, (NSUInteger)prefs.contextTurns);
	if (!late || !prefs.incognito) {
		[_history addObject:@{@"q": question, @"a": answer}];
		while (_history.count > limit) [_history removeObjectAtIndex:0];
	}
	if (prefs.incognito || !epoch.length) return;
	uint64_t generation = _generation;
	dispatch_async([SXStore queue], ^{
		if ([SXPrefs shared].incognito || [SXPrefs shared].localOnly || (late && ![self isCurrent:generation])) return;
		BOOL saved = [[SXStore shared] appendQuestion:question answer:answer limit:limit epoch:epoch startedAt:started];
		if (late && saved && [self isCurrent:generation] && ![SXPrefs shared].incognito && [SXPrefs shared].deferredReplies) {
			SXLogInf(@"resp", @"đáp án trễ đã lưu; thông báo=%d", SXNotifyHistory());
		}
	});
}
- (NSString *)errorBubbleLocked {
	if (_answerError.code == -1003 || _answerError.code == NSURLErrorNotConnectedToInternet) return @"⚠️ Không có mạng — SiriX không gọi được AI.";
	if (_answerError.code == -6) return @"⚠️ AI không trả lời.";
	if ([_answerError.domain isEqual:NSURLErrorDomain]) return @"⚠️ SiriX không kết nối được với AI.";
	return [@"⚠️ SiriX gặp lỗi: " stringByAppendingString:_answerError.localizedDescription ?: @"Không rõ lỗi."];
}
- (void)queueNativeUpdateLocked:(BOOL)final {
	uint64_t generation = _generation;
	SXNativeBubble *bubble = _nativeBubble;
	BOOL success = _answerDisplay.length && !_answerError;
	NSString *text = final ? (success ? SXDisplayText(_answerDisplay, _prefs.markdown, NO) : [self errorBubbleLocked])
		: SXDisplayText(_partial, _prefs.markdown, YES);
	if (_streamOriginal.length) text = [text stringByAppendingFormat:@"\n—\nSiri: %@", _streamOriginal];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_condition lock];
		BOOL eligible = generation == self->_generation && self->_streamingView && !self->_actionSeen && !self->_closed &&
			bubble == self->_nativeBubble && SXUptime() - self->_captureUptime < SXTurnLimit;
		[self->_condition unlock];
		if (!eligible) return;
		BOOL updated = [bubble updateText:text];
		[self->_condition lock];
		if (generation == self->_generation && self->_streamingView) {
			if (final || !updated) {
				self->_streamingView = NO; self->_nativeBubble = nil;
				if (final && updated) {
					self->_deferred = NO;
					self->_decisionIsAnswer = success;
					self->_decisionDisplay = success ? SXDisplayText(self->_answerDisplay, self->_prefs.markdown, NO) : [self errorBubbleLocked];
					self->_decisionSpeech = success ? self->_answer : @"";
					self->_outcomeCounted = YES;
					if (success) { [self queueStatistic:@"replaced" milliseconds:self->_llmMs]; [self saveAnswerLocked:NO]; }
					else [self queueStatistic:@"error" milliseconds:self->_llmMs];
					if (success && !self->_voiceApple && self->_suppressed && !self->_ttsScheduled) {
						// Siri was already given a silent provisional bubble. Playback is
						// finalized here, even if an online TTS plan missed its deadline.
						if (SXTTSModeAllows(self->_prefs.ttsMode, YES)) {
							BOOL fallback = !self->_ttsPlan && ![self->_prefs.ttsSource isEqual:@"system"];
							[self queueSpeechLocked:(self->_ttsPlan ?: SXTTSSystemPlan(self->_answer, self->_prefs)) fallback:fallback];
						}
					}
				} else {
					self->_decisionDisplay = nil;
					self->_deferred = self->_prefs.deferredReplies && !self->_prefs.incognito;
					if (self->_deferred && self->_answerDisplay.length) [self saveAnswerLocked:YES];
					SXLogDbg(@"resp", @"không cập nhật được bubble Siri; dùng lịch sử cho đáp án trễ.");
				}
			}
		}
		[self->_condition unlock];
	});
}
- (void)queueSpeechLocked:(SXTTSPlan *)plan fallback:(BOOL)fallback {
	if (!plan || _ttsScheduled || _closed || _voiceApple) return;
	_ttsScheduled = YES;
	uint64_t generation = _generation;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
		[self->_condition lock];
		BOOL allowed = generation == self->_generation && self->_pending && !self->_actionSeen && !self->_closed && !self->_voiceApple;
		[self->_condition unlock];
		if (!allowed) return;
		SXTTSPlay(plan, ^(BOOL ok) {
			[self->_condition lock];
			if (generation == self->_generation) [self queueStatistic:(ok && !fallback ? @"tts_ok" : @"tts_fb") milliseconds:nil];
			[self->_condition unlock];
		});
	});
}

#pragma mark - ACE display

- (BOOL)handleIncomingCommand:(id)command {
	if (!command || ![SXPrefs shared].enabled) return NO;
	NSString *className = NSStringFromClass([command class]);
	NSString *reference = SXRefID(command);
	if (SXIsActionClass(className)) {
		[_condition lock];
		if (_pending && (!_ref || !reference || [_ref isEqual:reference])) {
			_actionSeen = YES; [_request cancel]; [_mediaRequest cancel];
			dispatch_async(dispatch_get_main_queue(), ^{ SXTTSStop(); });
			[_condition broadcast];
		}
		[_condition unlock];
		return NO;
	}
	if ([className isEqual:@"SAPreSynthesizeTTS"]) {
		[_condition lock];
		BOOL suppress = _pending && !_closed && !_actionSeen && _suppressed && !_voiceApple && reference && [_ref isEqual:reference];
		BOOL changed = suppress && SXSilentPreSynthesis(command);
		if (suppress && !changed) {
			_voiceApple = YES;
			dispatch_async(dispatch_get_main_queue(), ^{ SXTTSStop(); });
		}
		[_condition unlock];
		return changed;
	}
	if (![className containsString:@"AddViews"] && ![className containsString:@"SayIt"]) return NO;
	// Only the insertion hook has a real AFConversation. Do not wait twice.
	if ([className containsString:@"AddViews"] && [SXPrefs shared].liveSiriUpdates && NSThread.isMainThread &&
		[NSClassFromString(@"AFConversation") instancesRespondToSelector:@selector(addItemsForAddViewsCommand:)]) return NO;
	return [self awaitAndMutate:command source:@"AFConnection" className:className bubble:nil];
}
- (BOOL)handleAddViewsInsertion:(id)command { return [self handleAddViewsInsertion:command conversation:nil]; }
- (BOOL)handleAddViewsInsertion:(id)command conversation:(id)conversation {
	if (!command || ![SXPrefs shared].enabled) return NO;
	NSString *className = NSStringFromClass([command class]);
	if (![className containsString:@"AddViews"]) return NO;
	SXNativeBubble *bubble = conversation && [SXPrefs shared].liveSiriUpdates ? [SXNativeBubble bubbleInConversation:conversation command:command] : nil;
	return [self awaitAndMutate:command source:@"AFConversation" className:className bubble:bubble];
}
- (BOOL)awaitAndMutate:(id)command source:(NSString *)source className:(NSString *)className bubble:(SXNativeBubble *)bubble {
	NSString *reference = SXRefID(command);
	[_condition lock];
	if (!_pending || _actionSeen || _closed || SXUptime() - _captureUptime >= SXTurnLimit || (_ref && reference && ![_ref isEqual:reference])) {
		[_condition unlock]; return NO;
	}
	if (!_ref) _ref = [reference copy];
	if ([_handledCommands containsObject:command]) { [_condition unlock]; return YES; }
	uint64_t generation = _generation;
	if (!_decided) {
		// Main/ACE never waits for ongoing streaming beyond this budget.
		NSTimeInterval remaining = MAX(0, _prefs.responseTimeout - (SXUptime() - _captureUptime));
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MIN(5.0, remaining)];
		// A provisional bubble is silent. Only use it if final playback has a
		// supported local fallback, not when the user asked for Apple's voice.
		BOOL canPreview = bubble && SXTTSModeAllows(_prefs.ttsMode, YES);
		while (!_answerDisplay && !_answerError && !(canPreview && _partial.length) && !_decided && _pending && !_closed && !_actionSeen && generation == _generation)
			if (![_condition waitUntilDate:deadline]) break;
		if (generation != _generation || !_pending || _closed || _actionSeen) { [_condition unlock]; return NO; }
		if ([_handledCommands containsObject:command]) { [_condition unlock]; return YES; }
		if (!_decided) {
			_decided = YES;
			BOOL canSpeakError = SXTTSModeAllows(_prefs.ttsMode, NO);
			if (_answerDisplay.length) {
				_decisionIsAnswer = YES; _decisionDisplay = SXDisplayText(_answerDisplay, _prefs.markdown, NO); _decisionSpeech = _answer;
			} else if (canPreview && _partial.length && !_answerError) {
				_streamingView = YES; _nativeBubble = bubble;
				_decisionDisplay = SXDisplayText(_partial, _prefs.markdown, YES); _decisionSpeech = @"";
			} else if (_answerError && _answerError.code != NSURLErrorTimedOut) {
				[self queueStatistic:@"error" milliseconds:_llmMs];
				if ([SXDisplayPolicy shouldShowErrorBubbleInMode:_prefs.mode speakErrors:canSpeakError]) _decisionDisplay = [self errorBubbleLocked];
				_decisionSpeech = canSpeakError ? _decisionDisplay : @"";
				if (canSpeakError && _decisionDisplay) _ttsPlan = SXTTSSystemPlan(_decisionDisplay, _prefs);
			} else {
				[self queueStatistic:@"timeout" milliseconds:nil];
				_decisionDisplay = [SXDisplayPolicy timeoutBubbleMessageInMode:_prefs.mode action:_prefs.timeoutAction];
				_decisionSpeech = canSpeakError ? _decisionDisplay : @"";
				if (canSpeakError && _decisionDisplay) _ttsPlan = SXTTSSystemPlan(_decisionDisplay, _prefs);
				_deferred = _prefs.deferredReplies && !_answerError && !_prefs.incognito;
				if (!_deferred) { [_request cancel]; [_mediaRequest cancel]; }
			}
			if (!_decisionDisplay.length) { _outcomeCounted = YES; [self queueStatistic:@"kept" milliseconds:nil]; }
			[_condition broadcast];
		}
	}
	if (!_decisionDisplay.length) { [_condition unlock]; return NO; }
	NSString *display = _decisionDisplay;
	if ((_decisionIsAnswer || _streamingView) && _prefs.showOriginal) {
		NSString *original = SXOriginalResponse(command, className);
		if (original.length) {
			display = [display stringByAppendingFormat:@"\n—\nSiri: %@", original];
			if (_streamingView && bubble == _nativeBubble) _streamOriginal = original;
		}
	}
	BOOL custom = _ttsPlan && !_voiceApple && !_streamingView;
	if (_ttsScheduled && _suppressed && !_voiceApple && !_streamingView) custom = YES;
	BOOL silent = custom || _streamingView || (_decisionSpeech && !_decisionSpeech.length);
	BOOL changed = SXMutateCommand(command, display, silent ? @"" : _decisionSpeech, source, className, _prefs.hideWebCards);
	if (!changed && silent) {
		_voiceApple = YES;
		if (_streamingView && bubble == _nativeBubble) {
			_streamingView = NO; _nativeBubble = nil; _deferred = _prefs.deferredReplies && !_prefs.incognito; _decisionDisplay = nil;
		} else if (!_streamingView) changed = SXMutateCommand(command, display, _decisionSpeech.length ? _decisionSpeech : display, source, className, _prefs.hideWebCards);
		custom = NO;
	}
	if (changed) {
		[_handledCommands addObject:command];
		if (silent && !_voiceApple) _suppressed = YES;
		if (_deferred && bubble && !_nativeBubble && !_decisionIsAnswer && !_answerError) _nativeBubble = bubble;
		if (!_streamingView && !_outcomeCounted) {
			_outcomeCounted = YES;
			if (_decisionIsAnswer) [self queueStatistic:@"replaced" milliseconds:_llmMs];
		}
		if (custom) [self queueSpeechLocked:_ttsPlan fallback:NO];
		else if (_decisionIsAnswer && SXTTSModeAllows(_prefs.ttsMode, YES) && !_voiceApple) {
			_voiceApple = YES; [_mediaRequest cancel]; [self queueStatistic:@"tts_fb" milliseconds:nil];
		}
		if (_decisionIsAnswer) [self saveAnswerLocked:NO];
	}
	[_condition unlock];
	return changed;
}
- (void)clearHistoryMemory {
	[_condition lock];
	_historyEpoch = nil; _skipHistory = YES;
	[_history removeAllObjects];
	[_condition unlock];
}
- (BOOL)clearHistory {
	[self clearHistoryMemory];
	__block BOOL ok = NO;
	dispatch_sync([SXStore queue], ^{ ok = [[SXStore shared] clearHistory]; });
	if (ok) notify_post("com.sirix.tweak/resetHistory");
	return ok;
}
@end
