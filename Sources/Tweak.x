#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <signal.h>
#import <unistd.h>
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXIntercept.h"

#ifndef SX_SCHEME
#define SX_SCHEME "unknown"
#endif

#pragma mark - Chẩn đoán exception (SpringBoard)

static NSUncaughtExceptionHandler *SXPrevExceptionHandler = NULL;

static void SXExceptionHandler(NSException *exception) {
	SXLogErr(@"err", @"EXCEPTION không bắt được: %@ — %@ | %@",
			 exception.name, exception.reason,
			 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
	if (SXPrevExceptionHandler) SXPrevExceptionHandler(exception);
}

#pragma mark - Trích xuất câu nói

static id SXMsg(id object, SEL selector) {
	if (!object || ![object respondsToSelector:selector]) return nil;
	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *SXNorm(NSString *text) {
	if (![text isKindOfClass:[NSString class]]) return nil;
	static NSRegularExpression *whitespace;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		whitespace = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:NULL];
	});
	NSString *result = [whitespace stringByReplacingMatchesInString:text
														   options:0
															 range:NSMakeRange(0, text.length)
													   withTemplate:@" "];
	result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return result.length ? result : nil;
}

/// phrases[*].interpretations[*].tokens[*].text — chỉ lấy diễn giải tốt nhất.
static NSString *SXChainUtterance(id root) {
	if (!root) return nil;
	NSMutableArray<NSString *> *chunks = [NSMutableArray array];
	id phrases = nil;
	@try { phrases = [root valueForKey:@"phrases"]; } @catch (NSException *e) {}
	if (![phrases isKindOfClass:[NSArray class]]) return nil;

	for (id phrase in phrases) {
		id interpretations = nil;
		@try { interpretations = [phrase valueForKey:@"interpretations"]; } @catch (NSException *e) {}
		if (![interpretations isKindOfClass:[NSArray class]]) continue;
		for (id interpretation in interpretations) {
			id tokens = nil;
			@try { tokens = [interpretation valueForKey:@"tokens"]; } @catch (NSException *e) {}
			if (![tokens isKindOfClass:[NSArray class]]) continue;
			NSMutableArray<NSString *> *local = [NSMutableArray array];
			for (id token in tokens) {
				id value = nil;
				@try { value = [token valueForKey:@"text"]; } @catch (NSException *e) {}
				if ([value isKindOfClass:[NSString class]] && ((NSString *)value).length) {
					[local addObject:value];
				}
			}
			if (local.count) {
				[chunks addObjectsFromArray:local];
				break;
			}
		}
		if (chunks.count) break;
	}
	return chunks.count ? [chunks componentsJoinedByString:@" "] : nil;
}

static NSString *SXUtteranceFromRecognized(id object) {
	if (!object) return nil;
	SEL bestSelector = NSSelectorFromString(@"af_bestTextInterpretation");

	id value = SXMsg(object, bestSelector);
	NSString *text = SXNorm([value isKindOfClass:[NSString class]] ? value : nil);
	if (text) return text;

	id recognition = nil;
	@try { recognition = [object valueForKey:@"recognition"]; } @catch (NSException *e) {}
	if (recognition) {
		value = SXMsg(recognition, bestSelector);
		text = SXNorm([value isKindOfClass:[NSString class]] ? value : nil);
		if (text) return text;
		text = SXNorm(SXChainUtterance(recognition));
		if (text) return text;
	}
	text = SXNorm(SXChainUtterance(object));
	if (text) return text;

	id direct = nil;
	@try { direct = [object valueForKey:@"text"]; } @catch (NSException *e) {}
	return SXNorm([direct isKindOfClass:[NSString class]] ? direct : nil);
}

static void SXCapture(NSString *raw, NSString *source) {
	NSString *text = SXNorm(raw);
	if (text) {
		[[SXIntercept shared] noteQuestion:text source:source];
	} else {
		SXLogDbg(@"capture", @"(%@) không trích xuất được văn bản", source);
	}
}

#pragma mark - Hook: hội thoại

%group AFConvCaptureHook
%hook AFConversation

- (void)addItemForSpeechRecognizedCommand:(id)command {
	// Mọi hook đều bọc @try: một exception lọt vào Siri sẽ giết SpringBoard
	// (người dùng thấy "giao diện Siri văng").
	@try {
		NSString *text = SXUtteranceFromRecognized(command);
		if (text) {
			[[SXIntercept shared] noteQuestion:text source:@"AFConversation.addItemForSpeechRecognizedCommand"];
		} else {
			SXLogDbg(@"capture", @"AFConversation.addItemForSpeechRecognizedCommand: không trích được văn bản");
		}
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"hook addItemForSpeechRecognizedCommand exception %@: %@", exception.name, exception.reason);
	}
	%orig;
}

%end
%end

%group AFConvViewsHook
%hook AFConversation
- (void)addItemsForAddViewsCommand:(id)command {
	@try {
		[[SXIntercept shared] handleAddViewsInsertion:command];
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"hook addItemsForAddViewsCommand exception %@: %@", exception.name, exception.reason);
	}
	%orig;
}

%end
%end

#pragma mark - Hook: kết nối Assistant

%group AFConnCommandHook
%hook AFConnection

- (void)_handleCommand:(id)command reply:(id)reply {
	@try {
		[[SXIntercept shared] handleIncomingCommand:command];
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"hook _handleCommand exception %@: %@ | %@", exception.name, exception.reason,
				 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
	}
	%orig;
}

%end
%end

%group AFConnSpeechHook
%hook AFConnection
- (void)_tellSpeechDelegateSpeechRecognized:(id)result {
	@try {
		NSString *text = SXUtteranceFromRecognized(result);
		if (text) {
			[[SXIntercept shared] noteQuestion:text source:@"AFConnection._tellSpeechDelegateSpeechRecognized:"];
		}
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"hook _tellSpeechDelegateSpeechRecognized exception %@: %@", exception.name, exception.reason);
	}
	%orig;
}

%end
%end

%group AFConnTextHook
%hook AFConnection
- (void)startRequestWithText:(NSString *)text {
	@try {
		SXCapture(text, @"AFConnection.startRequestWithText (Type-to-Siri)");
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"hook startRequestWithText exception %@: %@", exception.name, exception.reason);
	}
	%orig;
}

%end
%end

%group AFConnRequestHook
%hook AFConnection
- (void)_requestWillBeginWithRequestClass:(id)requestClass
						  isSpeechRequest:(BOOL)isSpeech
					 speechRequestOptions:(id)options
							  requestInfo:(id)info
					analyticsEventProvider:(id)provider {
	SXLogDbg(@"hook", @"yêu cầu mới: class=%@ speech=%d",
			 requestClass ? [requestClass description] : @"?", isSpeech ? 1 : 0);
	%orig;
}

%end
%end

%group AFConnBackgroundRequestHook
%hook AFConnection
- (void)_requestWillBeginWithRequestClass:(id)requestClass
						  isSpeechRequest:(BOOL)isSpeech
					 speechRequestOptions:(id)options
							  requestInfo:(id)info
						isBackgroundRequest:(BOOL)isBackground
					analyticsEventProvider:(id)provider {
	SXLogDbg(@"hook", @"yêu cầu mới: class=%@ speech=%d background=%d",
			 requestClass ? [requestClass description] : @"?", isSpeech ? 1 : 0, isBackground ? 1 : 0);
	%orig;
}

%end
%end

#pragma mark - Khởi động

static BOOL SXCanHook(NSString *className, Class cls, NSString *selectorName) {
	BOOL exists = cls && class_getInstanceMethod(cls, NSSelectorFromString(selectorName)) != NULL;
	SXLogInf(@"hook", @"%@ %@: %@", className, selectorName,
			 exists ? @"tìm thấy — cài hook" : @"KHÔNG tìm thấy — bỏ qua hook");
	return exists;
}

%ctor {
	@autoreleasepool {
		SXLogInit();
		SXPrevExceptionHandler = NSGetUncaughtExceptionHandler();
		NSSetUncaughtExceptionHandler(&SXExceptionHandler);
		[SXPrefs shared];
		[[SXIntercept shared] setup];

		// Cài đặt đổi → tải lại ngay (không cần respring).
		int prefsToken = 0;
		notify_register_dispatch("com.sirix.tweak/prefs.changed", &prefsToken,
								 dispatch_get_main_queue(), ^(int token) {
			[[SXPrefs shared] reload];
		});

		// Nút "Khởi động lại SpringBoard" trong Cài đặt — chỉ đăng ký ở SpringBoard.
		NSString *processName = [NSString stringWithUTF8String:getprogname() ?: ""];
		if ([processName isEqualToString:@"SpringBoard"]) {
			int respringToken = 0;
			notify_register_dispatch("com.sirix.respring", &respringToken,
									 dispatch_get_main_queue(), ^(int token) {
				SXLogInf(@"boot", @"nhận yêu cầu khởi động lại SpringBoard…");
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
							   dispatch_get_main_queue(), ^{
					kill(getpid(), SIGKILL); // launchd tự khởi động lại SpringBoard
				});
			});
		}

		Class conversation = objc_getClass("AFConversation");
		if (SXCanHook(@"AFConversation", conversation, @"addItemForSpeechRecognizedCommand:")) %init(AFConvCaptureHook);
		if (SXCanHook(@"AFConversation", conversation, @"addItemsForAddViewsCommand:")) %init(AFConvViewsHook);

		Class connection = objc_getClass("AFConnection");
		if (SXCanHook(@"AFConnection", connection, @"_handleCommand:reply:")) %init(AFConnCommandHook);
		if (SXCanHook(@"AFConnection", connection, @"_tellSpeechDelegateSpeechRecognized:")) %init(AFConnSpeechHook);
		if (SXCanHook(@"AFConnection", connection, @"startRequestWithText:")) %init(AFConnTextHook);
		if (SXCanHook(@"AFConnection", connection, @"_requestWillBeginWithRequestClass:isSpeechRequest:speechRequestOptions:requestInfo:analyticsEventProvider:")) %init(AFConnRequestHook);
		if (SXCanHook(@"AFConnection", connection, @"_requestWillBeginWithRequestClass:isSpeechRequest:speechRequestOptions:requestInfo:isBackgroundRequest:analyticsEventProvider:")) %init(AFConnBackgroundRequestHook);

		SXLogInf(@"boot", @"SiriX %@ sẵn sàng (scheme=%s) — chế độ=%@ provider=%@",
				 SX_VERSION, SX_SCHEME,
				 [SXPrefs shared].mode == SXReplyModeFull ? @"thay thế tất cả" : @"thông minh",
				 [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai");
	}
}
