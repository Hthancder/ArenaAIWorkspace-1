#import "SXIntercept.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXTools.h"
#import "SXMarkdown.h"
#import "SXDisplayPolicy.h"
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
	if (text.length > 800) text = [[text substringToIndex:800] stringByAppendingString:@"…"];
	return text;
}

/// Thay text của view: `speakableText` nhận BẢN ĐỌC (thuần, không markdown),
/// `text` nhận BẢN HIỂN THỊ (đã render markdown nếu bật).
/// Quy tắc: nếu view có chữ ở MỘT trong hai trường → ghi CẢ HAI
/// (trường trống cũng được điền — tránh bubble hiển thị rỗng hoặc TTS đọc nhầm markdown).
static BOOL SXApplyTextToView(id view, NSString *displayText, NSString *speechText) {
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

	if (canSpeak) SXSet(view, setSpeakableSelector, speechText);
	if (canText) SXSet(view, setTextSelector, displayText);
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
		SXSet(view, setSpeakable, speechText.length ? speechText : displayText);
		canSet = YES;
	}
	SEL setText = NSSelectorFromString(@"setText:");
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
/// Mọi thao tác xây giá trị MỚI trước, setter chạy sau (mutate-on-copy) —
/// nếu có bất kỳ phần tử nào hỏng → không gọi setter → bản gốc nguyên vẹn.
static BOOL SXMutateCommand(id command, NSString *displayText, NSString *speechText,
							NSString *source, NSString *className) {
	if (!displayText.length || !command) return NO;
	if (!speechText.length) speechText = displayText;
	BOOL isAddViews = [className containsString:@"AddViews"];
	BOOL isSayIt = [className containsString:@"SayIt"];
	BOOL changed = NO;
	NSUInteger stripped = 0;

	if (isAddViews) {
		SEL viewsSelector = NSSelectorFromString(@"views");
		SEL setViewsSelector = NSSelectorFromString(@"setViews:");
		if ([command respondsToSelector:viewsSelector] && [command respondsToSelector:setViewsSelector]) {
			NSArray *views = SXMsg(command, viewsSelector);
			if ([views isKindOfClass:[NSArray class]]) {
				BOOL hideCards = [SXPrefs shared].hideWebCards;
				NSMutableArray *kept = [NSMutableArray arrayWithCapacity:views.count];
				for (id view in views) {
					if (hideCards && SXIsCardView(view)) {
						stripped++;
						SXLogDbg(@"resp", @"ẩn thẻ: %@", NSStringFromClass([view class]));
						continue;
					}
					[kept addObject:view];
					if (SXApplyTextToView(view, displayText, speechText)) changed = YES;
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
					@try {
						SXSet(command, setViewsSelector, kept);
					} @catch (NSException *exception) {
						SXLogErr(@"resp", @"setViews: exception %@ — giữ bản gốc", exception.name);
						return NO;
					}
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
				@try {
					SXSet(command, setMessageSelector, speechText);
				} @catch (NSException *exception) {
					SXLogErr(@"resp", @"setMessage: exception %@ — giữ bản gốc", exception.name);
					return NO;
				}
				changed = YES;
			}
		}
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

#pragma mark - Trạng thái

@interface SXIntercept () {
	NSCondition *_condition;
	uint64_t _generation;
	BOOL _pending;
	BOOL _consumed;
	BOOL _ready;
	BOOL _errored;
	BOOL _actionSeen;
	NSString *_question;
	NSString *_answer;        // bản đọc (thuần, ≤800 ký tự)
	NSString *_answerDisplay; // bản hiển thị (nguyên văn, ≤4000 ký tự)
	NSError *_answerError;
	NSMutableArray<NSDictionary *> *_history;
	NSString *_lastCaptureText;
	NSTimeInterval _lastCaptureTime;
	NSTimeInterval _captureTime; // mốc0 của ngân sách chờ AI (v1.1)
}
@end

@implementation SXIntercept

+ (instancetype)shared {
	static SXIntercept *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[SXIntercept alloc] init];
	});
	return instance;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_condition = [[NSCondition alloc] init];
		_history = [NSMutableArray array];
	}
	return self;
}

- (void)setup {
	int token = 0;
	notify_register_dispatch("com.sirix.tweak/resetHistory", &token, dispatch_get_main_queue(), ^(int t) {
		[[SXIntercept shared] clearHistory];
	});
}

#pragma mark - Câu hỏi

- (void)noteQuestion:(NSString *)text source:(NSString *)source {
	NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!clean.length) {
		SXLogDbg(@"capture", @"(%@) văn bản rỗng — bỏ qua", source);
		return;
	}

	static NSRegularExpression *whitespace;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		whitespace = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:NULL];
	});
	NSString *normalized = [whitespace stringByReplacingMatchesInString:clean
															   options:0
																 range:NSMakeRange(0, clean.length)
														   withTemplate:@" "].lowercaseString;

	SXPrefs *prefs = [SXPrefs shared];
	[_condition lock];
	if (!prefs.enabled) {
		[_condition unlock];
		SXLogDbg(@"capture", @"tweak đang tắt — bỏ qua “%@”", SXShort(clean, 80));
		return;
	}
	NSTimeInterval now = CFAbsoluteTimeGetCurrent();
	if (_lastCaptureText && [_lastCaptureText isEqualToString:normalized] && now - _lastCaptureTime < 2.5) {
		[_condition unlock];
		SXLogDbg(@"capture", @"trùng lặp trong %.1f giây — bỏ “%@” (nguồn %@)",
				 now - _lastCaptureTime, SXShort(clean, 80), source);
		return;
	}
	_lastCaptureText = normalized;
	_lastCaptureTime = now;

	_generation++;
	uint64_t myGeneration = _generation;
	_question = clean;
	_captureTime = now;
	_pending = YES;
	_consumed = NO;
	_ready = NO;
	_errored = NO;
	_actionSeen = NO;
	_answer = nil;
	_answerDisplay = nil;
	_answerError = nil;
	NSArray<NSDictionary *> *historySnapshot = [_history copy];
	[_condition broadcast]; // đánh thức các lượt chờ của câu hỏi trước

	SXLogInf(@"capture", @"câu hỏi #%llu (%@): “%@”", (unsigned long long)myGeneration, source, clean);
	[_condition unlock];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		// Bỏ nếu đã có câu hỏi mới trước khi kịp gửi.
		[self->_condition lock];
		BOOL stale = (self->_generation != myGeneration);
		[self->_condition unlock];
		if (stale) return;

		SXToolExec executor = ^NSDictionary *(NSString *name, NSDictionary *arguments, NSError **error) {
			if ([name isEqualToString:@"reset_conversation"]) {
				[[SXIntercept shared] clearHistory];
				return @{@"result": @"Đã xóa lịch sử hội thoại."};
			}
			return [SXTools execute:name arguments:arguments error:error];
		};
		[SXLLM askQuestion:clean
				   history:historySnapshot
					 tools:[SXTools definitions]
				   executor:executor
				completion:^(NSString *answer, NSError *error, NSDictionary *info) {
			[self applyAnswer:answer error:error forGeneration:myGeneration];
		}];
	});
}

- (void)applyAnswer:(NSString *)answer error:(NSError *)error forGeneration:(uint64_t)generation {
	[_condition lock];
	if (generation != _generation) {
		[_condition unlock];
		SXLogDbg(@"resp", @"bỏ đáp án cũ (câu hỏi #%llu, hiện tại #%llu)",
				 (unsigned long long)generation, (unsigned long long)_generation);
		return;
	}
	if (error) {
		_errored = YES;
		_answerError = error;
	} else {
		// Bản hiển thị: giữ nguyên văn (render markdown lúc hiển thị), cắt an toàn.
		NSString *raw = [answer stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (raw.length > 4000) raw = [[raw substringToIndex:4000] stringByAppendingString:@"…"];
		_answerDisplay = raw;
		// Bản đọc: gỡ markdown + cắt 800 (đề phòng TTS/LibreSpeech).
		_answer = SXSanitizeAnswer(raw);
		if (_answerDisplay.length && _answer.length) {
			_ready = YES;
			SXLogDbg(@"resp", @"đáp án #%llu sẵn sàng (hiển thị %lu · đọc %lu ký tự)",
					 (unsigned long long)generation,
					 (unsigned long)_answerDisplay.length, (unsigned long)_answer.length);
		} else {
			// Rỗng sau khi xử lý → errored (không bao giờ hiện bubble trống).
			_errored = YES;
			_answerError = [NSError errorWithDomain:@"com.sirix.llm" code:-6
										   userInfo:@{NSLocalizedDescriptionKey: @"Đáp án rỗng sau khi xử lý."}];
		}
	}
	[_condition broadcast];
	[_condition unlock];
}

#pragma mark - Đường vào lệnh ACE

- (BOOL)handleIncomingCommand:(id)command {
	if (!command || ![SXPrefs shared].enabled) return NO;
	NSString *className = NSStringFromClass([command class]);

	if (SXIsActionClass(className)) {
		[_condition lock];
		if (_pending && !_consumed) {
			_actionSeen = YES;
			[_condition broadcast]; // đánh thức luồng đang chờ — thoát ngay, không giữ ACE
		}
		[_condition unlock];
		SXLogDbg(@"resp", @"tác vụ hệ thống — cho Siri gốc xử lý: %@", className);
		return NO;
	}

	BOOL looksLikeResponse = [className containsString:@"AddViews"] || [className containsString:@"SayIt"];
	if (!looksLikeResponse) {
		SXLogDbg(@"resp", @"bỏ qua lệnh không liên quan: %@", className);
		return NO;
	}
	return [self awaitAndMutate:command
						 source:@"AFConnection._handleCommand:reply:"
					  className:className];
}

- (BOOL)handleAddViewsInsertion:(id)command {
	if (!command || ![SXPrefs shared].enabled) return NO;
	NSString *className = NSStringFromClass([command class]);
	if (![className containsString:@"AddViews"]) return NO;
	return [self awaitAndMutate:command
						 source:@"AFConversation.addItemsForAddViewsCommand:"
					  className:className];
}

/// Chờ đáp án (có giới hạn), thay thế tại chỗ, hoặc cho qua — an toàn khi chạy song song.
- (BOOL)awaitAndMutate:(id)command source:(NSString *)source className:(NSString *)className {
	SXPrefs *prefs = [SXPrefs shared];
	[_condition lock];

	if (!_pending || _consumed) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: không có câu hỏi đang chờ — cho qua (%@)", source, className);
		return NO;
	}
	uint64_t myGeneration = _generation;

	if (prefs.mode == SXReplyModeSmart && _actionSeen) {
		_consumed = YES;
		[_condition unlock];
		SXLogInf(@"resp", @"%@: trao đổi có tác vụ hệ thống — giữ câu trả lời gốc (%@)", source, className);
		return NO;
	}

	// Ngân sách chờ = từ lúc hỏi (capture + timeout); CHẶN luồng ACE tối đa5s
	// (hard-cap chống watchdog đóng dialog — DESIGN-SYSTEM §10).
	NSTimeInterval timeout = prefs.responseTimeout;
	NSTimeInterval elapsed = _captureTime > 0 ? (CFAbsoluteTimeGetCurrent() - _captureTime) : 0;
	NSTimeInterval waitBudget = MIN(5.0, MAX(0.0, timeout - elapsed));
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:waitBudget];
	BOOL smartKeep = (prefs.mode == SXReplyModeSmart);
	while (!_ready && !_errored && !_consumed && _generation == myGeneration &&
		   !(smartKeep && _actionSeen)) {
		if (![_condition waitUntilDate:deadline]) break;
	}

	if (_generation != myGeneration) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: đã có câu hỏi mới — bỏ lượt chờ cũ", source);
		return NO;
	}
	if (_consumed) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: câu trả lời đã được xử lý ở luồng khác — cho qua", source);
		return NO;
	}
	if (_ready && _answer.length && _answerDisplay.length) {
		NSString *speech = _answer;
		NSString *raw = _answerDisplay;
		NSString *question = _question;
		_consumed = YES;
		[_history addObject:@{@"q": question ?: @"",
							  @"a": raw.length > 1000 ? [[raw substringToIndex:1000] stringByAppendingString:@"…"] : raw}];
		while ((NSInteger)_history.count > prefs.contextTurns) {
			[_history removeObjectAtIndex:0];
		}
		[_condition unlock];

		NSString *display = raw;
		if (prefs.markdown) {
			display = SXMarkdownRender(raw);
		} else if (display.length > 2000) {
			display = [[display substringToIndex:2000] stringByAppendingString:@"…"];
		}
		[SXDisplayPolicy logDecision:[NSString stringWithFormat:@"thay thế (md=%d, hiển thị %lu ký tự)",
									   prefs.markdown, (unsigned long)display.length]
							   source:source];
		return SXMutateCommand(command, display, speech, source, className);
	}
	if (_errored) {
		NSError *error = _answerError;
		_consumed = YES;
		[_condition unlock];
		if ([SXDisplayPolicy shouldShowErrorBubbleInMode:prefs.mode speakErrors:prefs.speakErrors]) {
			NSString *message = [NSString stringWithFormat:@"⚠️ SiriX gặp lỗi: %@", error.localizedDescription];
			[SXDisplayPolicy logDecision:@"bubble lỗi" source:source];
			return SXMutateCommand(command, message, message, source, className);
		}
		SXLogInf(@"resp", @"%@: AI lỗi (%@) — giữ câu trả lời gốc (chính sách: thông minh, chưa bật báo lỗi)",
				 source, error.localizedDescription);
		return NO;
	}

	// Hết ngân sách chờ.
	NSString *question = _question;
	_consumed = YES;
	[_condition unlock];
	NSString *timeoutMessage = [SXDisplayPolicy timeoutBubbleMessageInMode:prefs.mode
																	 action:prefs.timeoutAction];
	SXLogWrn(@"resp", @"%@: hết ngân sách %.0fs chờ AI (chặn ≤5s, ngân sách %.1fs) (%@) — %@. Câu hỏi: “%@”. "
			 @"Gợi ý: tăng “Thời gian chờ AI” hoặc đổi model nhanh hơn.",
			 source, timeout, waitBudget, className,
			 timeoutMessage ? @"chèn bubble thông báo" : @"giữ câu trả lời gốc",
			 SXShort(question, 80));
	if (timeoutMessage) {
		[SXDisplayPolicy logDecision:@"bubble hết giờ" source:source];
		return SXMutateCommand(command, timeoutMessage, timeoutMessage, source, className);
	}
	return NO;
}

- (void)clearHistory {
	NSUInteger count = 0;
	[_condition lock];
	count = _history.count;
	[_history removeAllObjects];
	[_condition unlock];
	SXLogInf(@"pref", @"đã xóa lịch sử hội thoại (%lu câu)", (unsigned long)count);
}

@end
