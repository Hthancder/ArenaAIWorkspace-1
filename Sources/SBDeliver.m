#import "SBDeliver.h"
#import <objc/message.h>

#define SBLog(fmt, ...) NSLog(@"[SiriBridge] " fmt, ##__VA_ARGS__)

static BOOL gOwnInjection = NO;

BOOL SBDeliverIsOwnInjection(void) { return gOwnInjection; }
void SBDeliverMarkOwn(BOOL own)    { gOwnInjection = own; }

BOOL SBDeliverCommand(id delegate, id command, NSString *selectorName) {
    if (!delegate || !command || !selectorName.length) return NO;
    SEL sel = NSSelectorFromString(selectorName);
    if (![delegate respondsToSelector:sel]) {
        SBLog(@"delegate %@ không có %@", NSStringFromClass([delegate class]), selectorName);
        return NO;
    }

    void (^completion)(id) = ^(id ack) {
        SBLog(@"%@ xong", selectorName);
    };

    BOOL prev = gOwnInjection;
    gOwnInjection = YES;
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, sel, command, completion);
        return YES;
    } @catch (NSException *e) {
        SBLog(@"gọi %@ lỗi: %@", selectorName, e.reason);
        return NO;
    } @finally {
        gOwnInjection = prev;
    }
}
