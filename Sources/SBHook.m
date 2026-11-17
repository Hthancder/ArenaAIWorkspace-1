// SBHook.m — implementation
#import "SBHook.h"
#import "SBLog.h"
#import <objc/message.h>

// Bảng IMP gốc: key = class + "|" + selector
static NSMutableDictionary<NSString *, id> *gOriginals = nil;
static NSLock *gHookLock = nil;

static NSLock *SBHookLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gHookLock = [NSLock new];
        gOriginals = [NSMutableDictionary dictionary];
    });
    return gHookLock;
}

static NSString *SBKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%p|%s", (void *)cls, sel_getName(sel)];
}

IMP SBHookInstanceMethod(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NULL;

    SBHookLock();
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        // Thử superclass: nhiều method của AFUISiriSession nằm ở lớp cha
        Class super = class_getSuperclass(cls);
        while (super && !m) { m = class_getInstanceMethod(super, sel); super = class_getSuperclass(super); }
    }
    if (!m) { [gHookLock unlock]; return NULL; }

    NSString *key = SBKey(cls, sel);
    IMP previous = (IMP)gOriginals[key];
    if (previous) { [gHookLock unlock]; return previous; }

    IMP original = method_getImplementation(m);
    // class_replaceMethod an toàn hơn method_setImplementation khi method đến từ superclass
    IMP result = class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(m));
    if (!result) {
        // class_replaceMethod trả về IMP cũ; nếu NULL thì method được thêm mới
        result = original;
    }
    gOriginals[key] = (id)original;
    [gHookLock unlock];

    SBLog(@"hook %@ -%s", NSStringFromClass(cls), sel_getName(sel));
    return original;
}

IMP SBOriginalIMP(Class cls, SEL sel) {
    if (!cls || !sel) return NULL;
    SBHookLock();
    IMP imp = (IMP)gOriginals[SBKey(cls, sel)];
    [gHookLock unlock];
    return imp;
}

BOOL SBSetSafe(id obj, NSString *key, id value) {
    if (!obj || !key.length) return NO;
    @try {
        [obj setValue:value forKey:key];
        return YES;
    } @catch (NSException *e) {
        SBLog(@"[KVC] %@.%@ lỗi: %@", NSStringFromClass([obj class]), key, e.reason);
        return NO;
    }
}

BOOL SBHasHook(Class cls, SEL sel) {
    return SBOriginalIMP(cls, sel) != NULL;
}
