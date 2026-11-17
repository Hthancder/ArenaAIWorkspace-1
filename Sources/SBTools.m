#import "SBTools.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <EventKit/EventKit.h>
#import <Contacts/Contacts.h>
#import <objc/message.h>
#import "SBLog.h"

// Private nhưng ổn định từ iOS 8 → 15, dùng để mở app không cần URL scheme
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
- (NSArray *)allInstalledApplications;
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *displayName;
@end

@implementation SBTools

+ (NSArray *)openAIToolSpecs {
    NSMutableArray *specs = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSDictionary *) = ^(NSString *name, NSString *desc, NSDictionary *params) {
        [specs addObject:@{@"type": @"function",
                           @"function": @{@"name": name, @"description": desc, @"parameters": params}}];
    };
    NSDictionary *strProp = @{@"type": @"string"};

    add(@"open_app", @"Mở một ứng dụng trên máy theo tên người dùng nói.", @{
        @"type": @"object",
        @"properties": @{@"name": strProp},
        @"required": @[@"name"]});

    add(@"call_phone", @"Gọi điện tới một số điện thoại hoặc tên liên hệ.", @{
        @"type": @"object",
        @"properties": @{@"target": strProp},
        @"required": @[@"target"]});

    add(@"open_url", @"Mở URL (bản đồ, website, deep link).", @{
        @"type": @"object",
        @"properties": @{@"url": strProp},
        @"required": @[@"url"]});

    add(@"add_calendar_event", @"Thêm sự kiện vào Lịch.", @{
        @"type": @"object",
        @"properties": @{@"title": strProp,
                         @"start": @{@"type": @"string", @"description": @"ISO8601, ví dụ 2026-11-17T09:00:00+07:00"},
                         @"duration_minutes": @{@"type": @"number"},
                         @"notes": strProp},
        @"required": @[@"title", @"start"]});

    add(@"add_reminder", @"Tạo nhắc nhở.", @{
        @"type": @"object",
        @"properties": @{@"title": strProp, @"due": @{@"type": @"string", @"description": @"ISO8601, tuỳ chọn"}},
        @"required": @[@"title"]});

    add(@"send_message", @"Mở app Tin nhắn soạn sẵn nội dung cho một liên hệ (không tự gửi).", @{
        @"type": @"object",
        @"properties": @{@"to": strProp, @"body": strProp},
        @"required": @[@"to", @"body"]});

    add(@"media_control", @"Điều khiển nhạc đang phát.", @{
        @"type": @"object",
        @"properties": @{@"action": @{@"type": @"string", @"enum": @[@"play", @"pause", @"next", @"previous"]}},
        @"required": @[@"action"]});

    add(@"device_status", @"Lấy thông tin máy: pin, tên máy, phiên bản iOS, mạng.", @{
        @"type": @"object", @"properties": @{}});

    add(@"list_apps", @"Liệt kê các app đã cài (tên) để tra cứu.", @{
        @"type": @"object", @"properties": @{}});

    add(@"speak_only", @"Không làm gì trên máy; dùng khi chỉ cần trả lời bằng lời.", @{
        @"type": @"object", @"properties": @{@"text": strProp}, @"required": @[@"text"]});

    return specs;
}

+ (BOOL)isKnownTool:(NSString *)name {
    static NSSet *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        known = [NSSet setWithArray:@[@"open_app", @"call_phone", @"open_url", @"add_calendar_event",
                                      @"add_reminder", @"send_message", @"media_control",
                                      @"device_status", @"list_apps", @"speak_only"]];
    });
    return [known containsObject:name ?: @""];
}

#pragma mark - Helpers

+ (NSDictionary *)args:(NSString *)json {
    if (!json.length) return @{};
    id o = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                           options:0 error:NULL];
    return [o isKindOfClass:[NSDictionary class]] ? o : @{};
}

+ (void)finish:(NSString *)r completion:(void (^)(NSString *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(r ?: @"ok"); });
}

+ (NSString *)resolveBundleIDForName:(NSString *)name {
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    if (!ws) return nil;
    id space = [ws performSelector:@selector(defaultWorkspace)];
    if (![space respondsToSelector:@selector(allInstalledApplications)]) return nil;
    NSArray *apps = [space performSelector:@selector(allInstalledApplications)];
    NSString *needle = name.lowercaseString;
    NSString *best = nil; NSUInteger bestScore = 0;
    for (id app in apps) {
        NSString *display = nil; NSString *bid = nil;
        @try { display = [app valueForKey:@"displayName"]; bid = [app valueForKey:@"bundleIdentifier"]; } @catch (...) {}
        if (!bid) continue;
        NSString *d = display.lowercaseString ?: @"";
        NSUInteger score = 0;
        if ([d isEqualToString:needle]) score = 100;
        else if (d.length && [d containsString:needle]) score = 60;
        else if (needle.length && [needle containsString:d] && d.length > 2) score = 40;
        else if ([bid.lowercaseString containsString:needle]) score = 30;
        if (score > bestScore) { bestScore = score; best = bid; }
    }
    return best;
}

#pragma mark - Run

+ (void)runTool:(NSString *)name arguments:(NSString *)json completion:(void (^)(NSString *))completion {
    @try {
        [self sb_runTool:name arguments:json completion:completion];
    } @catch (NSException *e) {
        SBLog(@"tool %@ exception: %@ — %@", name, e.name, e.reason);
        // Không được để SBEngine treo chờ mãi
        [self finish:[NSString stringWithFormat:@"tool %@ lỗi", name] completion:completion];
    }
}

+ (void)sb_runTool:(NSString *)name arguments:(NSString *)json completion:(void (^)(NSString *))completion {
    NSDictionary *a = [self args:json];
    SBLog(@"tool %@ %@", name, json);

    if ([name isEqualToString:@"speak_only"]) {
        [self finish:(a[@"text"] ?: @"ok") completion:completion]; return;
    }
    if ([name isEqualToString:@"device_status"]) {
        UIDevice *d = UIDevice.currentDevice;
        [d setBatteryMonitoringEnabled:YES];
        NSString *s = [NSString stringWithFormat:@"%@, iOS %@, pin %d%%",
                       d.name, d.systemVersion, (int)roundf(d.batteryLevel * 100)];
        [self finish:s completion:completion]; return;
    }
    if ([name isEqualToString:@"list_apps"]) {
        Class ws = NSClassFromString(@"LSApplicationWorkspace");
        if (!ws) { [self finish:@"không truy cập được" completion:completion]; return; }
        id space = [ws performSelector:@selector(defaultWorkspace)];
        if (![space respondsToSelector:@selector(allInstalledApplications)]) {
            [self finish:@"không truy cập được" completion:completion]; return;
        }
        NSArray *apps = [space performSelector:@selector(allInstalledApplications)];
        NSMutableArray *names = [NSMutableArray array];
        for (id app in apps) {
            NSString *n = nil; @try { n = [app valueForKey:@"displayName"]; } @catch (...) {}
            if (n.length) [names addObject:n];
            if (names.count > 120) break;
        }
        [self finish:[names componentsJoinedByString:@", "] completion:completion]; return;
    }
    if ([name isEqualToString:@"open_app"]) {
        NSString *appName = a[@"name"];
        NSString *bid = [self resolveBundleIDForName:appName ?: @""];
        if (!bid) { [self finish:[NSString stringWithFormat:@"không tìm thấy app %@", appName]
                      completion:completion]; return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                Class ws = NSClassFromString(@"LSApplicationWorkspace");
                id space = [ws performSelector:@selector(defaultWorkspace)];
                SEL s = NSSelectorFromString(@"openApplicationWithBundleID:");
                BOOL ok = [space respondsToSelector:s] &&
                          ((BOOL (*)(id, SEL, id))objc_msgSend)(space, s, bid);
                if (completion) completion(ok ? [NSString stringWithFormat:@"đã mở %@", appName] : @"mở thất bại");
            } @catch (NSException *e) {
                SBLog(@"open_app: %@", e.reason);
                if (completion) completion(@"mở thất bại");
            }
        });
        return;
    }
    if ([name isEqualToString:@"open_url"]) {
        NSString *s = a[@"url"];
        NSURL *url = [NSURL URLWithString:s];
        if (!url) { [self finish:@"url sai" completion:completion]; return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            __block BOOL ok = NO;
            Class ws = NSClassFromString(@"LSApplicationWorkspace");
            if (ws) {
                // openSensitiveURL là API nội bộ; dùng @try vì có thể không tồn tại
                @try {
                    SEL sel = NSSelectorFromString(@"openSensitiveURL:withOptions:");
                    id space = [ws performSelector:@selector(defaultWorkspace)];
                    if ([space respondsToSelector:sel]) {
                        ok = ((id (*)(id, SEL, id, id))objc_msgSend)(space, sel, url, @{}) != nil;
                    }
                } @catch (__unused NSException *e) { ok = NO; }
            }
            if (completion) completion(ok ? @"đã mở" : @"không mở được");
        });
        return;
    }
    if ([name isEqualToString:@"call_phone"]) {
        NSString *target = a[@"target"] ?: @"";
        NSString *digits = [[target componentsSeparatedByCharactersInSet:
                              [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        NSString *urlStr = nil;
        if (digits.length >= 3) urlStr = [@"tel://" stringByAppendingString:digits];
        else urlStr = [NSString stringWithFormat:@"tel://%@", [target stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
        [self runTool:@"open_url" arguments:[NSString stringWithFormat:@"{\"url\":\"%@\"}", urlStr] completion:completion];
        return;
    }
    if ([name isEqualToString:@"media_control"]) {
        NSString *action = a[@"action"] ?: @"play";
        MPMusicPlayerController *pc = [MPMusicPlayerController systemMusicPlayer];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([action isEqualToString:@"play"]) [pc play];
            else if ([action isEqualToString:@"pause"]) [pc pause];
            else if ([action isEqualToString:@"next"]) [pc skipToNextItem];
            else if ([action isEqualToString:@"previous"]) [pc skipToPreviousItem];
            if (completion) completion([NSString stringWithFormat:@"nhạc: %@", action]);
        });
        return;
    }
    if ([name isEqualToString:@"add_calendar_event"] || [name isEqualToString:@"add_reminder"]) {
        BOOL reminder = [name isEqualToString:@"add_reminder"];
        EKEventStore *store = [EKEventStore new];
        EKAuthorizationStatus st = [EKEventStore authorizationStatusForEntityType:
                                    reminder ? EKEntityTypeReminder : EKEntityTypeEvent];
        void (^create)(void) = ^{
            NSError *err = nil;
            NSDate *start = nil;
            NSString *iso = reminder ? a[@"due"] : a[@"start"];
            if (iso.length) {
                NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
                f.formatOptions = NSISO8601DateFormatWithInternetDateTime;
                start = [f dateFromString:iso];
            }
            if (!start) start = [NSDate dateWithTimeIntervalSinceNow:3600];
            NSNumber *dur = a[@"duration_minutes"];
            NSDate *end = [start dateByAddingTimeInterval:(dur ? dur.doubleValue : 60) * 60];

            if (reminder) {
                EKReminder *r = [EKReminder reminderWithEventStore:store];
                r.title = a[@"title"]; r.calendar = [store defaultCalendarForNewReminders];
                r.dueDateComponents = [[NSCalendar currentCalendar] componentsInTimeZone:[NSTimeZone localTimeZone] fromDate:start];
                [store saveReminder:r commit:YES error:&err];
            } else {
                EKEvent *e = [EKEvent eventWithEventStore:store];
                e.title = a[@"title"]; e.startDate = start; e.endDate = end;
                e.notes = a[@"notes"]; e.calendar = [store defaultCalendarForNewEvents];
                [store saveEvent:e span:EKSpanThisEvent commit:YES error:&err];
            }
            if (completion) completion(err ? err.localizedDescription : @"đã thêm");
        };
        if (st == EKAuthorizationStatusNotDetermined) {
            [store requestAccessToEntityType:(reminder ? EKEntityTypeReminder : EKEntityTypeEvent)
                                  completion:^(BOOL granted, NSError *e) {
                if (granted) create();
                else if (completion) completion(@"chưa được cấp quyền Lịch/Nhắc nhở");
            }];
        } else if (st == EKAuthorizationStatusAuthorized) {
            create();
        } else if (completion) {
            completion(@"chưa được cấp quyền Lịch/Nhắc nhở");
        }
        return;
    }
    if ([name isEqualToString:@"send_message"]) {
        NSString *to = a[@"to"] ?: @""; NSString *body = a[@"body"] ?: @"";
        NSString *url = [NSString stringWithFormat:@"sms:%@&body=%@",
                         [to stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]],
                         [body stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        [self runTool:@"open_url" arguments:[NSString stringWithFormat:@"{\"url\":\"%@\"}", url] completion:completion];
        return;
    }

    [self finish:[NSString stringWithFormat:@"tool %@ chưa hỗ trợ", name] completion:completion];
}

@end
