//
//  WritingToolsInjector.m
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

#import "WritingToolsInjector.h"
#import "WritingToolsPresenter.h"
#import "WritingToolsMenu.h"

#import "PrivateClasses.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static __weak UIView *gLastTouchView = nil;
static __weak UIWindow *gLastTouchWindow = nil;
static CGPoint gLastTouchWindowPoint = {0, 0};
static __weak UIView *gLastEditMenuTargetView = nil;
static __weak UIView *gLastMenuControllerTargetView = nil;
static CGRect gLastMenuControllerTargetRect = {0, 0, 0, 0};
static id gLastCapturedCopyAction = nil;

static BOOL WT_IsIgnoredInternalWindowOrView(UIView *view) {
    if (!view) { return YES; }
    NSString *clsName = NSStringFromClass([view class]);
    if ([clsName containsString:@"WriteNow"] ||
        [clsName containsString:@"InteractiveHighlight"] ||
        [clsName containsString:@"UIKeyboard"] ||
        [clsName containsString:@"UIKBRender"] ||
        [clsName containsString:@"UIEmoji"] ||
        [clsName containsString:@"_UIRemoteKeyboard"]) {
        return YES;
    }
    return NO;
}

static BOOL WT_IsIgnoredPresentedController(UIViewController *vc) {
    if (!vc) { return YES; }
    NSString *clsName = NSStringFromClass([vc class]);
    if ([clsName containsString:@"WritingTool"] ||
        [clsName containsString:@"ScreenTextOverlay"] ||
        [clsName containsString:@"UIActivityViewController"] ||
        [clsName containsString:@"PHPickerViewController"] ||
        [clsName containsString:@"UIDocumentPickerViewController"] ||
        [clsName containsString:@"UIImagePickerController"] ||
        [clsName containsString:@"SFSafariViewController"] ||
        [clsName containsString:@"_UIRemoteViewController"]) {
        return YES;
    }
    return NO;
}

static UIView *WT_FindFirstResponderInView(UIView *view) {
    if (!view) { return nil; }
    if (view.isFirstResponder) { return view; }
    for (UIView *sub in view.subviews) {
        UIView *hit = WT_FindFirstResponderInView(sub);
        if (hit) { return hit; }
    }
    return nil;
}

static UIView *WT_FindTopMostFirstResponderView(void) {
    NSMutableArray<UIWindow *> *candidates = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) { continue; }
        for (UIWindow *win in ((UIWindowScene *)scene).windows) {
            if (!win.isHidden && !WT_IsIgnoredInternalWindowOrView(win)) {
                [candidates addObject:win];
            }
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel != b.windowLevel) {
            return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.isKeyWindow != b.isKeyWindow) {
            return a.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    for (UIWindow *win in candidates) {
        UIView *fr = WT_FindFirstResponderInView(win);
        if (fr && !WT_IsIgnoredInternalWindowOrView(fr)) {
            return fr;
        }
    }
    return nil;
}

static UIView *WT_ResolveActiveMenuTargetView(void) {
    if (gLastEditMenuTargetView && gLastEditMenuTargetView.window && !WT_IsIgnoredInternalWindowOrView(gLastEditMenuTargetView)) {
        return gLastEditMenuTargetView;
    }
    if (gLastMenuControllerTargetView && gLastMenuControllerTargetView.window && !WT_IsIgnoredInternalWindowOrView(gLastMenuControllerTargetView)) {
        return gLastMenuControllerTargetView;
    }
    UIView *fr = WT_FindTopMostFirstResponderView();
    if (fr) {
        return fr;
    }
    if (gLastTouchView && gLastTouchView.window && !WT_IsIgnoredInternalWindowOrView(gLastTouchView)) {
        return gLastTouchView;
    }
    return nil;
}

// MARK: - UIResponder

static void add_UIResponder_openWriteTools(id self, SEL _cmd) {
    NSInteger slotIndex = WT_SlotIndexFromSelectorName(NSStringFromSelector(_cmd));
    if (slotIndex < 0) { slotIndex = 0; }
    __weak id weakSelf = self;
    CGPoint capturedPoint = gLastTouchWindowPoint;
    id capturedCopy = gLastCapturedCopyAction;
    __weak UIView *menuTarget = gLastMenuControllerTargetView ?: gLastEditMenuTargetView;
    __weak UIView *touchView = gLastTouchView;

    dispatch_async(dispatch_get_main_queue(), ^{
        id resolved = weakSelf;
        UIView *targetView = nil;
        if ([resolved isKindOfClass:[UIView class]]) {
            targetView = (UIView *)resolved;
        } else if ([resolved isKindOfClass:[UIViewController class]]) {
            targetView = [(UIViewController *)resolved view];
        }
        if (!targetView || !targetView.window) {
            targetView = menuTarget ?: WT_ResolveActiveMenuTargetView() ?: touchView;
        }
        if (!targetView) { return; }

        WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
        if ([targetView isKindOfClass:[UITextView class]] ||
            [targetView isKindOfClass:[UITextField class]] ||
            [targetView isKindOfClass:NSClassFromString(@"WKWebView") ?: [NSObject class]]) {
            [presenter presentToolController:targetView slotIndex:slotIndex];
        } else {
            [presenter presentFromUniversalMenuTarget:targetView
                                          windowPoint:capturedPoint
                                   fallbackCopyAction:capturedCopy
                                            slotIndex:slotIndex];
        }
    });
}

static BOOL (*old_UIResponder_canPerformAction_withSender_)(UIResponder *, SEL, SEL, id);
static BOOL new_UIResponder_canPerformAction_withSender_(UIResponder *self, SEL _cmd, SEL action, id sender) {
    if (old_UIResponder_canPerformAction_withSender_(self, _cmd, action, sender)) {
        return YES;
    }
    NSInteger slot = WT_SlotIndexFromSelectorName(NSStringFromSelector(action));
    if (slot < 0) {
        return NO;
    }
    if (![self isKindOfClass:[UIView class]]) {
        return NO;
    }
    UIView *view = (UIView *)self;
    if (WT_IsIgnoredInternalWindowOrView(view) || [view isKindOfClass:[UIWindow class]]) {
        return NO;
    }
    BOOL matchesActiveTarget = (view == gLastMenuControllerTargetView ||
                                view == gLastEditMenuTargetView ||
                                view == gLastTouchView ||
                                (gLastTouchView != nil && [gLastTouchView isDescendantOfView:view]) ||
                                (gLastMenuControllerTargetView != nil && [gLastMenuControllerTargetView isDescendantOfView:view]));
    if (!matchesActiveTarget) {
        return NO;
    }
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    if (![presenter shouldUnlockBlockedSelection]) {
        return NO;
    }
    BOOL isReadOnly = [presenter isResponderReadOnly:self];
    return [presenter canPerformCustomSlot:slot isReadOnly:isReadOnly];
}

// MARK: - UIWindow Touch & Picker Attachment

static void (*old_UIWindow_sendEvent_)(UIWindow *, SEL, UIEvent *);
static void new_UIWindow_sendEvent_(UIWindow *self, SEL _cmd, UIEvent *event) {
    if (event.type == UIEventTypeTouches && !self.isHidden) {
        NSString *clsName = NSStringFromClass([self class]);
        if (![clsName containsString:@"WriteNow"] && ![clsName containsString:@"InteractiveHighlight"]) {
            NSSet<UITouch *> *touches = [event touchesForWindow:self];
            if (touches.count == 1) {
                UITouch *touch = touches.anyObject;
                if (touch.phase == UITouchPhaseBegan && !WT_IsIgnoredInternalWindowOrView(touch.view)) {
                    gLastTouchView = touch.view;
                    gLastTouchWindow = self;
                    gLastTouchWindowPoint = [touch locationInView:self];
                }
            }
        }
    }
    old_UIWindow_sendEvent_(self, _cmd, event);
}

static void (*old_UIWindow_becomeKeyWindow)(UIWindow *, SEL);
static void new_UIWindow_becomeKeyWindow(UIWindow *self, SEL _cmd) {
    old_UIWindow_becomeKeyWindow(self, _cmd);
    if (self.windowLevel == UIWindowLevelNormal) {
        NSString *clsName = NSStringFromClass([self class]);
        if (![clsName containsString:@"TextEffects"] && ![clsName containsString:@"WriteNow"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[WritingToolsPresenter sharedInstance] attachScreenPickerToWindow:self];
            });
        }
    }
}

static UIView * _Nullable WT_FindCopyActionViewInRoot(UIView *root, UIWindow *window) {
    if (!root || !window || root.isHidden || root.alpha <= 0.05) { return nil; }
    CGRect winBounds = window.bounds;
    if (winBounds.size.height <= 0) { return nil; }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSInteger visited = 0;
    while (queue.count > 0 && visited < 220) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visited++;

        if (cur.isHidden || cur.alpha <= 0.05 || WT_IsIgnoredInternalWindowOrView(cur)) { continue; }

        NSString *candidateText = nil;
        if ([cur isKindOfClass:[UIButton class]]) {
            candidateText = [(UIButton *)cur currentTitle];
        } else if ([cur isKindOfClass:[UILabel class]]) {
            candidateText = [(UILabel *)cur text];
        }
        if (!candidateText.length && cur.accessibilityLabel.length > 0 && cur.accessibilityLabel.length <= 32) {
            candidateText = cur.accessibilityLabel;
        }

        if (WT_IsCopyTitle(candidateText)) {
            CGRect frameInWin = [cur convertRect:cur.bounds toView:window];
            if (frameInWin.size.height >= 12 &&
                frameInWin.size.height <= 120 &&
                frameInWin.size.width >= 24 &&
                frameInWin.origin.y > winBounds.size.height * 0.25) {
                return cur;
            }
        }

        for (UIView *sub in cur.subviews) {
            [queue addObject:sub];
        }
    }
    return nil;
}

static BOOL WT_ViewHierarchyContainsEditableText(UIView *root) {
    if (!root) { return NO; }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSInteger visited = 0;
    while (queue.count > 0 && visited < 150) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visited++;
        if ([cur isKindOfClass:[UITextView class]] && [(UITextView *)cur isEditable]) { return YES; }
        if ([cur isKindOfClass:[UITextField class]]) { return YES; }
        for (UIView *sub in cur.subviews) {
            [queue addObject:sub];
        }
    }
    return NO;
}

static void (*old_UIWindow_makeKeyAndVisible)(UIWindow *, SEL);
static void new_UIWindow_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    old_UIWindow_makeKeyAndVisible(self, _cmd);
    if (WT_IsIgnoredInternalWindowOrView(self)) { return; }
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"TextEffects"] || [clsName containsString:@"Keyboard"]) { return; }
    if (self.windowLevel <= UIWindowLevelNormal) { return; }

    __weak UIWindow *weakWin = self;
    __weak UIView *capturedTarget = WT_ResolveActiveMenuTargetView() ?: gLastTouchView;
    CGPoint capturedPoint = gLastTouchWindowPoint;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *win = weakWin;
        if (!win || win.isHidden || win.alpha <= 0.05) { return; }
        WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
        if (![presenter isReadOnlyEnabled] || ![presenter shouldInjectIntoContextMenus]) { return; }
        if (WT_ViewHierarchyContainsEditableText(win)) { return; }
        UIView *copyView = WT_FindCopyActionViewInRoot(win, win);
        if (copyView) {
            [presenter attachCopySheetAccessoryToWindow:win
                                             targetView:capturedTarget
                                            windowPoint:capturedPoint
                                               copyView:copyView];
        }
    });
}

// MARK: - UIMenuController (iOS 13-15+ custom menu tracking)

static void (*old_UIMenuController_setTargetRect_inView_)(UIMenuController *, SEL, CGRect, UIView *);
static void new_UIMenuController_setTargetRect_inView_(UIMenuController *self, SEL _cmd, CGRect targetRect, UIView *targetView) {
    if (targetView && !WT_IsIgnoredInternalWindowOrView(targetView)) {
        gLastMenuControllerTargetView = targetView;
        gLastMenuControllerTargetRect = targetRect;
    }
    old_UIMenuController_setTargetRect_inView_(self, _cmd, targetRect, targetView);
}

static void (*old_UIMenuController_showMenuFromView_rect_)(UIMenuController *, SEL, UIView *, CGRect);
static void new_UIMenuController_showMenuFromView_rect_(UIMenuController *self, SEL _cmd, UIView *targetView, CGRect targetRect) {
    if (targetView && !WT_IsIgnoredInternalWindowOrView(targetView)) {
        gLastMenuControllerTargetView = targetView;
        gLastMenuControllerTargetRect = targetRect;
    }
    old_UIMenuController_showMenuFromView_rect_(self, _cmd, targetView, targetRect);
}

static void (*old_UIMenuController_setMenuItems_)(UIMenuController *, SEL, NSArray<UIMenuItem *> *);
static void new_UIMenuController_setMenuItems_(UIMenuController *self, SEL _cmd, NSArray<UIMenuItem *> *menuItems) {
    NSMutableArray<UIMenuItem *> *cleaned = [NSMutableArray arrayWithCapacity:menuItems.count];
    for (UIMenuItem *item in menuItems) {
        if (![item isKindOfClass:[UIMenuItem class]]) { continue; }
        NSString *selName = NSStringFromSelector(item.action);
        if (WT_SlotIndexFromSelectorName(selName) >= 0) { continue; }
        [cleaned addObject:item];
    }

    UIMenuItem *copyItem = WT_FindCopyUIMenuItem(cleaned);
    if (copyItem) {
        gLastCapturedCopyAction = copyItem;
    }

    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    if ([presenter isReadOnlyEnabled] && WT_ExtraItemsContainCopyOrTextAction(cleaned)) {
        NSArray<UIMenuItem *> *wtItems = WT_BuildExtraMenuItemsForReadOnly(YES);
        if (wtItems.count > 0) {
            [cleaned addObjectsFromArray:wtItems];
        }
    }

    old_UIMenuController_setMenuItems_(self, _cmd, [cleaned copy]);
}

// MARK: - UIEditMenuInteraction (iOS 16+)

static void (*old_UIEditMenuInteraction_presentEditMenuWithConfiguration_)(id, SEL, id);
static void new_UIEditMenuInteraction_presentEditMenuWithConfiguration_(id self, SEL _cmd, id configuration) {
    if ([self respondsToSelector:@selector(view)]) {
        UIView *view = [(id)self view];
        if ([view isKindOfClass:[UIView class]] && !WT_IsIgnoredInternalWindowOrView(view)) {
            gLastEditMenuTargetView = view;
        }
    }
    old_UIEditMenuInteraction_presentEditMenuWithConfiguration_(self, _cmd, configuration);
}

// MARK: - Menu Helpers

static BOOL WT_SubmenuHasActionNamed(NSArray *children, NSString *targetSelName) {
    for (id item in children) {
        if ([item isKindOfClass:[UICommand class]]) {
            UICommand *cmd = (UICommand *)item;
            if ([NSStringFromSelector(cmd.action) isEqualToString:targetSelName]) {
                return YES;
            }
        } else if ([item isKindOfClass:[UIMenu class]]) {
            if (WT_SubmenuHasActionNamed([(UIMenu *)item children], targetSelName)) {
                return YES;
            }
        }
    }
    return NO;
}

static UIView *WT_FindActionCapableResponderView(UIView *candidate) {
    if (!candidate) { return nil; }
    SEL sel = NSSelectorFromString(@kWritingToolSelectorName);
    UIResponder *cur = candidate;
    for (NSInteger depth = 0; depth < 8 && cur != nil; depth++) {
        if ([cur isKindOfClass:[UIView class]] && ![cur isKindOfClass:[UIWindow class]]) {
            if ([cur canPerformAction:sel withSender:nil]) {
                return (UIView *)cur;
            }
        }
        cur = cur.nextResponder;
    }
    return nil;
}

static UIMenu *WT_WrapActionsForMode(NSArray<UIMenuElement *> *elements, WritingToolsPresenter *presenter) {
    NSString *mode = [presenter menuPresentationMode];
    if ([mode isEqualToString:@"submenu"] && elements.count > 1) {
        UIImage *sparkles = [UIImage systemImageNamed:@"sparkles"];
        return [UIMenu menuWithTitle:[presenter writingToolMenuName]
                               image:sparkles
                          identifier:WT_CustomSubmenuIdentifier()
                             options:0
                            children:elements];
    }
    return nil;
}

// MARK: - _UIEditMenuPresentation @ iOS 16+

static void (*old__UIEditMenuPresentation_displayMenu_configuration_)(id, SEL, UIMenu *, id);
static void new__UIEditMenuPresentation_displayMenu_configuration_(id self, SEL _cmd, UIMenu *menu, id configuration) {
    NSMutableArray *build = [NSMutableArray new];
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    BOOL injected = NO;
    UIView *activeTarget = WT_ResolveActiveMenuTargetView();
    CGPoint capturedPoint = gLastTouchWindowPoint;

    for (id item in [menu children]) {
        if (WT_MenuItem_IsWritingTool(item)) { continue; }
        if (![item isKindOfClass:[UIMenu class]]) {
            [build addObject:item];
            continue;
        }
        UIMenu *submenu = item;
        if (![submenu.identifier isEqualToString:WT_AppleMenuIdentifier()]) {
            [build addObject:submenu];
            continue;
        }

        NSMutableArray *cleanChildren = [NSMutableArray array];
        for (id child in submenu.children) {
            if (!WT_MenuItem_IsWritingTool(child)) {
                [cleanChildren addObject:child];
            }
        }

        BOOL hasEditActions = WT_SubmenuHasActionNamed(cleanChildren, @"cut:")
            || WT_SubmenuHasActionNamed(cleanChildren, @"paste:");
        id copyElement = WT_FindCopyMenuElement(cleanChildren);
        if (copyElement) {
            gLastCapturedCopyAction = copyElement;
        }
        BOOL hasSelectionActions = hasEditActions
            || copyElement != nil
            || WT_SubmenuHasActionNamed(cleanChildren, @"selectAll:");

        if (hasSelectionActions) {
            BOOL isReadOnly = !hasEditActions;
            UIView *capableTarget = WT_FindActionCapableResponderView(activeTarget)
                ?: WT_FindActionCapableResponderView(WT_FindTopMostFirstResponderView())
                ?: WT_FindActionCapableResponderView(gLastTouchView);
            BOOL responderSupportsSelector = (capableTarget != nil);
            UIView *resolvedTarget = capableTarget ?: activeTarget ?: gLastTouchView;

            BOOL isNonNormalWindow = (resolvedTarget.window != nil && resolvedTarget.window.windowLevel != UIWindowLevelNormal);
            BOOL isStandardTextKit = [resolvedTarget isKindOfClass:[UITextView class]]
                || [resolvedTarget isKindOfClass:[UITextField class]]
                || [resolvedTarget isKindOfClass:NSClassFromString(@"WKWebView") ?: [NSObject class]];

            if (responderSupportsSelector && !isNonNormalWindow && isStandardTextKit) {
                NSArray<UICommand *> *wtCommands = WT_BuildCommandsForReadOnly(isReadOnly);
                if (wtCommands.count > 0) {
                    UIMenu *wrapped = WT_WrapActionsForMode((NSArray<UIMenuElement *> *)wtCommands, presenter);
                    if (wrapped) {
                        [cleanChildren addObject:wrapped];
                    } else {
                        [cleanChildren addObjectsFromArray:wtCommands];
                    }
                    injected = YES;
                }
            } else if (!isReadOnly || [presenter isReadOnlyEnabled]) {
                __weak UIView *weakTarget = resolvedTarget;
                id capturedCopy = copyElement;
                NSArray<UIMenuElement *> *wtActions = WT_BuildUIActionsForReadOnly(isReadOnly, ^(NSInteger slotIndex) {
                    [presenter presentFromUniversalMenuTarget:weakTarget
                                                  windowPoint:capturedPoint
                                           fallbackCopyAction:capturedCopy
                                                    slotIndex:slotIndex];
                });
                if (wtActions.count > 0) {
                    UIMenu *wrapped = WT_WrapActionsForMode(wtActions, presenter);
                    if (wrapped) {
                        [cleanChildren addObject:wrapped];
                    } else {
                        [cleanChildren addObjectsFromArray:wtActions];
                    }
                    injected = YES;
                }
            }
        }

        UIMenu *rebuildAppleMenu = [submenu menuByReplacingChildren:cleanChildren];
        [build addObject:rebuildAppleMenu];
    }

    // Fallback for apps (Facebook, custom editors, readers) that provide custom Copy menu without com.apple.menu.standard-edit
    if (!injected && [presenter isReadOnlyEnabled]) {
        id copyElement = WT_FindCopyMenuElement(build);
        BOOL looksLikeText = (copyElement != nil) || WT_MenuLooksLikeTextOrContentMenu(build);
        if (looksLikeText) {
            if (copyElement) {
                gLastCapturedCopyAction = copyElement;
            }
            __weak UIView *weakTarget = activeTarget ?: gLastTouchView;
            id capturedCopy = copyElement;
            NSArray<UIMenuElement *> *wtActions = WT_BuildUIActionsForReadOnly(YES, ^(NSInteger slotIndex) {
                [presenter presentFromUniversalMenuTarget:weakTarget
                                              windowPoint:capturedPoint
                                       fallbackCopyAction:capturedCopy
                                                slotIndex:slotIndex];
            });
            if (wtActions.count > 0) {
                UIMenu *wrapped = WT_WrapActionsForMode(wtActions, presenter);
                if (wrapped) {
                    [build addObject:wrapped];
                } else {
                    [build addObjectsFromArray:wtActions];
                }
            }
        }
    }

    UIMenu *newMenu = [menu menuByReplacingChildren:build];
    old__UIEditMenuPresentation_displayMenu_configuration_(self, _cmd, newMenu, configuration);
}

// MARK: - UIContextMenuConfiguration (App Long-Press Context Menus @ iOS 15+)

static UIContextMenuConfiguration * (*old_UIContextMenuConfiguration_config)(
    Class,
    SEL,
    id<NSCopying>,
    UIContextMenuContentPreviewProvider,
    UIContextMenuActionProvider
);

static UIContextMenuConfiguration * new_UIContextMenuConfiguration_config(
    Class self,
    SEL _cmd,
    id<NSCopying> identifier,
    UIContextMenuContentPreviewProvider previewProvider,
    UIContextMenuActionProvider actionProvider
) {
    if (!actionProvider) {
        return old_UIContextMenuConfiguration_config(self, _cmd, identifier, previewProvider, actionProvider);
    }

    __weak UIView *capturedView = gLastTouchView;
    CGPoint capturedPoint = gLastTouchWindowPoint;
    UIContextMenuActionProvider copiedProvider = [actionProvider copy];

    UIContextMenuActionProvider wrappedProvider = ^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        UIMenu *origMenu = copiedProvider(suggestedActions);
        if (!origMenu || WT_MenuContainsWriteNow(origMenu)) {
            return origMenu;
        }

        WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
        if (![presenter isReadOnlyEnabled] || ![presenter shouldInjectIntoContextMenus]) {
            return origMenu;
        }

        UIView *targetView = capturedView;
        BOOL looksLikeText = WT_MenuLooksLikeTextOrContentMenu(origMenu.children);
        if (!looksLikeText && targetView) {
            looksLikeText = [presenter hasExtractableTextNearView:targetView windowPoint:capturedPoint];
        }
        if (!looksLikeText) {
            return origMenu;
        }

        id copyElement = WT_FindCopyMenuElement(origMenu.children);
        if (copyElement) {
            gLastCapturedCopyAction = copyElement;
        }
        NSArray<UIMenuElement *> *wtActions = WT_BuildUIActionsForReadOnly(YES, ^(NSInteger slotIndex) {
            [presenter presentFromContextMenuView:targetView
                                      windowPoint:capturedPoint
                                        slotIndex:slotIndex
                               fallbackCopyAction:copyElement];
        });
        if (wtActions.count == 0) {
            return origMenu;
        }

        NSMutableArray<UIMenuElement *> *updated = [origMenu.children mutableCopy] ?: [NSMutableArray array];
        UIMenu *wrapped = WT_WrapActionsForMode(wtActions, presenter);
        if (wrapped) {
            [updated addObject:wrapped];
        } else if (wtActions.count > 1) {
            UIMenu *inlineGroup = [UIMenu menuWithTitle:@""
                                                  image:nil
                                             identifier:WT_CustomSubmenuIdentifier()
                                                options:UIMenuOptionsDisplayInline
                                               children:wtActions];
            [updated addObject:inlineGroup];
        } else {
            [updated addObjectsFromArray:wtActions];
        }
        return [origMenu menuByReplacingChildren:updated];
    };

    return old_UIContextMenuConfiguration_config(self, _cmd, identifier, previewProvider, wrappedProvider);
}

// MARK: - UIViewController Present (UIAlertController ActionSheet + Custom Bottom Sheets like Facebook)

static void (*old_UIViewController_presentViewController_animated_completion_)(
    UIViewController *,
    SEL,
    UIViewController *,
    BOOL,
    void (^)(void)
);

static void new_UIViewController_presentViewController_animated_completion_(
    UIViewController *self,
    SEL _cmd,
    UIViewController *viewControllerToPresent,
    BOOL flag,
    void (^completion)(void)
) {
    if (!viewControllerToPresent || WT_IsIgnoredPresentedController(viewControllerToPresent)) {
        old_UIViewController_presentViewController_animated_completion_(self, _cmd, viewControllerToPresent, flag, completion);
        return;
    }

    __weak UIView *capturedTarget = WT_ResolveActiveMenuTargetView() ?: gLastTouchView;
    CGPoint capturedPoint = gLastTouchWindowPoint;
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];

    // 1. UIAlertController ActionSheet containing "Copy" / "Sao chép"
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
        if (alert.preferredStyle == UIAlertControllerStyleActionSheet && [presenter isReadOnlyEnabled] && [presenter shouldInjectIntoContextMenus]) {
            NSString *wnTitle = [presenter writingToolMenuName];
            BOOL alreadyHasWriteNow = NO;
            UIAlertAction *foundCopyAction = nil;
            for (UIAlertAction *act in alert.actions) {
                if ([act.title isEqualToString:wnTitle]) {
                    alreadyHasWriteNow = YES;
                }
                if (!foundCopyAction && WT_IsCopyTitle(act.title)) {
                    foundCopyAction = act;
                }
            }
            if (foundCopyAction && !alreadyHasWriteNow) {
                UIAlertAction *wnAction = [UIAlertAction actionWithTitle:wnTitle
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(__unused UIAlertAction * _Nonnull action) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [presenter presentFromUniversalMenuTarget:capturedTarget
                                                      windowPoint:capturedPoint
                                               fallbackCopyAction:foundCopyAction
                                                        slotIndex:0];
                    });
                }];
                [alert addAction:wnAction];
            }
        }
        old_UIViewController_presentViewController_animated_completion_(self, _cmd, viewControllerToPresent, flag, completion);
        return;
    }

    old_UIViewController_presentViewController_animated_completion_(self, _cmd, viewControllerToPresent, flag, completion);

    // 2. Custom App Action Sheets / Bottom Sheets (Facebook FDSBottomSheet, Instagram, Messenger, TikTok, Zalo...)
    if ([presenter isReadOnlyEnabled] && [presenter shouldInjectIntoContextMenus]) {
        __weak UIViewController *weakPresented = viewControllerToPresent;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *presented = weakPresented;
            if (!presented || presented.isBeingDismissed || !presented.view.window) { return; }
            if (WT_ViewHierarchyContainsEditableText(presented.view)) { return; }
            UIView *copyView = WT_FindCopyActionViewInRoot(presented.view, presented.view.window);
            if (copyView) {
                [presenter attachCopySheetAccessoryToPresentedVC:presented
                                                      targetView:capturedTarget
                                                     windowPoint:capturedPoint
                                                        copyView:copyView];
            }
        });
    }
}

// MARK: - UICalloutBar @ iOS 15+

static void (*old_UICalloutBar_setExtraItems_)(UICalloutBar *, SEL, NSArray<UIMenuItem *> *);
static void new_UICalloutBar_setExtraItems_(UICalloutBar *self, SEL _cmd, NSArray<UIMenuItem *> *items) {
    NSMutableArray<UIMenuItem *> *newItems = [NSMutableArray arrayWithCapacity:items.count];
    for (UIMenuItem *item in items) {
        if (![item isKindOfClass:[UIMenuItem class]]) { continue; }
        NSString *selectorName = NSStringFromSelector(item.action);
        if (WT_SlotIndexFromSelectorName(selectorName) >= 0) {
            continue;
        }
        [newItems addObject:item];
    }
    UIMenuItem *copyItem = WT_FindCopyUIMenuItem(newItems);
    if (copyItem) {
        gLastCapturedCopyAction = copyItem;
    }
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    if ([presenter isReadOnlyEnabled] && WT_ExtraItemsContainCopyOrTextAction(newItems)) {
        NSArray<UIMenuItem *> *wtItems = WT_BuildExtraMenuItemsForReadOnly(YES);
        if (wtItems.count > 0) {
            [newItems addObjectsFromArray:wtItems];
        }
    }
    old_UICalloutBar_setExtraItems_(self, _cmd, [newItems copy]);
}

static void (*old_UICalloutBar_updateAvailableButtons)(UICalloutBar *, SEL);
static void new_UICalloutBar_updateAvailableButtons(UICalloutBar *self, SEL _cmd) {
    Class cbsbdCls = NSClassFromString(@"_UICalloutBarSystemButtonDescription");
    if (!cbsbdCls || ![cbsbdCls respondsToSelector:@selector(buttonDescriptionWithTitle:action:type:)]) {
        return old_UICalloutBar_updateAvailableButtons(self, _cmd);
    }

    Ivar msbd = class_getInstanceVariable(object_getClass(self), "m_systemButtonDescriptions");
    if (!msbd) { return old_UICalloutBar_updateAvailableButtons(self, _cmd); }

    NSMutableArray *buttonDescriptions = object_getIvar(self, msbd);
    if (![buttonDescriptions isKindOfClass:[NSMutableArray class]]) {
        return old_UICalloutBar_updateAvailableButtons(self, _cmd);
    }

    Ivar extraIvar = class_getInstanceVariable(object_getClass(self), "m_extraItems");
    NSArray<UIMenuItem *> *extraItems = extraIvar ? object_getIvar(self, extraIvar) : nil;
    BOOL extraHasWriteNow = NO;
    BOOL extraHasCopyOrText = NO;
    if ([extraItems isKindOfClass:[NSArray class]]) {
        for (UIMenuItem *item in extraItems) {
            if (![item isKindOfClass:[UIMenuItem class]]) { continue; }
            if (WT_SlotIndexFromSelectorName(NSStringFromSelector(item.action)) >= 0) {
                extraHasWriteNow = YES;
            }
        }
        if (WT_ExtraItemsContainCopyOrTextAction(extraItems)) {
            extraHasCopyOrText = YES;
            UIMenuItem *copyItem = WT_FindCopyUIMenuItem(extraItems);
            if (copyItem) {
                gLastCapturedCopyAction = copyItem;
            }
        }
    }

    NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
    BOOL hasEditActions = NO;
    BOOL hasTextSelectionActions = extraHasCopyOrText;

    for (NSUInteger i = 0; i < buttonDescriptions.count; i++) {
        _UICalloutBarSystemButtonDescription *desc = buttonDescriptions[i];
        if (!desc.action) { continue; }
        NSString *selName = NSStringFromSelector(desc.action);
        if (WT_SlotIndexFromSelectorName(selName) >= 0) {
            [toRemove addIndex:i];
            continue;
        }
        if ([selName isEqualToString:@"cut:"] || [selName isEqualToString:@"paste:"]) {
            hasEditActions = YES;
            hasTextSelectionActions = YES;
        } else if ([selName isEqualToString:@"copy:"] ||
                   [selName isEqualToString:@"selectAll:"] ||
                   [selName isEqualToString:@"_lookup:"] ||
                   [selName isEqualToString:@"_translate:"] ||
                   [selName isEqualToString:@"_share:"] ||
                   [selName.lowercaseString containsString:@"copy"]) {
            hasTextSelectionActions = YES;
        }
    }
    if (toRemove.count > 0) {
        [buttonDescriptions removeObjectsAtIndexes:toRemove];
    }

    if (!hasTextSelectionActions || extraHasWriteNow) {
        return old_UICalloutBar_updateAvailableButtons(self, _cmd);
    }

    BOOL isReadOnly = !hasEditActions;
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    if (isReadOnly && ![presenter isReadOnlyEnabled]) {
        return old_UICalloutBar_updateAvailableButtons(self, _cmd);
    }

    NSMutableArray<_UICalloutBarSystemButtonDescription *> *descriptionsToAdd = [NSMutableArray array];

    if ([presenter shouldShowMainMenuItemForReadOnly:isReadOnly]) {
        UIMenuItem *writeNowItem = WT_MenuItem();
        _UICalloutBarSystemButtonDescription *mainDesc = [cbsbdCls
                                                          buttonDescriptionWithTitle:writeNowItem.title
                                                          action:NSSelectorFromString(@kWritingToolSelectorName)
                                                          type:1];
        if (mainDesc) {
            [descriptionsToAdd addObject:mainDesc];
        }
    }

    NSArray<NSDictionary<NSString *, id> *> *customItems = [presenter customSelectionMenuItemsForReadOnly:isReadOnly];
    for (NSDictionary<NSString *, id> *dict in customItems) {
        NSString *title = dict[@"title"];
        NSString *selName = dict[@"selector"];
        if (![title isKindOfClass:[NSString class]] || !title.length) { continue; }
        if (![selName isKindOfClass:[NSString class]] || !selName.length) { continue; }
        _UICalloutBarSystemButtonDescription *customDesc = [cbsbdCls
                                                            buttonDescriptionWithTitle:title
                                                            action:NSSelectorFromString(selName)
                                                            type:1];
        if (customDesc) {
            [descriptionsToAdd addObject:customDesc];
        }
    }

    if (descriptionsToAdd.count == 0) {
        return old_UICalloutBar_updateAvailableButtons(self, _cmd);
    }

    NSInteger insertIndex = NSNotFound;
    NSInteger currentIndex = 0;
    for (_UICalloutBarSystemButtonDescription *description in buttonDescriptions) {
        if (description.action && [NSStringFromSelector(description.action) hasPrefix:@"_"]) {
            insertIndex = currentIndex;
            break;
        }
        currentIndex++;
    }

    if (insertIndex == NSNotFound || insertIndex > (NSInteger)buttonDescriptions.count) {
        [buttonDescriptions addObjectsFromArray:descriptionsToAdd];
    } else {
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertIndex, descriptionsToAdd.count)];
        [buttonDescriptions insertObjects:descriptionsToAdd atIndexes:indexes];
    }

    return old_UICalloutBar_updateAvailableButtons(self, _cmd);
}

// MARK: - HOOK

__attribute__((always_inline)) void WTHookMessageExecute(Class cls, SEL selName, IMP replaced, IMP *orig) {
    Method origMethod = class_getInstanceMethod(cls, selName);
    if (!origMethod && orig == 0) {
        return;
    }
    *orig = method_setImplementation(origMethod, replaced);
}

__attribute__((always_inline)) void WTHookClassMethodExecute(Class cls, SEL selName, IMP replaced, IMP *orig) {
    Method origMethod = class_getClassMethod(cls, selName);
    if (!origMethod && orig == 0) {
        return;
    }
    *orig = method_setImplementation(origMethod, replaced);
}

__attribute__((always_inline)) BOOL WTAddMessageExecute(Class cls, SEL selName, IMP impl, NSString *sign) {
    if (cls == nil || selName == nil || impl == nil || sign == nil) {
        return NO;
    }
    return class_addMethod(cls, selName, impl, sign.UTF8String);
}

// MARK: - WritingToolsInjector

@implementation WritingToolsInjector

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WTAddMessageExecute(
            [UIResponder class],
            NSSelectorFromString(@kWritingToolSelectorName),
            (IMP)add_UIResponder_openWriteTools,
            @"v@:"
        );

        for (NSInteger i = 1; i <= kWritingToolCustomSlotCount; i++) {
            NSString *slotSel = [NSString stringWithFormat:@"%s%ld%s", kWritingToolCustomSlotPrefix, (long)i, kWritingToolCustomSlotSuffix];
            WTAddMessageExecute(
                [UIResponder class],
                NSSelectorFromString(slotSel),
                (IMP)add_UIResponder_openWriteTools,
                @"v@:"
            );
        }

        WTHookMessageExecute(
            [UIResponder class],
            @selector(canPerformAction:withSender:),
            (IMP)new_UIResponder_canPerformAction_withSender_,
            (IMP *)&old_UIResponder_canPerformAction_withSender_
        );

        WTHookMessageExecute(
            [UIWindow class],
            @selector(sendEvent:),
            (IMP)new_UIWindow_sendEvent_,
            (IMP *)&old_UIWindow_sendEvent_
        );

        WTHookMessageExecute(
            [UIWindow class],
            @selector(becomeKeyWindow),
            (IMP)new_UIWindow_becomeKeyWindow,
            (IMP *)&old_UIWindow_becomeKeyWindow
        );

        WTHookMessageExecute(
            [UIWindow class],
            @selector(makeKeyAndVisible),
            (IMP)new_UIWindow_makeKeyAndVisible,
            (IMP *)&old_UIWindow_makeKeyAndVisible
        );

        WTHookMessageExecute(
            [UIViewController class],
            @selector(presentViewController:animated:completion:),
            (IMP)new_UIViewController_presentViewController_animated_completion_,
            (IMP *)&old_UIViewController_presentViewController_animated_completion_
        );

        Class menuControllerCls = [UIMenuController class];
        if (menuControllerCls) {
            if (class_getInstanceMethod(menuControllerCls, @selector(setTargetRect:inView:))) {
                WTHookMessageExecute(
                    menuControllerCls,
                    @selector(setTargetRect:inView:),
                    (IMP)new_UIMenuController_setTargetRect_inView_,
                    (IMP *)&old_UIMenuController_setTargetRect_inView_
                );
            }
            if (class_getInstanceMethod(menuControllerCls, @selector(showMenuFromView:rect:))) {
                WTHookMessageExecute(
                    menuControllerCls,
                    @selector(showMenuFromView:rect:),
                    (IMP)new_UIMenuController_showMenuFromView_rect_,
                    (IMP *)&old_UIMenuController_showMenuFromView_rect_
                );
            }
            if (class_getInstanceMethod(menuControllerCls, @selector(setMenuItems:))) {
                WTHookMessageExecute(
                    menuControllerCls,
                    @selector(setMenuItems:),
                    (IMP)new_UIMenuController_setMenuItems_,
                    (IMP *)&old_UIMenuController_setMenuItems_
                );
            }
        }

        Class editMenuInteractionCls = NSClassFromString(@"UIEditMenuInteraction");
        if (editMenuInteractionCls) {
            WTHookMessageExecute(
                editMenuInteractionCls,
                NSSelectorFromString(@"presentEditMenuWithConfiguration:"),
                (IMP)new_UIEditMenuInteraction_presentEditMenuWithConfiguration_,
                (IMP *)&old_UIEditMenuInteraction_presentEditMenuWithConfiguration_
            );
        }

        WTHookClassMethodExecute(
            [UIContextMenuConfiguration class],
            @selector(configurationWithIdentifier:previewProvider:actionProvider:),
            (IMP)new_UIContextMenuConfiguration_config,
            (IMP *)&old_UIContextMenuConfiguration_config
        );

        if (@available(iOS 16.0, *)) {
            Class menuPresentationClass = NSClassFromString(@"_UIEditMenuPresentation");
            if (menuPresentationClass) {
                WTHookMessageExecute(
                    menuPresentationClass,
                    NSSelectorFromString(@"displayMenu:configuration:"),
                    (IMP)new__UIEditMenuPresentation_displayMenu_configuration_,
                    (IMP *)&old__UIEditMenuPresentation_displayMenu_configuration_
                );
            }
        } else {
            Class calloutBarClass = NSClassFromString(@"UICalloutBar");
            if (calloutBarClass) {
                WTHookMessageExecute(
                    calloutBarClass,
                    NSSelectorFromString(@"setExtraItems:"),
                    (IMP)new_UICalloutBar_setExtraItems_,
                    (IMP *)&old_UICalloutBar_setExtraItems_
                );
                WTHookMessageExecute(
                    calloutBarClass,
                    NSSelectorFromString(@"updateAvailableButtons"),
                    (IMP)new_UICalloutBar_updateAvailableButtons,
                    (IMP *)&old_UICalloutBar_updateAvailableButtons
                );
            }
        }
    });
}

@end
