// Tweak.x — hook chính của SiriBridge
//
// Nguyên tắc:
//  * Chỉ inject vào com.apple.springboard và com.apple.SiriViewService (xem SiriBridge.plist).
//  * Không hook gì khi chưa bật trong Settings (đọc config ở runtime).
//  * Chỉ chặn câu trả lời của Siri khi ReplaceSiri = YES; mọi thứ khác vẫn để Siri xử lý.
//  * Không bao giờ gọi %orig hai lần; completion của receivedCommand luôn được gọi.

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

#define SBLog(fmt, ...) NSLog(@"[SiriBridge] " fmt, ##__VA_ARGS__)

#pragma mark - Tiện ích

static id SBValue(id obj, NSString *key) {
    if (!obj) return nil;
    @try {
        if ([obj respondsToSelector:NSSelectorFromString(key)]) return [obj valueForKey:key];
    } @catch (__unused NSException *e) {}
    return nil;
}

static BOOL SBIsHandledCommand(NSString *className) {
    // Các command mang nội dung trả lời của Siri. Khi Replace = YES ta chặn hết.
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"SAUIAddViews", @"SAUIAddDialogs", @"SAUISayIt",
                                    @"SAUIRepeatIt", @"SAUIClearScreen", @"SAUIDisambiguationList"]];
    });
    return [set containsObject:className ?: @""];
}

// Chống xử lý trùng: mỗi câu chỉ chạy 1 lần cho tới request tiếp theo
static NSString *SBDedupText = nil;
static void SBResetTurnDedup(void) { SBDedupText = nil; }
static BOOL SBClaimText(NSString *text) {
    if (!text.length) return NO;
    if ([SBDedupText isEqualToString:text]) return NO;
    SBDedupText = [text copy];
    return YES;
}

#pragma mark - Hook: AFUISiriSession

%group SBSiriSession

%hook AFUISiriSession

// Bắt đầu request → reset turn
- (void)assistantConnectionRequestWillStart:(id)connection {
    SBCaptureClearTurn();
    SBResetTurnDedup();
    %orig;
}

// Type-to-Siri: text nằm ngay trong request options.
// Ta chỉ GHI NHỚ text rồi để Siri chạy bình thường (state machine cần %orig).
// Câu trả lời của Siri sẽ bị chặn ở `receivedCommand:` và thay bằng câu của LLM.
- (void)startRequestWithOptions:(id)options completion:(id)completion {
    NSString *text = SBCaptureTextFromRequestOptions(options);
    if (text.length && [SBConfig.shared shouldHandleText:text]) {
        SBCaptureRememberTurnText(text);
        SBLog(@"type-to-siri: %@", text);
    }
    %orig;
}

// Kết quả nhận dạng giọng nói cuối cùng
- (void)assistantConnection:(id)connection speechRecognized:(id)recognized {
    NSString *text = SBCaptureTextFromSpeechRecognized(recognized);
    if (text.length && [SBConfig.shared shouldHandleText:text]) {
        SBCaptureRememberTurnText(text);
        SBCaptureSetAnswerSink(self);
    } else {
        SBCaptureRememberTurnText(nil);
    }
    %orig;
}

// Điểm chặn duy nhất: mọi ACE từ server đều qua đây
- (void)assistantConnection:(id)connection receivedCommand:(id)command completion:(id)completion {
    SBConfig *cfg = [SBConfig shared];
    NSString *turnText = SBCaptureCurrentTurnText();
    NSString *cls = NSStringFromClass([command class]);

    BOOL interested = cfg.enabled && cfg.replaceSiri && turnText.length > 0 && SBIsHandledCommand(cls);
    if (!interested) {
        %orig;
        return;
    }

    // Chặn: không cho câu trả lời của Siri đi tiếp vào UI/TTS
    SBLog(@"chặn command %@", cls);

    // Trả lời ACK cho state machine để không bị treo
    Class ackCls = NSClassFromString(@"SACommandSucceeded");
    if (ackCls) {
        id ack = ((id (*)(id, SEL))objc_msgSend)(ackCls, NSSelectorFromString(@"commandSucceeded"));
        @try {
            if ([command respondsToSelector:NSSelectorFromString(@"aceId")])
                [ack setValue:SBValue(command, @"aceId") forKey:@"refId"];
        } @catch (__unused NSException *e) {}
        if (completion) {
            void (^cb)(id) = completion;
            dispatch_async(dispatch_get_main_queue(), ^{ cb(ack); });
        }
    } else if (completion) {
        void (^cb)(id) = completion;
        dispatch_async(dispatch_get_main_queue(), ^{ cb(nil); });
    }

    // Khởi động lượt LLM: mỗi câu chỉ một lần trong một request
    if (!SBClaimText(turnText)) return;
    if ([[SBEngine shared] busy]) return;
    id delegate = SBValue(self, @"delegate");
    id localDelegate = SBValue(self, @"localDelegate");
    id sink = delegate ?: localDelegate;
    SBLog(@"xử lý lượt: %@", turnText);
    [[SBEngine shared] handleTurnWithText:turnText session:self delegate:sink];
}

// Siri bị đóng → dọn dẹp
- (void)end {
    [[SBEngine shared] cancel];
    [[SBTTS shared] stop];
    SBCaptureClearTurn();
    %orig;
}

- (void)endForReason:(long long)reason {
    [[SBEngine shared] cancel];
    [[SBTTS shared] stop];
    SBCaptureClearTurn();
    %orig;
}

%end

%end

#pragma mark - Hook: SRSiriViewController (fallback nếu delegate nil)

%group SBSiriViewController

%hook SRSiriViewController

// Lưới an toàn: nếu vì lý do nào đó `receivedCommand:` không chặn được
// (Siri tự sinh AddViews cục bộ, ví dụ lỗi mạng), ta chặn ở đây.
// Bỏ qua khi chính SiriBridge đang bơm câu trả lời của nó.
- (void)siriSessionDidReceiveAddViewsCommand:(id)cmd completion:(id)completion {
    SBConfig *cfg = [SBConfig shared];
    NSString *turnText = SBCaptureCurrentTurnText();
    BOOL blocked = cfg.enabled && cfg.replaceSiri && turnText.length > 0 &&
                   [cfg shouldHandleText:turnText] && (SBDeliverIsOwnInjection() == NO);
    if (blocked) {
        BOOL hasRealText = NO;
        for (id v in (SBValue(cmd, @"views") ?: @[])) {
            NSString *t = SBValue(v, @"text");
            if (![t isKindOfClass:[NSString class]]) t = SBValue(v, @"speakableText");
            if (t.length > 1) { hasRealText = YES; break; }
        }
        if (hasRealText) {
            SBLog(@"chặn AddViews dự phòng");
            Class ackCls = NSClassFromString(@"SACommandSucceeded");
            id ack = ackCls ? ((id (*)(id, SEL))objc_msgSend)(ackCls, NSSelectorFromString(@"commandSucceeded")) : nil;
            if (completion) {
                void (^cb)(id) = completion;
                dispatch_async(dispatch_get_main_queue(), ^{ cb(ack); });
            }
            return;
        }
    }
    %orig;
}

%end

%end

#pragma mark - Cài đặt hook có kiểm tra

static BOOL SBInstalled = NO;

static BOOL SBClassHas(Class cls, NSString *sel) {
    return cls && class_getInstanceMethod(cls, NSSelectorFromString(sel)) != NULL;
}

static void SBInstall(void) {
    if (SBInstalled) return;
    Class sessionCls = NSClassFromString(@"AFUISiriSession");
    if (!sessionCls) { SBLog(@"không có AFUISiriSession"); return; }

    NSArray *required = @[@"assistantConnection:speechRecognized:",
                          @"assistantConnectionRequestWillStart:",
                          @"assistantConnection:receivedCommand:completion:"];
    for (NSString *s in required) {
        if (!SBClassHas(sessionCls, s)) {
            SBLog(@"thiếu method %@, không hook", s);
            return;
        }
    }
    %init(SBSiriSession, AFUISiriSession = sessionCls);

    Class srvc = NSClassFromString(@"SRSiriViewController");
    if (SBClassHas(srvc, @"siriSessionDidReceiveAddViewsCommand:completion:")) {
        %init(SBSiriViewController, SRSiriViewController = srvc);
        SBLog(@"hook dự phòng SRSiriViewController đã cài");
    }

    SBInstalled = YES;
    SBLog(@"hooks đã cài (AFUISiriSession)");
}

// Tín hiệu xoá lịch sử từ Settings (chạy trên main queue)
static void SBClearHistorySignal(CFNotificationCenterRef c, void *obs, CFStringRef name,
                                 const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SBHistory shared] reset];
        SBCaptureClearTurn();
        SBLog(@"đã xoá lịch sử hội thoại");
    });
}

#pragma mark - Entry

static void SBPrefsChanged(CFNotificationCenterRef c, void *obs, CFStringRef name,
                           const void *obj, CFDictionaryRef info) {
    [[SBConfig shared] reload];
    SBLog(@"prefs reloaded (enabled=%d)", SBConfig.shared.enabled);
}

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"?";
        SBLog(@"load vào %@ trên iOS %@", bundle, UIDevice.currentDevice.systemVersion);

        [[SBConfig shared] reload];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            SBPrefsChanged, (__bridge CFStringRef)SBConfigChangedNote, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            SBClearHistorySignal, CFSTR("com.hthancder.siribridge/resetHistory"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        // Chỉ cài hook trong tiến trình Siri UI
        if ([bundle isEqualToString:@"com.apple.SiriViewService"] ||
            [bundle isEqualToString:@"com.apple.springboard"]) {
            // AFUISiriSession được load trễ → thử ngay, rồi thử lại sau
            SBInstall();
            if (!SBInstalled) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    SBInstall();
                    if (!SBInstalled) SBLog(@"vẫn chưa cài được hook");
                });
            }
        }
    }
}
