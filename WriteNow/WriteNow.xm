%config(generator=internal);

#import <HBLog.h>

@import UIKit;
@import WritingToolsInjector;

static UIResponder *_lastResponderForEditing = nil;

@interface UIResponder (WriteNow)
- (id)_responderForEditing;
@end

@interface NSObject (WriteNowPresenterBridge)
+ (instancetype)sharedInstance;
- (BOOL)isReadOnlyEnabled;
- (BOOL)canPerformCustomSlot:(NSInteger)slotIndex isReadOnly:(BOOL)isReadOnly;
@end

static NSInteger WN_SlotIndexForAction(SEL action) {
    NSString *actionName = NSStringFromSelector(action);
    if (!actionName.length) { return -1; }
    if ([actionName isEqualToString:@kWritingToolSelectorName]) {
        return 0;
    }
    NSString *prefix = @kWritingToolCustomSlotPrefix;
    NSString *suffix = @kWritingToolCustomSlotSuffix;
    if ([actionName hasPrefix:prefix] && [actionName hasSuffix:suffix] &&
        actionName.length > prefix.length + suffix.length) {
        NSString *mid = [actionName substringWithRange:NSMakeRange(prefix.length, actionName.length - prefix.length - suffix.length)];
        NSInteger idx = [mid integerValue];
        if (idx >= 1 && idx <= kWritingToolCustomSlotCount) {
            return idx;
        }
    }
    return -1;
}

static BOOL WN_IsTextBearingReadOnlyView(UIView *view) {
    if ([view isKindOfClass:[UIImageView class]] || [view isKindOfClass:[UIWindow class]]) {
        return NO;
    }
    if ([view conformsToProtocol:@protocol(UITextInput)]) {
        id<UITextInput> ti = (id<UITextInput>)view;
        if (ti.selectedTextRange && !ti.selectedTextRange.isEmpty) {
            return YES;
        }
    }
    Class pdfViewCls = NSClassFromString(@"PDFView");
    if (pdfViewCls && [view isKindOfClass:pdfViewCls]) {
        SEL sel = NSSelectorFromString(@"currentSelection");
        if ([view respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id selection = [view performSelector:sel];
#pragma clang diagnostic pop
            if (selection != nil) { return YES; }
        }
    }
    if ([view isKindOfClass:[UILabel class]] ||
        [view respondsToSelector:NSSelectorFromString(@"selectedText")] ||
        [view respondsToSelector:NSSelectorFromString(@"text")] ||
        [view respondsToSelector:NSSelectorFromString(@"attributedText")]) {
        return YES;
    }
    if (@available(iOS 11.0, *)) {
        for (id interaction in view.interactions) {
            NSString *iName = NSStringFromClass([interaction class]);
            if ([iName containsString:@"Text"] || [iName containsString:@"Selection"] || [iName containsString:@"EditMenu"]) {
                return YES;
            }
        }
    }
    NSString *clsName = NSStringFromClass([view class]);
    for (NSString *token in @[@"Text", @"Label", @"Message", @"Chat", @"Web", @"Document", @"Reader", @"SwiftUI", @"PDF", @"Cell", @"Content", @"Note", @"Mail"]) {
        if ([clsName containsString:token]) {
            return YES;
        }
    }
    return NO;
}

%group WriteNowUniversal

%hook WKContentView

%property(nonatomic, strong) NSString *wn_selectedText;
%property(nonatomic, strong) dispatch_semaphore_t wn_isGettingSelectedTextSemaphore;

%new
- (void)accessibilitySpeakSelectionSetContent:(NSString *)string {
    self.wn_selectedText = string;
    if (self.wn_isGettingSelectedTextSemaphore)
        dispatch_semaphore_signal(self.wn_isGettingSelectedTextSemaphore);
}

%end

%hook UIResponder

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    BOOL origRet = %orig;

    NSInteger slotIndex = WN_SlotIndexForAction(action);
    if (slotIndex < 0) {
        return origRet;
    }

    Class presenterCls = NSClassFromString(@"WritingToolsPresenter");
    id presenter = [presenterCls respondsToSelector:@selector(sharedInstance)] ? [presenterCls sharedInstance] : nil;

    UIResponder *responder = [self isKindOfClass:[UIView class]] ? self : _lastResponderForEditing;
    if (![responder isKindOfClass:[UIView class]] || [responder isKindOfClass:[UIWindow class]]) {
        return NO;
    }

    if ([responder isKindOfClass:[UITextView class]]) {
        UITextView *textView = (UITextView *)responder;
        if ([textView isEditable]) {
            return presenter ? [presenter canPerformCustomSlot:slotIndex isReadOnly:NO] : YES;
        }
        BOOL readOnlyAllowed = presenter ? [presenter isReadOnlyEnabled] : YES;
        if (readOnlyAllowed && [textView isSelectable] && (!textView.selectedTextRange.isEmpty || textView.hasText)) {
            return presenter ? [presenter canPerformCustomSlot:slotIndex isReadOnly:YES] : YES;
        }
        return NO;
    }
    else if ([responder isKindOfClass:[UITextField class]]) {
        return presenter ? [presenter canPerformCustomSlot:slotIndex isReadOnly:NO] : YES;
    }
    else if ([responder isKindOfClass:%c(WKContentView)]) {
        WKContentView *contentView = (WKContentView *)responder;
        if ([contentView isFocusingElement]) {
            return presenter ? [presenter canPerformCustomSlot:slotIndex isReadOnly:NO] : YES;
        }
        BOOL readOnlyAllowed = presenter ? [presenter isReadOnlyEnabled] : YES;
        if (readOnlyAllowed && ![contentView.selectedTextRange isEmpty]) {
            return presenter ? [presenter canPerformCustomSlot:slotIndex isReadOnly:YES] : YES;
        }
        return NO;
    }

    // Generic read-only responder (PDFView, SwiftUI Text, UILabel, Chat bubbles, etc.)
    BOOL readOnlyAllowed = presenter ? [presenter isReadOnlyEnabled] : YES;
    if (!readOnlyAllowed) {
        return NO;
    }
    UIView *candidateView = (UIView *)responder;
    if ([self canPerformAction:@selector(copy:) withSender:sender] && WN_IsTextBearingReadOnlyView(candidateView)) {
        return presenter ? [presenter canPerformCustomSlot:slotIndex isReadOnly:YES] : YES;
    }

    return NO;
}

- (UIResponder *)_responderForEditing {
    UIResponder *responder = %orig;
    _lastResponderForEditing = responder;

    HBLogDebug(@"_responderForEditing: %@", responder);
    return responder;
}

%end

%end

%ctor {
    HBLogDebug(@"loaded!");
    %init(WriteNowUniversal);
}
