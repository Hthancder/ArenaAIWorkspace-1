#import "SXIntercept.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXTools.h"
#import "SXMarkdown.h"
#import "SXDisplayPolicy.h"
#import "SXStore.h"
#import <objc/message.h>
#import <notify.h>
#ifndef SX_TESTING
#import <UserNotifications/UserNotifications.h>
#endif

#pragma mark - Công cụ riêng của tweak

/// `reset_conversation` cần SXIntercept (xoá lịch sử + phát notify) nên không
/// nằm trong SXToolCatalog dùng chung. Đăng ký vào cùng sổ với 12 công cụ kia để
/// model thấy nó trong danh sách và Settings liệt kê được.
static void SXRegisterHostTools(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SXTool *tool = [SXTool toolWithName:@"reset_conversation"
									 title:@"Xoá lịch sử hội thoại"
								   summary:@"Xoá toàn bộ câu hỏi và câu trả lời đã lưu trên máy."
									prompt:@"Dùng khi người dùng muốn xoá hoặc quên lịch sử trò chuyện đã lưu."
								  category:SXToolCategoryMemory
								parameters:@{@"type": @"object", @"properties": @{}, @"required": @[]}
								   handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			(void)arguments;
			if (![[SXIntercept shared] clearHistory]) {
				if (error) {
					*error = [NSError errorWithDomain:SXToolErrorDomain code:1
											userInfo:@{NSLocalizedDescriptionKey: @"Không xoá được lịch sử đã lưu."}];
				}
				return nil;
			}
			return @{@"result": @"Đã xoá lịch sử hội thoại."};
		}];
		tool.sideEffect = YES;
		tool.timeout = 4.0;
		[SXToolkit registerTool:tool];
	});
}

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

static NSString *SXDialogID(id command);      // định nghĩa ở dưới

/// Tạo bong bóng trả lời của SiriX khi lệnh không có sẵn trường văn bản
/// (ví dụ Apple chỉ gửi thẻ tìm kiếm — đã ẩn — hoặc rỗng).
///
/// View mới PHẢI mang cùng `dialogIdentifier` với lệnh ACE đang xử lý: Siri gắn
/// view vào hội thoại theo id này. Một id ngẫu nhiên làm hội thoại không khớp
/// (Siri đóng giao diện / layout truy cập nil) — đây là nguyên nhân nhìn thấy
/// "Siri văng" sau khi AI gọi công cụ xong và câu trả lời được chèn vào.
static id SXMakeUtteranceView(NSString *displayText, NSString *speechText, id command) {
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
	if (!canSet) return nil;

	// Kế thừa id hội thoại của lệnh (nếu có) thay vì bịa id mới.
	NSString *dialogID = SXDialogID(command);
	for (NSString *name in @[@"dialogIdentifier", @"dialogId"]) {
		if (!dialogID.length) break;
		SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",
										   [[name substringToIndex:1] uppercaseString],
										   [name substringFromIndex:1]]);
		if ([view respondsToSelector:setter]) SXSet(view, setter, dialogID);
	}
	SEL setRefId = NSSelectorFromString(@"setRefId:");
	if ([view respondsToSelector:setRefId]) SXSet(view, setRefId, NSUUID.UUID.UUIDString);
	SEL setAceId = NSSelectorFromString(@"setAceId:");
	if ([view respondsToSelector:setAceId]) SXSet(view, setAceId, NSUUID.UUID.UUIDString);
	SEL setListen = NSSelectorFromString(@"setListenAfterSpeaking:");
	if ([view respondsToSelector:setListen]) {
		((void (*)(id, SEL, BOOL))objc_msgSend)(view, setListen, NO);
	}
	return view;
}

/// View có chữ (text hoặc speakableText) — ứng viên để thay.
static BOOL SXViewHasText(id view) {
	if (!view) return NO;
	id value = SXMsg(view, NSSelectorFromString(@"text"));
	if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return YES;
	value = SXMsg(view, NSSelectorFromString(@"speakableText"));
	return [value isKindOfClass:[NSString class]] && [(NSString *)value length];
}

/// Chọn MỘT view chính để thay: ưu tiên Utterance (bong bóng trả lời), nếu không có thì
/// lấy view có chữ cuối cùng. Các view khác giữ nguyên — tránh việc tiêu đề/phụ đề
/// bị đè cùng một nội dung (chữ lặp) khi Apple gửi nhiều view trong một AddViews.
static id SXPrimaryTextView(NSArray *views) {
	id fallback = nil;
	for (id view in views) {
		if (SXIsCardView(view)) continue;
		if (!SXViewHasText(view)) continue;
		NSString *className = NSStringFromClass([view class]);
		if ([className containsString:@"Utterance"]) return view;
		fallback = view;
	}
	return fallback;
}

/// ID hội thoại của lệnh ACE (nếu có) — dùng để không áp quyết định cũ sang lệnh khác.
static NSString *SXDialogID(id command) {
	if (!command) return nil;
	id value = nil;
	@try { value = [command valueForKey:@"dialogIdentifier"]; } @catch (NSException *exception) { value = nil; }
	return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
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
				}
				// Chỉ thay view chính. View khác (tiêu đề, phụ đề…) giữ nguyên văn.
				id primary = SXPrimaryTextView(kept);
				if (primary && SXApplyTextToView(primary, displayText, speechText, rollback)) changed = YES;
				BOOL injected = NO;
				if (!changed) {
					// Không có trường văn bản sẵn (thẻ đã ẩn / rỗng) → chèn bong bóng của SiriX
					// thay vì thả về câu trả lời gốc của Siri.
					id bubble = SXMakeUtteranceView(displayText, speechText, command);
					if (bubble) {
						[kept insertObject:bubble atIndex:0];
						changed = YES;
						injected = YES;
						SXLogDbg(@"resp", @"chèn bong bóng trả lời (%lu ký tự, dialog=%@)",
								 (unsigned long)displayText.length,
								 SXDialogID(command) ?: @"(không có)");
					}
				}
				// KHÔNG BAO GIỜ để views = [] (ACE dialog vỡ → giao diện tự đóng).
				// Nếu strip hết mà chèn không được → không sửa gì, trả về Siri gốc (an toàn).
				if ((stripped || injected) && kept.count > 0) {
					BOOL allValid = YES;
					for (id view in kept) { if (!view) { allValid = NO; break; } }
					if (!allValid) {
						SXLogErr(@"err", @"danh sách view sau khi sửa có phần tử nil — bỏ thao tác");
						return NO;
					}
					[rollback addObject:^{ SXSet(command, setViewsSelector, views); }];
					SXSet(command, setViewsSelector, kept);
					NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:kept.count];
					for (id view in kept) [names addObject:NSStringFromClass([view class])];
					SXLogDbg(@"resp", @"views sau khi sửa (%lu): %@", (unsigned long)kept.count,
							 [names componentsJoinedByString:@", "]);
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
	/// Quyết định đã chọn cho lượt này — áp cho MỌI lệnh AddViews/SayIt cùng hội
	/// thoại, không chỉ lệnh đầu tiên.
	BOOL _decided;
	NSString *_decisionDisplay;
	NSString *_decisionSpeech;
	NSTimeInterval _decisionTime;
	BOOL _decisionIsAnswer;
	NSString *_decisionDialogID;
	BOOL _historySaved;
	BOOL _outcomeCounted;
	BOOL _questionIncognito;
	NSString *_historyEpoch;
	NSString *_statsEpoch;
	NSNumber *_llmMs;
	/// Token máy chủ báo cho lượt này (@{in, out}) — ghi kèm thống kê nếu có.
	NSDictionary *_llmUsage;
	NSHashTable *_handledCommands;
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
	NSTimeInterval _captureTime;
	NSTimeInterval _lastProgressAt;
}
- (void)noteToolProgress;
@end

#pragma mark - Trả lời trễ

/// Câu trả lời đến sau khi Siri đã đóng: không thể chèn vào hội thoại nữa
/// (Siri đã kết thúc lượt), nên gửi thông báo kèm nút đọc + toàn văn trong
/// thân thông báo. Trước đây đáp án này bị bỏ hoàn toàn.
static void SXPostDeferredAnswer(NSString *question, NSString *display) {
#ifndef SX_TESTING
	if (!display.length) return;
	NSString *body = display.length > 900
		? [[display substringToIndex:900] stringByAppendingString:@"…"] : display;
	NSString *title = question.length
		? [NSString stringWithFormat:@"SiriX trả lời: %@", SXShort(question, 60)]
		: @"SiriX trả lời";
	@try {
		UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
		content.title = title;
		content.body = body;
		content.sound = nil;    // im lặng: người dùng có thể không cầm máy
		content.threadIdentifier = @"com.sirix.tweak.deferred";
		UNTimeIntervalNotificationTrigger *trigger =
			[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
		UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:
			[NSString stringWithFormat:@"sirix.deferred.%@", NSUUID.UUID.UUIDString]
																	content:content trigger:trigger];
		[[UNUserNotificationCenter currentNotificationCenter]
			addNotificationRequest:request withCompletionHandler:^(NSError *error) {
			if (error) SXLogWrn(@"resp", @"không gửi được thông báo trả lời trễ: %@",
								error.localizedDescription);
			else SXLogInf(@"resp", @"đã gửi thông báo trả lời trễ (%lu ký tự)",
						  (unsigned long)display.length);
		}];
	} @catch (NSException *exception) {
		SXLogErr(@"resp", @"thông báo trả lời trễ lỗi: %@", exception.reason);
	}
#else
	(void)question; (void)display;   // bản test không có UserNotifications
#endif
}

/// Hàng đợi tuần tự cho toàn bộ vòng đời một lượt hỏi (xem `noteQuestion:`).
static dispatch_queue_t SXTurnQueue(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("com.sirix.turn", DISPATCH_QUEUE_SERIAL);
	});
	return queue;
}

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
		_handledCommands = [NSHashTable hashTableWithOptions:
			NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
		SXRegisterHostTools();
	}
	return self;
}

- (void)setup {
#ifndef SX_TESTING
	int token = 0;
	notify_register_dispatch("com.sirix.tweak/resetHistory", &token, dispatch_get_main_queue(), ^(int t) {
		(void)t;
		[[SXIntercept shared] clearHistoryMemory];
	});
#endif
}

#pragma mark - Câu hỏi

- (void)noteQuestion:(NSString *)text source:(NSString *)source {
	NSString *clean = [text stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
		SXLogDbg(@"capture", @"tweak đang tắt — bỏ qua");
		return;
	}
	NSTimeInterval now = CFAbsoluteTimeGetCurrent();
	// Cùng một câu có thể đi qua ba hook (nhận giọng nói, AFConnection, AFConversation).
	// Chỉ bỏ khi đúng là cùng một câu trong một khoảng rất ngắn — trước đây cửa sổ
	// 2,5 giây làm người dùng hỏi lại cùng câu bị coi là trùng và không nhận trả lời.
	if (_lastCaptureText && [_lastCaptureText isEqualToString:normalized] && now - _lastCaptureTime < 1.0) {
		[_condition unlock];
		SXLogDbg(@"capture", @"trùng lặp trong %.2f giây (nguồn %@)", now - _lastCaptureTime, source);
		return;
	}
	_lastCaptureText = normalized;
	_lastCaptureTime = now;

	// Chế độ tiền tố: câu không có @ai do Siri xử lý và luôn huỷ lượt cũ để
	// đáp án cũ không gắn vào yêu cầu không có tiền tố.
	if ([prefs.triggerMode isEqualToString:@"prefix"]) {
		NSString *lower = clean.lowercaseString;
		BOOL hasAI = [lower hasPrefix:@"@ai"] &&
			(lower.length == 3 || [[NSCharacterSet whitespaceAndNewlineCharacterSet]
								   characterIsMember:[lower characterAtIndex:3]]);
		if (!hasAI) {
			_generation++;
			_pending = NO;
			[_condition broadcast];
			[_condition unlock];
			SXLogInf(@"capture", @"bỏ qua câu không có tiền tố @ai — dùng Siri gốc (%@)", source);
			return;
		}
		clean = [[clean substringFromIndex:3] stringByTrimmingCharactersInSet:
				 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
	_lastProgressAt = now;
	_pending = YES;
	_decided = NO;
	_decisionDisplay = nil;
	_decisionSpeech = nil;
	_decisionTime = 0;
	_decisionIsAnswer = NO;
	_decisionDialogID = nil;
	_historySaved = NO;
	_outcomeCounted = NO;
	_questionIncognito = prefs.incognito;
	_historyEpoch = nil;
	_statsEpoch = nil;
	_llmMs = nil;
	_llmUsage = nil;
	[_handledCommands removeAllObjects];
	_ready = NO;
	_errored = NO;
	_actionSeen = NO;
	_answer = nil;
	_answerDisplay = nil;
	_answerError = nil;
	NSArray<NSDictionary *> *historySnapshot = [_history copy];
	[_condition broadcast]; // đánh thức lượt đang chờ của câu hỏi trước

	if (prefs.incognito) SXLogInf(@"capture", @"câu hỏi #%llu (%@): [không lưu lịch sử]",
								  (unsigned long long)myGeneration, source);
	else SXLogInf(@"capture", @"câu hỏi #%llu (%@): “%@”",
				  (unsigned long long)myGeneration, source, clean);
	[_condition unlock];

	// Một hàng đợi riêng, TUẦN TỰ cho toàn bộ việc "một lượt hỏi": đọc kho → gọi
	// AI → nhận đáp án → ghi thống kê/lịch sử/thông báo. Trước đây ba khối chạy
	// trên ba luồng khác nhau nên thứ tự là ngẫu nhiên, và một khối lấy epoch
	// của lượt CŨ có thể ghi đè epoch của lượt MỚI — lượt hỏi mới sẽ không đọc
	// được gì và trả lời "quá muộn" dù mạng nhanh.
	dispatch_async(SXTurnQueue(), ^{
		// Đọc kho và epoch trên hàng đợi của kho, không chặn hook ACE bằng I/O.
		__block NSDictionary *stored = nil;
		dispatch_sync([SXStore queue], ^{ stored = [[SXStore shared] snapshot]; });
		[self->_condition lock];
		BOOL stale = (self->_generation != myGeneration);
		BOOL privateTurn = self->_questionIncognito || [SXPrefs shared].incognito;
		if (!stale) {
			self->_historyEpoch = stored[@"historyEpoch"];
			self->_statsEpoch = stored[@"statsEpoch"];
		}
		[self->_condition unlock];
		if (stale) return;

		// Lượt riêng tư không được gửi bất kỳ ngữ cảnh cũ nào tới nhà cung cấp,
		// kể cả lịch sử đang giữ trong RAM trước khi bật chế độ này.
		NSArray *requestHistory = privateTurn ? @[] : (stored[@"history"] ?: historySnapshot);
		// 0 = không gửi ngữ cảnh: mỗi câu hỏi độc lập, tiết kiệm token.
		NSUInteger maxTurns = (NSUInteger)MAX(0, [SXPrefs shared].contextTurns);
		if (maxTurns == 0) requestHistory = @[];
		else if (requestHistory.count > maxTurns) {
			requestHistory = [requestHistory subarrayWithRange:
							  NSMakeRange(requestHistory.count - maxTurns, maxTurns)];
		}

		SXToolExec executor = ^NSDictionary *(NSString *name, NSDictionary *arguments, NSError **error) {
			// Mỗi lần gọi công cụ là một mốc tiến triển: hook ACE đang chờ sẽ được
			// gia hạn thay vì tưởng model bị treo rồi hiện bubble hết giờ.
			[self noteToolProgress];
			return [SXTools execute:name arguments:arguments error:error];
		};
		[SXLLM askQuestion:clean
				   history:requestHistory
					 tools:[SXTools definitions]
				  executor:executor
				completion:^(NSString *answer, NSError *error, NSDictionary *info) {
			[self applyAnswer:answer error:error info:info forGeneration:myGeneration];
		}];
	});
}

- (void)applyAnswer:(NSString *)answer error:(NSError *)error info:(NSDictionary *)info
	  forGeneration:(uint64_t)generation {
	// Khai báo ngoài khối lock để còn dùng sau khi nhả lock (gửi thông báo).
	BOOL answerArrivedLate = NO;
	[_condition lock];
	if (generation != _generation) {
		[_condition unlock];
		SXLogDbg(@"resp", @"bỏ đáp án cũ (câu hỏi #%llu, hiện tại #%llu)",
				 (unsigned long long)generation, (unsigned long long)_generation);
		return;
	}
	_llmMs = [info[@"ms"] isKindOfClass:NSNumber.class] ? info[@"ms"] : nil;
	_llmUsage = [info[@"usage"] isKindOfClass:NSDictionary.class] ? info[@"usage"] : nil;
	if (error) {
		_errored = YES;
		_answerError = error;
	} else {
		NSString *raw = [answer stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (raw.length > 4000) raw = [[raw substringToIndex:4000] stringByAppendingString:@"…"];
		_answerDisplay = raw;
		_answer = SXSanitizeAnswer(raw);
		if (_answerDisplay.length && _answer.length) {
			_ready = YES;
			SXLogDbg(@"resp", @"đáp án #%llu sẵn sàng (hiển thị %lu · đọc %lu ký tự)",
					 (unsigned long long)generation,
					 (unsigned long)_answerDisplay.length, (unsigned long)_answer.length);
			// Lượt đã quyết định (hết giờ / giữ Siri gốc) rồi mới có đáp án →
			// không còn chỗ chèn vào Siri. Gửi thông báo thay vì bỏ đi.
			answerArrivedLate = (_decided || _outcomeCounted) && !_decisionIsAnswer;
		} else {
			_errored = YES;
			_answerError = [NSError errorWithDomain:@"com.sirix.llm" code:-6
										   userInfo:@{NSLocalizedDescriptionKey: @"Đáp án rỗng sau khi xử lý."}];
		}
	}
	[_condition broadcast];
	[_condition unlock];

	// Đáp án tới muộn: lưu vào Lịch sử (nếu được phép) và gửi thông báo — nếu
	// người dùng đã tắt thông báo hay chưa cấp quyền thì ít nhất Lịch sử vẫn có.
	if (answerArrivedLate && _ready && generation == _generation) {
		SXPrefs *prefs = [SXPrefs shared];
		BOOL allowDeferred = prefs.deferLongReplies;
		NSString *question = _question;
		NSString *display = _answerDisplay;
		BOOL privateTurn = _questionIncognito || prefs.incognito;
		NSString *epoch = _historyEpoch;
		NSUInteger limit = MAX(1, (NSUInteger)prefs.contextTurns);
		NSTimeInterval startedAt = _captureTime;
		if (display.length && !privateTurn && epoch.length) {
			NSString *stored = display.length > 1000
				? [[display substringToIndex:1000] stringByAppendingString:@"…"] : display;
			NSString *answer = stored;
			dispatch_async([SXStore queue], ^{
				[[SXStore shared] appendQuestion:question ?: @"" answer:answer limit:limit
									   epoch:epoch startedAt:startedAt];
			});
		}
		// Thông báo là một bản lưu bền ngoài lịch sử. Không gửi nội dung của
		// lượt riêng tư vào Notification Center.
		if ([SXDisplayPolicy shouldSendDeferredAnswerWhenEnabled:allowDeferred privateTurn:privateTurn]) {
			SXLogInf(@"resp", @"đáp án tới sau khi đã quyết định — gửi thông báo (%lu ký tự)",
					 (unsigned long)display.length);
			dispatch_async(dispatch_get_main_queue(), ^{
				SXPostDeferredAnswer(question, display);
			});
		} else if (allowDeferred && privateTurn) {
			SXLogInf(@"resp", @"bỏ thông báo trả lời trễ cho lượt riêng tư");
		}
	}
}

// Ghi số liệu ngoài hook, epoch ngăn tác vụ xếp hàng phục hồi thống kê đã xóa.
- (void)queueStatistic:(NSString *)event milliseconds:(NSNumber *)milliseconds {
	[self queueStatistic:event milliseconds:milliseconds tokens:nil];
}

- (void)queueStatistic:(NSString *)event milliseconds:(NSNumber *)milliseconds
				tokens:(NSDictionary *)tokens {
	NSString *epoch = _statsEpoch;
	NSTimeInterval startedAt = _captureTime;
	if (!epoch.length) return;
	dispatch_async([SXStore queue], ^{
		[[SXStore shared] recordEvent:event milliseconds:milliseconds tokens:tokens
								epoch:epoch startedAt:startedAt];
	});
}

#pragma mark - Đường vào lệnh ACE

- (BOOL)handleIncomingCommand:(id)command {
	if (!command || ![SXPrefs shared].enabled) return NO;
	NSString *className = NSStringFromClass([command class]);
	SXLogDbg(@"hook", @"lệnh ACE %@ (main=%d)", className, NSThread.isMainThread ? 1 : 0);

	if (SXIsActionClass(className)) {
		[_condition lock];
		if (_pending) {
			_actionSeen = YES;
			[_condition broadcast];
		}
		[_condition unlock];
		SXLogDbg(@"resp", @"tác vụ hệ thống — cho Siri gốc xử lý: %@", className);
		return NO;
	}

	BOOL looksLikeResponse = [className containsString:@"AddViews"] ||
							 [className containsString:@"SayIt"];
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
		_decided = YES;
		_decisionDisplay = nil;
		[_condition unlock];
		SXLogInf(@"resp", @"%@: có tác vụ hệ thống — giữ Siri gốc (%@)", source, className);
		return NO;
	}

	if (!_decided) {
		// Trần chờ trên luồng ACE. Ngân sách người dùng đặt là trần tổng; mỗi
		// lần model có tiến triển (chạy công cụ) thì mốc chờ được đẩy thêm 3
		// giây, nhưng vẫn không vượt quá trần tổng và không giữ hội thoại quá
		// lâu (Siri tự đóng khi quá chậm). Hook trên luồng chính dùng trần thấp
		// hơn vì mỗi giây chờ là một giây giao diện đứng yên.
		NSTimeInterval budget = MAX(2.0, prefs.responseTimeout);
		// Trần chờ do người dùng đặt (2–20 s); ngân sách AI chỉ là mức trần trên.
		// Trước đây trần cứng 8/16 s khiến đặt “chờ 30 giây” mà vẫn bị cắt ở 8 s.
		NSTimeInterval hardCap = MIN(budget, MAX(2.0, prefs.replyDeadline));
		NSTimeInterval captureAt = _captureTime > 0 ? _captureTime : CFAbsoluteTimeGetCurrent();
		NSTimeInterval baseDeadline = captureAt + MIN(hardCap, 5.0);
		while (!_ready && !_errored && !_decided && _generation == myGeneration && !_actionSeen) {
			NSTimeInterval target = MIN(MAX(baseDeadline, _lastProgressAt + 3.0),
										captureAt + hardCap);
			if (target <= CFAbsoluteTimeGetCurrent()) break;
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceReferenceDate:target];
			if (![_condition waitUntilDate:deadline]) break;
		}
		if (_generation != myGeneration) {
			[_condition unlock];
			SXLogDbg(@"resp", @"%@: câu hỏi mới — bỏ lượt chờ cũ", source);
			return NO;
		}
		if (_actionSeen) {
			_decided = YES;
			_decisionDisplay = nil;
			[_condition unlock];
			SXLogInf(@"resp", @"%@: phát hiện tác vụ trong lúc chờ — giữ Siri gốc", source);
			return NO;
		}
		// Một hook khác có thể đã quyết định trong lúc condition nhả lock.
		if (!_decided) {
			_decided = YES;
			_decisionTime = CFAbsoluteTimeGetCurrent();
			_decisionDialogID = SXDialogID(command);
			[_condition broadcast];
			if (_ready && _answer.length && _answerDisplay.length) {
				_decisionIsAnswer = YES;
				_decisionSpeech = _answer;
				_decisionDisplay = prefs.markdown ? SXMarkdownRender(_answerDisplay) : _answerDisplay;
				if (!_decisionDisplay.length) _decisionDisplay = _answerDisplay;
				if (!prefs.markdown && _decisionDisplay.length > 2000) {
					_decisionDisplay = [[_decisionDisplay substringToIndex:2000] stringByAppendingString:@"…"];
				}
				[SXDisplayPolicy logDecision:@"chọn đáp án AI cho lượt" source:source];
			} else if (_errored) {
				[self queueStatistic:@"error" milliseconds:_llmMs tokens:_llmUsage];
				if ([SXDisplayPolicy shouldShowErrorBubbleInMode:prefs.mode speakErrors:prefs.speakErrors]) {
					_decisionDisplay = [NSString stringWithFormat:@"⚠️ SiriX gặp lỗi: %@",
										_answerError.localizedDescription];
					_decisionSpeech = _decisionDisplay;
					[SXDisplayPolicy logDecision:@"bubble lỗi" source:source];
				} else {
					_decisionDisplay = nil;
					SXLogInf(@"resp", @"%@: AI lỗi (%@) — giữ Siri gốc", source,
							 _answerError.localizedDescription);
				}
			} else {
				[self queueStatistic:@"timeout" milliseconds:nil];
				_decisionDisplay = [SXDisplayPolicy timeoutBubbleMessageInMode:prefs.mode
																		action:prefs.timeoutAction];
				_decisionSpeech = _decisionDisplay;
				SXLogWrn(@"resp", @"%@: hết ngân sách (chờ %.1fs / trần %.1fs, ngân sách %.0fs) — %@",
						 source, CFAbsoluteTimeGetCurrent() - captureAt, hardCap, prefs.responseTimeout,
						 _decisionDisplay ? @"bubble hết giờ" : @"giữ Siri gốc");
			}
			if (!_decisionDisplay.length) {
				_outcomeCounted = YES;
				[self queueStatistic:@"kept" milliseconds:nil];
				if ([prefs.timeoutAction isEqualToString:@"retry"] && !_errored) {
					SXLogInf(@"resp", @"%@: giữ Siri gốc và chờ đáp án của lần thử lại bằng model dự phòng",
							 source);
				}
			}
		}
	}

	// AddViews, SayIt và hook dự phòng có thể là nhiều object cho cùng một lượt.
	// Dùng cùng quyết định thay vì cho các lệnh sau lọt về Siri gốc. Cửa sổ 10 s:
	// quyết định quá cũ chỉ có thể áp lên một lệnh ACE mà Siri đã bỏ — sửa lúc
	// đó làm hội thoại lệch trạng thái và giao diện tự đóng.
	if (!_decisionDisplay.length || CFAbsoluteTimeGetCurrent() - _decisionTime > 10.0) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: quyết định giữ gốc hoặc đã hết hạn (%@)", source, className);
		return NO;
	}
	// Chỉ áp quyết định cho cùng hội thoại — tránh đè lên một lệnh UI không liên quan.
	NSString *dialogID = SXDialogID(command);
	if (dialogID.length && _decisionDialogID.length && ![dialogID isEqualToString:_decisionDialogID]) {
		[_condition unlock];
		SXLogDbg(@"resp", @"%@: khác dialog (%@ ≠ %@) — cho qua", source, dialogID, _decisionDialogID);
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
		SXLogErr(@"err", @"%@: mutate %@ exception %@: %@ — cho qua", source, className,
				 exception.name, exception.reason);
	}
	if (changed) {
		[_handledCommands addObject:command];
		if (!_outcomeCounted) {
			_outcomeCounted = YES;
			[self queueStatistic:@"replaced" milliseconds:_decisionIsAnswer ? _llmMs : nil
						   tokens:_decisionIsAnswer ? _llmUsage : nil];
		}
		// Chỉ thêm lịch sử khi thực sự sửa được phản hồi AI, và chỉ một lần.
		if (_decisionIsAnswer && !_historySaved) {
			NSString *storedAnswer = _answerDisplay.length > 1000
				? [[_answerDisplay substringToIndex:1000] stringByAppendingString:@"…"] : _answerDisplay;
			[_history addObject:@{@"q": _question ?: @"", @"a": storedAnswer ?: @""}];
			while ((NSInteger)_history.count > MAX(0, prefs.contextTurns) && _history.count) {
				[_history removeObjectAtIndex:0];
			}
			_historySaved = YES;
			// Từng lượt được đánh dấu riêng tư từ lúc capture; đổi cấu hình trong
			// khi chờ cũng không được khiến lượt riêng tư bị ghi xuống đĩa.
			if (!_questionIncognito && !prefs.incognito && _historyEpoch.length) {
				NSString *question = _question ?: @"";
				NSString *answer = storedAnswer ?: @"";
				NSString *epoch = _historyEpoch;
				NSUInteger limit = MAX(1, (NSUInteger)prefs.contextTurns);
				NSTimeInterval startedAt = _captureTime;
				dispatch_async([SXStore queue], ^{
					[[SXStore shared] appendQuestion:question answer:answer limit:limit
											   epoch:epoch startedAt:startedAt];
				});
			}
		}
	}
	[_condition unlock];
	return changed;
}

- (void)noteToolProgress {
	[_condition lock];
	_lastProgressAt = CFAbsoluteTimeGetCurrent();
	[_condition broadcast];
	[_condition unlock];
}

- (void)clearHistoryMemory {
	[_condition lock];
	NSUInteger count = _history.count;
	[_history removeAllObjects];
	[_condition unlock];
	SXLogInf(@"pref", @"đã xóa ngữ cảnh trong bộ nhớ (%lu câu)", (unsigned long)count);
}

- (BOOL)clearHistory {
	[self clearHistoryMemory];
	__block BOOL ok = NO;
	dispatch_sync([SXStore queue], ^{ ok = [[SXStore shared] clearHistory]; });
	if (!ok) SXLogErr(@"err", @"không xóa được lịch sử đã lưu");
#ifndef SX_TESTING
	notify_post("com.sirix.tweak/resetHistory");
#endif
	return ok;
}

@end
