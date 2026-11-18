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

%group AFConvHooks
%hook AFConversation

- (void)addItemForSpeechRecognizedCommand:(id)command {
	%orig;
	NSString *text = SXUtteranceFromRecognized(command);
	if (text) {
		[[SXIntercept shared] noteQuestion:text source:@"AFConversation.addItemForSpeechRecognizedCommand"];
	} else {
		SXLogDbg(@"capture", @"AFConversation.addItemForSpeechRecognizedCommand: không trích được văn bản");
	}
}

- (void)addItemsForAddViewsCommand:(id)command {
	[[SXIntercept shared] handleAddViewsInsertion:command];
	%orig;
}

%end
%end

#pragma mark - Hook: kết nối Assistant

%group AFConnHooks
%hook AFConnection

- (void)_handleCommand:(id)command reply:(id)reply {
	[[SXIntercept shared] handleIncomingCommand:command];
	%orig;
}

- (void)_tellSpeechDelegateSpeechRecognized:(id)result {
	%orig;
	NSString *text = SXUtteranceFromRecognized(result);
	if (text) {
		[[SXIntercept shared] noteQuestion:text source:@"AFConnection._tellSpeechDelegateSpeechRecognized:"];
	}
}

- (void)startRequestWithText:(NSString *)text {
	SXCapture(text, @"AFConnection.startRequestWithText (Type-to-Siri)");
	%orig;
}

- (void)_requestWillBeginWithRequestClass:(id)requestClass
						  isSpeechRequest:(BOOL)isSpeech
					 speechRequestOptions:(id)options
							  requestInfo:(id)info
					analyticsEventProvider:(id)provider {
	SXLogDbg(@"hook", @"yêu cầu mới: class=%@ speech=%d",
			 requestClass ? [requestClass description] : @"?", isSpeech ? 1 : 0);
	%orig;
}

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

static void SXLogHookStatus(NSString *className, Class cls, NSArray<NSString *> *selectors) {
	for (NSString *selectorName in selectors) {
		BOOL exists = class_getInstanceMethod(cls, NSSelectorFromString(selectorName)) != NULL;
		SXLogInf(@"hook", @"%@ %@: %@", className, selectorName,
				 exists ? @"tìm thấy, đã cài ✓" : @"KHÔNG tìm thấy — hook sẽ không kích hoạt");
	}
}

%ctor {
	@autoreleasepool {
		SXLogInit();
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
		if (conversation) {
			SXLogHookStatus(@"AFConversation", conversation, @[
				@"addItemForSpeechRecognizedCommand:",
				@"addItemsForAddViewsCommand:",
			]);
			%init(AFConvHooks);
		} else {
			SXLogWrn(@"hook", @"Không tìm thấy lớp AFConversation — bắt câu hỏi sẽ yếu đi");
		}

		Class connection = objc_getClass("AFConnection");
		if (connection) {
			SXLogHookStatus(@"AFConnection", connection, @[
				@"_handleCommand:reply:",
				@"_tellSpeechDelegateSpeechRecognized:",
				@"startRequestWithText:",
			]);
			%init(AFConnHooks);
		} else {
			SXLogWrn(@"hook", @"Không tìm thấy lớp AFConnection — không thể thay thế câu trả lời");
		}

		SXLogInf(@"boot", @"SiriX %@ sẵn sàng (scheme=%s) — chế độ=%@ provider=%@",
				 SX_VERSION, SX_SCHEME,
				 [SXPrefs shared].mode == SXReplyModeFull ? @"thay thế tất cả" : @"thông minh",
				 [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai");
	}
}
