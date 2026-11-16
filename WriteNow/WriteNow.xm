%config(generator=internal);

#import <HBLog.h>

@import UIKit;
@import WritingToolsInjector;


static UIResponder *_lastResponderForEditing = nil;

@interface UIResponder (WriteNow)
- (id)_responderForEditing;
@end

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

    NSString *actionName = NSStringFromSelector(action);
    BOOL isWritingToolAction = [actionName isEqualToString:@kWritingToolSelectorName];
    if (!origRet || !isWritingToolAction) {
        return origRet;
    }

    UIResponder *responder = _lastResponderForEditing;
    if ([responder isKindOfClass:[UITextView class]]) {
        UITextView *textView = (UITextView *)responder;
        return [textView isEditable];
    }
    else if ([responder isKindOfClass:[UITextField class]]) {
        return YES;
    }
    else if ([responder isKindOfClass:%c(WKContentView)]) {
        WKContentView *contentView = (WKContentView *)responder;
        return ![contentView.selectedTextRange isEmpty];
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