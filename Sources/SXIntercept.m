#import "SXIntercept.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXTools.h"
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

static BOOL SXApplyTextToView(id view, NSString *text) {
	BOOL applied = NO;
	SEL speakableSelector = NSSelectorFromString(@"speakableText");
	SEL setSpeakableSelector = NSSelectorFromString(@"setSpeakableText:");
	if ([view respondsToSelector:setSpeakableSelector]) {
		id current = SXMsg(view, speakableSelector);
		if ([current isKindOfClass:[NSString class]] && ((NSString *)current).length) {
			SXSet(view, setSpeakableSelector, text);
			applied = YES;
		}
	}
	SEL textSelector = NSSelectorFromString(@"text");
	SEL setTextSelector = NSSelectorFromString(@"setText:");
	if ([view respondsToSelector:setTextSelector]) {
		id current = SXMsg(view, textSelector);
		if ([current isKindOfClass:[NSString class]] && ((NSString *)current).length) {
			SXSet(view, setTextSelector, text);
			applied = YES;
		}
	}
	return applied;
}

/// Thay nội dung tại chỗ: SAUIAddViews.views[*].speakableText/text + SAUISayIt.message.
static BOOL SXMutateCommand(id command, NSString *text, NSString *source, NSString *className) {
	if (!text.length || !command) return NO;
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
					if (SXApplyTextToView(view, text)) changed = YES;
				}
				if (changed && stripped) {
					SXSet(command, setViewsSelector, kept);
				}
			}
		}
	} else if (isSayIt) {
		SEL messageSelector = NSSelectorFromString(@"message");
		SEL setMessageSelector = NSSelectorFromString(@"setMessage:");
		if ([command respondsToSelector:setMessageSelector]) {
			id current = SXMsg(command, messageSelector);
			if ([current isKindOfClass:[NSString class]] && ((NSString *)current).length) {
				SXSet(command, setMessageSelector, text);
				changed = YES;
			}
		}
	}

	if (changed) {
		SXLogInf(@"resp", @"THAY THẾ — %@ | %@ | %lu ký tự%@",
				 source, className, (unsigned long)text.length,
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
	NSString *_answer;
	NSError *_answerError;
	NSMutableArray<NSDictionary *> *_history;
	NSString *_lastCaptureText;
	NSTimeInterval _lastCaptureTime;
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
	_pending = YES;
	_consumed = NO;
	_ready = NO;
	_errored = NO;
	_actionSeen = NO;
	_answer = nil;
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
		_answer = SXSanitizeAnswer(answer);
		if (_answer.length) {
			_ready = YES;
			SXLogDbg(@"resp", @"đáp án #%llu sẵn sàng (%lu ký tự)",
					 (unsigned long long)generation, (unsigned long)_answer.length);
		} else {
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
		if (_pending && !_consumed) _actionSeen = YES;
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

	NSTimeInterval timeout = prefs.responseTimeout;
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!_ready && !_errored && !_consumed && _generation == myGeneration) {
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
	if (_ready && _answer.length) {
		NSString *answer = _answer;
		NSString *question = _question;
		_consumed = YES;
		[_history addObject:@{@"q": question ?: @"", @"a": answer}];
		while ((NSInteger)_history.count > prefs.contextTurns) {
			[_history removeObjectAtIndex:0];
		}
		[_condition unlock];
		return SXMutateCommand(command, answer, source, className);
	}
	if (_errored) {
		NSError *error = _answerError;
		_consumed = YES;
		[_condition unlock];
		if (prefs.speakErrors) {
			NSString *message = [NSString stringWithFormat:@"SiriX gặp lỗi: %@", error.localizedDescription];
			return SXMutateCommand(command, message, source, className);
		}
		SXLogInf(@"resp", @"%@: AI lỗi (%@) — giữ câu trả lời gốc", source, error.localizedDescription);
		return NO;
	}

	// Hết giờ chờ.
	NSString *question = _question;
	_consumed = YES;
	[_condition unlock];
	SXLogWrn(@"resp", @"%@: hết %.0f giây chờ AI (%@) — giữ câu trả lời gốc. Câu hỏi: “%@”",
			 source, timeout, className, SXShort(question, 80));
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
