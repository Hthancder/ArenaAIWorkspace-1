// Tweak.x — hook chính của SiriBridge (KHÔNG dùng Logos / substrate)
//
// Vì sao không dùng Logos:
//   %hook của Logos sinh ra lời gọi `MSHookMessageEx` — một symbol KHÔNG có
//   trên hệ thống, chỉ có khi substrate/ElleKit đã nạp. Nếu libhooker nạp
//   chậm hơn dylib của ta, dyld không bind được symbol → process chết ngay
//   lúc load → SpringBoard/Siri vào safe mode.
//   Ở đây ta hook bằng đúng API công khai của libobjc
//   (class_getInstanceMethod + class_replaceMethod) nên **không có một symbol
//   ngoài hệ thống nào**, dyld bind luôn thành công.
//
// Nguyên tắc an toàn khác:
//   • %ctor không I/O nặng, không CFPreferences, không dlopen.
//   • Mọi thứ chạy trong process hệ thống đều bọc @try.
//   • Có crash-loop guard theo từng process.
//   • Chỉ chạy trong SiriViewService.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <UIKit/UIKit.h>

#import "SBConfig.h"
#import "SBCapture.h"
#import "SBEngine.h"
#import "SBTTS.h"
#import "SBHistory.h"
#import "SBDeliver.h"
#import "SBHook.h"
#import "SBLog.h"

#pragma mark - Helpers

static id SBValue(id obj, NSString *key) {
    if (!obj) return nil;
    @try {
        if ([obj respondsToSelector:NSSelectorFromString(key)]) return [obj valueForKey:key];
    } @catch (__unused NSException *e) {}
    return nil;
}

static BOOL SBIsHandledCommand(NSString *className) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"SAUIAddViews", @"SAUIAddDialogs", @"SAUISayIt",
                                    @"SAUIRepeatIt", @"SAUIDisambiguationList"]];
    });
    return [set containsObject:className ?: @""];
}

static NSString *SBDedupText = nil;
static void SBResetTurnDedup(void) { SBDedupText = nil; }
static BOOL SBClaimText(NSString *text) {
    if (!text.length) return NO;
    if ([SBDedupText isEqualToString:text]) return NO;
    SBDedupText = [text copy];
    return YES;
}

static void SBAckCommand(id command, id completion) {
    @try {
        Class ackCls = NSClassFromString(@"SACommandSucceeded");
        id ack = ackCls ? ((id (*)(id, SEL))objc_msgSend)(ackCls,
                    NSSelectorFromString(@"commandSucceeded")) : nil;
        if (ack) {
            id refId = SBValue(command, @"aceId");
            if (refId) SBSetSafe(ack, @"refId", refId);
        }
        if (completion) {
            void (^cb)(id) = completion;
            dispatch_async(dispatch_get_main_queue(), ^{
                @try { cb(ack); } @catch (NSException *e) { SBLog(@"ack cb: %@", e.reason); }
            });
        }
    } @catch (NSException *e) {
        SBLog(@"ACK lỗi: %@", e.reason);
    }
}

#pragma mark - AFUISiriSession hooks

static IMP sOrigWillStart   = NULL;
static IMP sOrigStartReq    = NULL;
static IMP sOrigSpeechRec   = NULL;
static IMP sOrigReceivedCmd = NULL;
static IMP sOrigEnd         = NULL;
static IMP sOrigEndReason   = NULL;

static void SBWillStart(id self, SEL _cmd, id connection) {
    @try {
        SBCaptureClearTurn();
        SBResetTurnDedup();
    } @catch (NSException *e) { SBLog(@"willStart: %@", e.reason); }
    if (sOrigWillStart) ((void (*)(id, SEL, id))sOrigWillStart)(self, _cmd, connection);
}

static void SBStartRequest(id self, SEL _cmd, id options, id completion) {
    @try {
        NSString *text = SBCaptureTextFromRequestOptions(options);
        if (text.length && [[SBConfig shared] shouldHandleTextSafe:text]) {
            SBCaptureRememberTurnText(text);
            SBLog(@"type-to-siri: %@", text);
        }
    } @catch (NSException *e) { SBLog(@"startRequest: %@", e.reason); }
    if (sOrigStartReq) ((void (*)(id, SEL, id, id))sOrigStartReq)(self, _cmd, options, completion);
}

static void SBSpeechRecognized(id self, SEL _cmd, id connection, id recognized) {
    @try {
        NSString *text = SBCaptureTextFromSpeechRecognized(recognized);
        if (text.length && [[SBConfig shared] shouldHandleTextSafe:text]) {
            SBCaptureRememberTurnText(text);
            SBCaptureSetAnswerSink(self);
            SBLog(@"nghe được: %@", text);
        } else {
            SBCaptureRememberTurnText(nil);
        }
    } @catch (NSException *e) { SBLog(@"speechRecognized: %@", e.reason); }
    if (sOrigSpeechRec) ((void (*)(id, SEL, id, id))sOrigSpeechRec)(self, _cmd, connection, recognized);
}

static void SBReceivedCommand(id self, SEL _cmd, id connection, id command, id completion) {
    BOOL swallowed = NO;

    @try {
        SBConfig *cfg = [SBConfig shared];
        NSString *turnText = SBCaptureCurrentTurnText();
        NSString *cls = NSStringFromClass([command class]);

        if (cfg.enabled && cfg.replaceSiri && turnText.length > 0 && SBIsHandledCommand(cls)) {
            swallowed = YES;
            SBLog(@"chặn command %@", cls);

            SBAckCommand(command, completion);

            if (SBClaimText(turnText) && ![[SBEngine shared] busy]) {
                id delegate = SBValue(self, @"delegate") ?: SBValue(self, @"localDelegate");
                if (!delegate) delegate = SBCaptureAnswerSink();
                SBLog(@"xử lý lượt: %@", turnText);
                [[SBEngine shared] handleTurnWithText:turnText session:self delegate:delegate];
            }
        }
    } @catch (NSException *e) {
        SBLog(@"receivedCommand: %@ — %@", e.name, e.reason);
        swallowed = NO;   // lỗi thì trả quyền cho Siri
    }

    if (swallowed) return;

    if (sOrigReceivedCmd) {
        @try {
            ((void (*)(id, SEL, id, id, id))sOrigReceivedCmd)(self, _cmd, connection, command, completion);
        } @catch (NSException *e) {
            SBLog(@"orig receivedCommand: %@", e.reason);
        }
    }
}

static void SBEndSession(id self, SEL _cmd) {
    @try {
        [[SBEngine shared] cancel];
        [[SBTTS shared] stop];
        SBCaptureClearTurn();
    } @catch (NSException *e) { SBLog(@"end: %@", e.reason); }
    if (sOrigEnd) ((void (*)(id, SEL))sOrigEnd)(self, _cmd);
}

static void SBEndForReason(id self, SEL _cmd, long long reason) {
    @try {
        [[SBEngine shared] cancel];
        [[SBTTS shared] stop];
        SBCaptureClearTurn();
    } @catch (NSException *e) { SBLog(@"endForReason: %@", e.reason); }
    if (sOrigEndReason) ((void (*)(id, SEL, long long))sOrigEndReason)(self, _cmd, reason);
}

#pragma mark - SRSiriViewController (lưới an toàn tầng 2)

static IMP sOrigAddViews = NULL;

static void SBAddViews(id self, SEL _cmd, id cmd, id completion) {
    BOOL blocked = NO;

    @try {
        SBConfig *cfg = [SBConfig shared];
        NSString *turnText = SBCaptureCurrentTurnText();
        if (cfg.enabled && cfg.replaceSiri && turnText.length > 0 &&
            [cfg shouldHandleTextSafe:turnText] && SBDeliverIsOwnInjection() == NO) {
            id views = SBValue(cmd, @"views") ?: @[];
            for (id v in views) {
                NSString *t = SBValue(v, @"text");
                if (![t isKindOfClass:[NSString class]]) t = SBValue(v, @"speakableText");
                if ([t isKindOfClass:[NSString class]] && t.length > 1) { blocked = YES; break; }
            }
        }
    } @catch (NSException *e) {
        SBLog(@"addViews guard: %@", e.reason);
        blocked = NO;
    }

    if (blocked) {
        SBLog(@"chặn AddViews dự phòng");
        SBAckCommand(cmd, completion);
        return;
    }
    if (sOrigAddViews) {
        @try {
            ((void (*)(id, SEL, id, id))sOrigAddViews)(self, _cmd, cmd, completion);
        } @catch (NSException *e) {
            SBLog(@"orig addViews: %@", e.reason);
        }
    }
}

#pragma mark - Crash-loop guard

static NSString *const SBGuardPlist   = @"/var/mobile/Library/Preferences/com.hthancder.siribridge.state.plist";
static NSString *const SBSafeModeFile = @"/var/mobile/Library/Preferences/com.hthancder.siribridge.safemode";

static NSDictionary *SBGuardRead(void) {
    @try {
        return [NSDictionary dictionaryWithContentsOfFile:SBGuardPlist] ?: @{};
    } @catch (__unused NSException *e) { return @{}; }
}

static void SBGuardWrite(NSString *bundle, NSString *state, NSString *detail) {
    @try {
        NSMutableDictionary *all = [[NSDictionary dictionaryWithContentsOfFile:SBGuardPlist] mutableCopy]
                                    ?: [NSMutableDictionary dictionary];
        all[bundle ?: @"?"] = @{@"state": state ?: @"?", @"detail": detail ?: @"",
                                @"date": [NSDate date], @"ver": @"0.2.0"};
        [all writeToFile:SBGuardPlist atomically:YES];
    } @catch (__unused NSException *e) {}
}

static BOOL SBSafeModeFileExists(void) {
    @try { return [[NSFileManager defaultManager] fileExistsAtPath:SBSafeModeFile]; }
    @catch (__unused NSException *e) { return NO; }
}

#pragma mark - Cài hook

static BOOL SBInstalled = NO;
static BOOL SBSafeMode  = NO;

static BOOL SBClassHas(Class cls, NSString *sel) {
    if (!cls) return NO;
    @try { return class_getInstanceMethod(cls, NSSelectorFromString(sel)) != NULL; }
    @catch (__unused NSException *e) { return NO; }
}

static void SBInstallHooks(void) {
    if (SBInstalled || SBSafeMode) return;

    @try {
        Class cls = NSClassFromString(@"AFUISiriSession");
        if (!cls) { SBLog(@"process này không có AFUISiriSession"); return; }

        NSArray *required = @[@"assistantConnection:speechRecognized:",
                              @"assistantConnectionRequestWillStart:",
                              @"assistantConnection:receivedCommand:completion:"];
        for (NSString *s in required) {
            if (!SBClassHas(cls, s)) { SBLog(@"thiếu -%@ → không hook", s); return; }
        }

        sOrigWillStart   = SBHookInstanceMethod(cls, NSSelectorFromString(@"assistantConnectionRequestWillStart:"),   (IMP)SBWillStart);
        sOrigStartReq    = SBHookInstanceMethod(cls, NSSelectorFromString(@"startRequestWithOptions:completion:"),     (IMP)SBStartRequest);
        sOrigSpeechRec   = SBHookInstanceMethod(cls, NSSelectorFromString(@"assistantConnection:speechRecognized:"),   (IMP)SBSpeechRecognized);
        sOrigReceivedCmd = SBHookInstanceMethod(cls, NSSelectorFromString(@"assistantConnection:receivedCommand:completion:"), (IMP)SBReceivedCommand);

        if (SBClassHas(cls, @"end"))
            sOrigEnd = SBHookInstanceMethod(cls, NSSelectorFromString(@"end"), (IMP)SBEndSession);
        if (SBClassHas(cls, @"endForReason:"))
            sOrigEndReason = SBHookInstanceMethod(cls, NSSelectorFromString(@"endForReason:"), (IMP)SBEndForReason);

        Class srvc = NSClassFromString(@"SRSiriViewController");
        if (SBClassHas(srvc, @"siriSessionDidReceiveAddViewsCommand:completion:")) {
            sOrigAddViews = SBHookInstanceMethod(srvc,
                NSSelectorFromString(@"siriSessionDidReceiveAddViewsCommand:completion:"), (IMP)SBAddViews);
            SBLog(@"hook dự phòng SRSiriViewController đã cài");
        }

        SBInstalled = (sOrigReceivedCmd != NULL);
        SBLog(@"cài hook: %@", SBInstalled ? @"THÀNH CÔNG" : @"THẤT BẠI");
    } @catch (NSException *e) {
        SBLog(@"cài hook lỗi: %@ — %@", e.name, e.reason);
    }
}

#pragma mark - Signals

static void SBClearHistorySignal(CFNotificationCenterRef c, void *obs, CFStringRef name,
                                 const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [[SBHistory shared] reset];
            SBCaptureClearTurn();
            SBLog(@"đã xoá lịch sử hội thoại");
        } @catch (NSException *e) { SBLog(@"resetHistory: %@", e.reason); }
    });
}

static void SBPrefsChanged(CFNotificationCenterRef c, void *obs, CFStringRef name,
                           const void *obj, CFDictionaryRef info) {
    @try {
        [[SBConfig shared] reload];
        SBLog(@"prefs reloaded (enabled=%d)", [SBConfig shared].enabled);
    } @catch (NSException *e) { SBLog(@"prefsChanged: %@", e.reason); }
}

#pragma mark - Entry

static NSString *SBBundleID(void) {
    @try { return NSBundle.mainBundle.bundleIdentifier ?: @"?"; }
    @catch (__unused NSException *e) { return @"?"; }
}

static void SBDeferredSetup(void) {
    @autoreleasepool {
        @try {
            [[SBConfig shared] reload];

            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                SBPrefsChanged, (__bridge CFStringRef)SBConfigChangedNote, NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                SBClearHistorySignal, CFSTR("com.hthancder.siribridge/resetHistory"), NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);

            SBInstallHooks();

            if (!SBInstalled && !SBSafeMode) {
                __block int attempts = 0;
                dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                    dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
                dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                                          2ull * NSEC_PER_SEC, NSEC_PER_SEC / 2);
                dispatch_source_set_event_handler(timer, ^{
                    if (SBInstalled || attempts++ > 15) { dispatch_source_cancel(timer); return; }
                    dispatch_async(dispatch_get_main_queue(), ^{ SBInstallHooks(); });
                });
                dispatch_resume(timer);
            }

            SBGuardWrite(SBBundleID(), @"ready", @"deferred setup hoàn tất");
            SBLog(@"khởi tạo xong trong %@", SBBundleID());
        } @catch (NSException *e) {
            SBLog(@"deferredSetup: %@ — %@", e.name, e.reason);
            SBGuardWrite(SBBundleID(), @"error", e.reason ?: @"?");
        }
    }
}

__attribute__((constructor))
static void SBCtor(void) {
    @autoreleasepool {
        @try {
            NSString *bundle = SBBundleID();
            SBLogSetTag(bundle);

            // Chỉ SiriViewService. Tweak không hook gì ở SpringBoard nên inject
            // vào đó chỉ tạo thêm đường chết.
            if (![bundle isEqualToString:@"com.apple.SiriViewService"]) {
                SBLog(@"bỏ qua process %@", bundle);
                return;
            }

            SBLog(@"load vào %@ (iOS %@)", bundle, UIDevice.currentDevice.systemVersion);

            NSDictionary *prev = SBGuardRead()[bundle] ?: @{};
            BOOL fileFlag = SBSafeModeFileExists();
            SBSafeMode = fileFlag || [prev[@"state"] isEqual:@"loading"];
            if (SBSafeMode) {
                SBLog(@"SAFE MODE — không cài hook (%@). Lần trước: %@",
                      fileFlag ? @"file safemode" : @"load trước không hoàn tất",
                      prev[@"detail"] ?: @"?");
                SBGuardWrite(bundle, @"safemode", @"bỏ qua do safe mode");
                return;
            }
            SBGuardWrite(bundle, @"loading", @"ctor bắt đầu");

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ SBDeferredSetup(); });

            SBGuardWrite(bundle, @"ctor-ok", @"ctor hoàn tất");
        } @catch (NSException *e) {
            // Constructor mà ném = chết process ⇒ tuyệt đối không để lọt
            NSLog(@"[SiriBridge] ctor exception: %@ — %@", e.name, e.reason);
        }
    }
}
