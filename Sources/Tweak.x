#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <signal.h>
#import <unistd.h>
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXIntercept.h"
#import "SXVoiceInput.h"
#import "SXNative.h"

#ifndef SX_SCHEME
#define SX_SCHEME "unknown"
#endif

#pragma mark - Chẩn đoán exception (SpringBoard)

static NSUncaughtExceptionHandler *SXPrevExceptionHandler = NULL;

static void SXExceptionHandler(NSException *exception) {
	SXLogErr(@"err", @"EXCEPTION không bắt được: %@", exception.name);
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

	if ([object isKindOfClass:NSString.class]) return SXNorm(object);
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
	NSString *apple = SXUtteranceFromRecognized(command);
	id presented = command;
	if (apple.length) {
		NSString *outcome = nil;
		NSString *ref = SXRefID(command);
		NSString *text = [[SXVoiceInput shared] finalText:apple owner:nil reference:ref outcome:&outcome];
		if (![text isEqual:apple]) {
			id copy = SXTranscriptCopy(command, text);
			if (copy) presented = copy;
			else SXLogDbg(@"stt", @"giữ text Apple trên UI; transcript mới chỉ dùng cho AI (L1).");
		}
		[[SXIntercept shared] noteQuestion:text source:@"AFConversation.recognized" reference:ref stt:outcome];
	}
	%orig(presented);
}

%end
%end

%group AFConvViewsHook
%hook AFConversation
- (void)addItemsForAddViewsCommand:(id)command {
	[[SXIntercept shared] handleAddViewsInsertion:command conversation:self];
	%orig;
}

%end
%end

#pragma mark - Hook: kết nối Assistant

%group AFConnCommandHook
%hook AFConnection

- (void)_handleCommand:(id)command reply:(id)reply {
	[[SXIntercept shared] handleIncomingCommand:command];
	%orig;
}

%end
%end

%group AFConnSpeechHook
%hook AFConnection
- (void)_tellSpeechDelegateSpeechRecognized:(id)result {
	NSString *apple = SXUtteranceFromRecognized(result);
	if (apple.length) {
		NSString *outcome = nil;
		NSString *ref = SXRefID(result);
		NSString *text = [[SXVoiceInput shared] finalText:apple owner:self reference:ref outcome:&outcome];
		[[SXIntercept shared] noteQuestion:text source:@"AFConnection.recognized" reference:ref stt:outcome];
	}
	// Do not change the transcript used by the Apple request / intent pipeline.
	%orig;
}

%end
%end

%group AFConnTextHook
%hook AFConnection
- (void)startRequestWithText:(NSString *)text {
	[[SXVoiceInput shared] cancel];
	[[SXIntercept shared] beginRequest];
	SXCapture(text, @"AFConnection.startRequestWithText (Type-to-Siri)");
	%orig;
}

%end
%end

static BOOL SXHasRecordingBegin;
static void SXBeginVoice(id connection) {
	[[SXIntercept shared] beginRequest];
	[[SXVoiceInput shared] begin:connection];
}

%group AFConnRequestHook
%hook AFConnection
- (void)_requestWillBeginWithRequestClass:(id)requestClass isSpeechRequest:(BOOL)isSpeech
	 speechRequestOptions:(id)options requestInfo:(id)info analyticsEventProvider:(id)provider {
	if (isSpeech) [[SXIntercept shared] beginRequest];
	%orig;
}
%end
%end

%group AFConnBackgroundRequestHook
%hook AFConnection
- (void)_requestWillBeginWithRequestClass:(id)requestClass isSpeechRequest:(BOOL)isSpeech speechRequestOptions:(id)options
	 requestInfo:(id)info isBackgroundRequest:(BOOL)isBackground analyticsEventProvider:(id)provider {
	if (isSpeech && !isBackground) [[SXIntercept shared] beginRequest];
	%orig;
}
%end
%end

%group AFConnRecordingBegin
%hook AFConnection
- (void)_tellSpeechDelegateRecordingWillBeginWithInputAudioPowerXPCWrapper:(id)context {
	SXBeginVoice(self);
	%orig;
}
%end
%end

%group AFConnRecordingBegan
%hook AFConnection
- (void)_tellSpeechDelegateRecordingDidBeginOnAVRecordRoute:(id)route audioSessionID:(unsigned int)sessionID {
	if (!SXHasRecordingBegin) SXBeginVoice(self);
	%orig;
}
%end
%end

%group AFConnRecordingEnd
%hook AFConnection
- (void)_tellSpeechDelegateRecordingDidEnd {
	[[SXVoiceInput shared] endRecording:self];
	%orig;
}
%end
%end

%group AFConnRecordingCancel
%hook AFConnection
- (void)_tellSpeechDelegateRecordingDidCancel {
	[[SXVoiceInput shared] cancel];
	%orig;
}
%end
%end

%group AFConnRequestEnd
%hook AFConnection
- (void)_requestDidEnd {
	[[SXVoiceInput shared] endRecording:self];
	%orig;
}
%end
%end

%group AFConnDismiss
%hook AFConnection
- (void)didDismissUI {
	[[SXVoiceInput shared] cancel];
	[[SXIntercept shared] dialogDidDismiss];
	%orig;
}
%end
%end

%group SXBulletinShort
%hook BBServer
- (id)initWithQueue:(dispatch_queue_t)queue {
	id server = %orig;
	SXRememberBulletinServer(server, queue);
	return server;
}
%end
%end

%group SXBulletinLong
%hook BBServer
- (id)initWithQueue:(dispatch_queue_t)queue dataProviderManager:(id)manager syncService:(id)sync dismissalSyncCache:(id)cache
	 observerListener:(id)observer conduitListener:(id)conduit systemStateListener:(id)state settingsListener:(id)settings {
	id server = %orig;
	SXRememberBulletinServer(server, queue);
	return server;
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
			[[SXVoiceInput shared] cancel];
			[[SXIntercept shared] preferencesDidChange];
		});

		// Nút "Khởi động lại SpringBoard" trong Cài đặt — chỉ đăng ký ở SpringBoard.
		NSString *processName = [NSString stringWithUTF8String:getprogname() ?: ""];
		if ([processName isEqualToString:@"SpringBoard"]) {
			Class bulletin = objc_getClass("BBServer");
			if (SXCanHook(@"BBServer", bulletin, @"initWithQueue:")) %init(SXBulletinShort);
			if (SXCanHook(@"BBServer", bulletin, @"initWithQueue:dataProviderManager:syncService:dismissalSyncCache:observerListener:conduitListener:systemStateListener:settingsListener:")) %init(SXBulletinLong);
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

		SXHasRecordingBegin = SXCanHook(@"AFConnection", connection, @"_tellSpeechDelegateRecordingWillBeginWithInputAudioPowerXPCWrapper:");
		if (SXHasRecordingBegin) %init(AFConnRecordingBegin);
		if (SXCanHook(@"AFConnection", connection, @"_tellSpeechDelegateRecordingDidBeginOnAVRecordRoute:audioSessionID:")) %init(AFConnRecordingBegan);
		if (SXCanHook(@"AFConnection", connection, @"_tellSpeechDelegateRecordingDidEnd")) %init(AFConnRecordingEnd);
		if (SXCanHook(@"AFConnection", connection, @"_tellSpeechDelegateRecordingDidCancel")) %init(AFConnRecordingCancel);
		if (SXCanHook(@"AFConnection", connection, @"_requestDidEnd")) %init(AFConnRequestEnd);
		if (SXCanHook(@"AFConnection", connection, @"didDismissUI")) %init(AFConnDismiss);

		SXLogInf(@"boot", @"SiriX %@ sẵn sàng (scheme=%s) — chế độ=%@ provider=%@",
				 SX_VERSION, SX_SCHEME,
				 [SXPrefs shared].mode == SXReplyModeFull ? @"thay thế tất cả" : @"thông minh",
				 SXProviderID([SXPrefs shared].provider));
	}
}
