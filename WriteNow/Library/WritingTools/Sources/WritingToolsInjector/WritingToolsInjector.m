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

static UIView *WT_ResolveActiveMenuTargetView(void);

// MARK: - UIResponder

static void add_UIResponder_openWriteTools(id self, SEL _cmd) {
    NSInteger slotIndex = WT_SlotIndexFromSelectorName(NSStringFromSelector(_cmd));
    if (slotIndex < 0) { slotIndex = 0; }
    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        id resolved = weakSelf;
        UIView *targetView = nil;
        if ([resolved isKindOfClass:[UIView class]]) {
            targetView = (UIView *)resolved;
        } else if ([resolved isKindOfClass:[UIViewController class]]) {
            targetView = [(UIViewController *)resolved view];
        }
        if (!targetView || !targetView.window) {
            targetView = WT_ResolveActiveMenuTargetView();
        }
        if (!targetView) { return; }
        WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
        [presenter presentToolController:targetView slotIndex:slotIndex];
    });
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

// MARK: - UIEditMenuInteraction (iOS 16+)

static void (*old_UIEditMenuInteraction_presentEditMenuWithConfiguration_)(id, SEL, id);
static void new_UIEditMenuInteraction_presentEditMenuWithConfiguration_(id self, SEL _cmd, id configuration) {
    if ([self respondsToSelector:@selector(view)]) {
        UIView *view = [(id)self view];
        if ([view isKindOfClass:[UIView class]]) {
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

static UIView *WT_ResolveActiveMenuTargetView(void) {
    if (gLastEditMenuTargetView && gLastEditMenuTargetView.window && !WT_IsIgnoredInternalWindowOrView(gLastEditMenuTargetView)) {
        return gLastEditMenuTargetView;
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

            if (responderSupportsSelector && !isNonNormalWindow) {
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
                // Subclass overrode canPerformAction: or blocked standard selectors — inject UIActions directly
                __weak UIView *weakTarget = resolvedTarget;
                id capturedCopy = copyElement;
                NSArray<UIMenuElement *> *wtActions = WT_BuildUIActionsForReadOnly(isReadOnly, ^(NSInteger slotIndex) {
                    [presenter presentFromRestrictedMenuTarget:weakTarget
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

    // Fallback for apps that replace com.apple.menu.standard-edit completely with a Copy-only menu
    if (!injected && [presenter isReadOnlyEnabled]) {
        id copyElement = WT_FindCopyMenuElement(build);
        if (copyElement != nil) {
            __weak UIView *weakTarget = activeTarget ?: gLastTouchView;
            id capturedCopy = copyElement;
            NSArray<UIMenuElement *> *wtActions = WT_BuildUIActionsForReadOnly(YES, ^(NSInteger slotIndex) {
                [presenter presentFromRestrictedMenuTarget:weakTarget
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
            // In context menus, grouping multiple actions in a compact inline section keeps layout crisp
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

// MARK: - UICalloutBar @ iOS 15+

static void (*old_UICalloutBar_setExtraItems_)(UICalloutBar *, SEL, NSArray<UIMenuItem *> *);
static void new_UICalloutBar_setExtraItems_(UICalloutBar *self, SEL _cmd, NSArray<UIMenuItem *> *items) {
    NSMutableArray<UIMenuItem *> *newItems = [NSMutableArray arrayWithCapacity:items.count];
    for (UIMenuItem *item in items) {
        NSString *selectorName = NSStringFromSelector(item.action);
        if (WT_SlotIndexFromSelectorName(selectorName) >= 0) {
            item.action = NSSelectorFromString(@"__dummy__");
        }
        [newItems addObject:item];
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

    NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
    BOOL hasEditActions = NO;
    BOOL hasTextSelectionActions = NO;

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
                   [selName isEqualToString:@"_share:"]) {
            hasTextSelectionActions = YES;
        }
    }
    if (toRemove.count > 0) {
        [buttonDescriptions removeObjectsAtIndexes:toRemove];
    }

    if (!hasTextSelectionActions) {
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
