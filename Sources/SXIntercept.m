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
			if (original.length > 1000) original = [[original substringToIndex:1000] stringByAppendingString:@"…"];
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
	if (text.length > 800) text = [[text substringToIndex:800] stringByAppendingString:@"…"];
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

	if (canSpeak) {
		id old = SXMsg(view, speakableSelector);
		[rollback addObject:^{ SXSet(view, setSpeakableSelector, old); }];
		SXSet(view, setSpeakableSelector, speechText);
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
/// Ghi nhớ các giá trị cũ trước setter để cố gắng khôi phục nếu API riêng
/// của Apple ném exception (không giả định ACE object hỗ trợ NSCopying).
static BOOL SXMutateCommand(id command, NSString *displayText, NSString *speechText,
							NSString *source, NSString *className) {
	if (!displayText.length || !command) return NO;
	if (!speechText.length) speechText = displayText;
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
				BOOL hideCards = [SXPrefs shared].hideWebCards;
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
				changed = YES;
			}
		}
	}
	} @catch (NSException *exception) {
		BOOL rollbackFailed = NO;
		for (void (^undo)(void) in [rollback reverseObjectEnumerator]) {
			@try { undo(); } @catch (NSException *ignored) { rollbackFailed = YES; }
		}
		SXLogErr(@"err", @"%@: sửa %@ lỗi %@: %@ — khôi phục %@",
				 source, className, exception.name, exception.reason,
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

#pragma mark - Trạng thái

@interface SXIntercept () {
	NSCondition *_condition;
	uint64_t _generation;
	BOOL _pending;
	BOOL _consumed; // quyết định đã chọn cho lượt này (không chỉ cho một lệnh ACE)
	NSString *_decisionDisplay;
	NSString *_decisionSpeech;
	NSTimeInterval _decisionTime;
	BOOL _decisionIsAnswer;
	BOOL _historySaved;
	NSHashTable *_handledCommands; // cùng object có thể đi qua cả hai hook
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
		_handledCommands = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
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

	// Prefix mode mặc định để Siri xử lý; luôn hủy lượt cũ khi bỏ qua để
	// không gắn đáp án cũ vào một yêu cầu không có tiền tố.
	if ([prefs.triggerMode isEqualToString:@"prefix"]) {
		NSString *lower = clean.lowercaseString;
		BOOL hasAI = [lower hasPrefix:@"@ai"] && (lower.length == 3 || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[lower characterAtIndex:3]]);
		if (!hasAI) {
			_generation++;
			_pending = NO;
			[_condition broadcast];
			[_condition unlock];
			SXLogInf(@"capture", @"bỏ qua câu không có tiền tố @ai — dùng Siri gốc (%@)", source);
			return;
		}
		clean = [[clean substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!clean.length) {
			_generation++;
			_pending = NO;
			[_condition broadcast];
			[_condition unlock];
			SXLogInf(@"capture", @"tiền tố @ai không có câu hỏi — dùng Siri gốc");
			return;
		}
	}

	_generation++;
	uint64_t myGeneration = _generation;
	_question = clean;
	_captureTime = now;
	_pending = YES;
	_consumed = NO;
	_decisionDisplay = nil;
	_decisionSpeech = nil;
	_decisionTime = 0;
	_decisionIsAnswer = NO;
	_historySaved = NO;
	[_handledCommands removeAllObjects];
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
		if (_pending) {
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

	if (!_pending) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: không có câu hỏi đang chờ — cho qua (%@)", source, className);
		return NO;
	}
	uint64_t myGeneration = _generation;
	if ([_handledCommands containsObject:command]) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: lệnh đã được sửa ở hook khác (%@)", source, className);
		return YES;
	}

	// Tác vụ Apple luôn ưu tiên, kể cả chế độ thay mọi câu. Kiểm tra lại sau
	// khi chờ vì một luồng khác có thể nhận lệnh tác vụ trong lúc này.
	if (_actionSeen) {
		_consumed = YES;
		_decisionDisplay = nil;
		[_condition unlock];
		SXLogInf(@"resp", @"%@: có tác vụ hệ thống — giữ Siri gốc (%@)", source, className);
		return NO;
	}

	if (!_consumed) {
		// Chặn ACE tối đa 5s, kể cả khi timeout cấu hình lớn hơn.
		NSTimeInterval elapsed = _captureTime > 0 ? (CFAbsoluteTimeGetCurrent() - _captureTime) : 0;
		NSTimeInterval waitBudget = MIN(5.0, MAX(0.0, prefs.responseTimeout - elapsed));
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:waitBudget];
		while (!_ready && !_errored && !_consumed && _generation == myGeneration && !_actionSeen) {
			if (![_condition waitUntilDate:deadline]) break;
		}
		if (_generation != myGeneration) {
			[_condition unlock];
			SXLogDbg(@"resp", @"%@: câu hỏi mới — bỏ lượt chờ cũ", source);
			return NO;
		}
		if (_actionSeen) {
			_consumed = YES;
			_decisionDisplay = nil;
			[_condition unlock];
			SXLogInf(@"resp", @"%@: phát hiện tác vụ trong lúc chờ — giữ Siri gốc", source);
			return NO;
		}
		// Một hook khác có thể đã quyết định trong lúc condition nhả lock.
		if (!_consumed) {
			_consumed = YES;
			_decisionTime = CFAbsoluteTimeGetCurrent();
			[_condition broadcast];
			if (_ready && _answer.length && _answerDisplay.length) {
				_decisionIsAnswer = YES;
				_decisionSpeech = _answer;
				_decisionDisplay = prefs.markdown ? SXMarkdownRender(_answerDisplay) : _answerDisplay;
				if (!prefs.markdown && _decisionDisplay.length > 2000)
					_decisionDisplay = [[_decisionDisplay substringToIndex:2000] stringByAppendingString:@"…"];
				[SXDisplayPolicy logDecision:@"chọn đáp án AI cho lượt" source:source];
			} else if (_errored) {
				if ([SXDisplayPolicy shouldShowErrorBubbleInMode:prefs.mode speakErrors:prefs.speakErrors]) {
					_decisionDisplay = [NSString stringWithFormat:@"⚠️ SiriX gặp lỗi: %@", _answerError.localizedDescription];
					_decisionSpeech = _decisionDisplay;
					[SXDisplayPolicy logDecision:@"bubble lỗi" source:source];
				} else {
					SXLogInf(@"resp", @"%@: AI lỗi (%@) — giữ Siri gốc", source, _answerError.localizedDescription);
				}
			} else {
				_decisionDisplay = [SXDisplayPolicy timeoutBubbleMessageInMode:prefs.mode action:prefs.timeoutAction];
				_decisionSpeech = _decisionDisplay;
				SXLogWrn(@"resp", @"%@: hết ngân sách %.0fs (chặn ≤5s, thực tế %.1fs) — %@",
						 source, prefs.responseTimeout, waitBudget, _decisionDisplay ? @"bubble hết giờ" : @"giữ Siri gốc");
			}
		}
	}

	// AddViews, SayIt và hook dự phòng có thể là nhiều object cho cùng một lượt.
	// Dùng cùng quyết định thay vì cho các lệnh sau lọt về Siri gốc. Hết hạn
	// sau 30 giây để không áp dụng nhầm cho một phiên không bắt được capture.
	if (!_decisionDisplay.length || CFAbsoluteTimeGetCurrent() - _decisionTime > 30.0) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: quyết định giữ gốc hoặc đã hết hạn (%@)", source, className);
		return NO;
	}
	if ([_handledCommands containsObject:command]) {
		[_condition unlock];
		return YES;
	}
	BOOL changed = NO;
	@try {
		NSString *display = _decisionDisplay;
		if (_decisionIsAnswer && prefs.showOriginal) {
			NSString *original = SXOriginalResponse(command, className);
			if (original.length) display = [display stringByAppendingFormat:@"\n—\nSiri: %@", original];
		}
		changed = SXMutateCommand(command, display, _decisionSpeech, source, className);
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"%@: mutate %@ exception %@: %@ — cho qua", source, className, exception.name, exception.reason);
	}
	if (changed) {
		[_handledCommands addObject:command];
		// Chỉ thêm lịch sử khi thực sự sửa được phản hồi AI, và chỉ một lần.
		if (_decisionIsAnswer && !_historySaved) {
			[_history addObject:@{@"q": _question ?: @"",
				@"a": _answerDisplay.length > 1000 ? [[_answerDisplay substringToIndex:1000] stringByAppendingString:@"…"] : _answerDisplay}];
			while ((NSInteger)_history.count > prefs.contextTurns) [_history removeObjectAtIndex:0];
			_historySaved = YES;
		}
	}
	[_condition unlock];
	return changed;
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
