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

// MARK: - UIResponder

static void add_UIResponder_openWriteTools(id self, SEL _cmd) {
    NSInteger slotIndex = WT_SlotIndexFromSelectorName(NSStringFromSelector(_cmd));
    if (slotIndex < 0) { slotIndex = 0; }
    dispatch_async(dispatch_get_main_queue(), ^{
        WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
        [presenter presentToolController:self slotIndex:slotIndex];
    });
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

// MARK: - _UIEditMenuPresentation @ iOS 16+

static void (*old__UIEditMenuPresentation_displayMenu_configuration_)(id, SEL, UIMenu *, id);
static void new__UIEditMenuPresentation_displayMenu_configuration_(id self, SEL _cmd, UIMenu *menu, id configuration) {
    NSMutableArray *build = [NSMutableArray new];
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];

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
        BOOL hasSelectionActions = hasEditActions
            || WT_SubmenuHasActionNamed(cleanChildren, @"copy:")
            || WT_SubmenuHasActionNamed(cleanChildren, @"selectAll:");

        if (hasSelectionActions) {
            BOOL isReadOnly = !hasEditActions;
            NSArray<UICommand *> *wtCommands = WT_BuildCommandsForReadOnly(isReadOnly);
            if (wtCommands.count > 0) {
                NSString *mode = [presenter menuPresentationMode];
                if ([mode isEqualToString:@"submenu"] && wtCommands.count > 1) {
                    UIImage *sparkles = [UIImage systemImageNamed:@"sparkles"];
                    UIMenu *wtMenu = [UIMenu menuWithTitle:[presenter writingToolMenuName]
                                                     image:sparkles
                                                identifier:WT_CustomSubmenuIdentifier()
                                                   options:0
                                                  children:wtCommands];
                    [cleanChildren addObject:wtMenu];
                } else {
                    [cleanChildren addObjectsFromArray:wtCommands];
                }
            }
        }

        UIMenu *rebuildAppleMenu = [submenu menuByReplacingChildren:cleanChildren];
        [build addObject:rebuildAppleMenu];
    }

    UIMenu *newMenu = [menu menuByReplacingChildren:build];
    old__UIEditMenuPresentation_displayMenu_configuration_(self, _cmd, newMenu, configuration);
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

    // Remove previously injected WriteNow slot descriptions before rebuilding
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
        [self _initializeWritingTool];
    });
}

+ (void)_initializeWritingTool {
    Class responderCls = NSClassFromString(@"UIResponder");
    WTAddMessageExecute(responderCls, NSSelectorFromString(@kWritingToolSelectorName),
                        (IMP)add_UIResponder_openWriteTools, @"v@:");

    for (NSInteger slot = 1; slot <= kWritingToolCustomSlotCount; slot++) {
        NSString *slotSelName = [NSString stringWithFormat:@"%s%ld%s", kWritingToolCustomSlotPrefix, (long)slot, kWritingToolCustomSlotSuffix];
        WTAddMessageExecute(responderCls, NSSelectorFromString(slotSelName),
                            (IMP)add_UIResponder_openWriteTools, @"v@:");
    }

    if (@available(iOS 16, *)) {
        Class targetCls = NSClassFromString(@"_UIEditMenuContentPresentation");
        if (!targetCls) {
            targetCls = NSClassFromString(@"_UIEditMenuPresentation");
        }
        WTHookMessageExecute(targetCls, @selector(displayMenu:configuration:),
                             (IMP)new__UIEditMenuPresentation_displayMenu_configuration_,
                             (IMP *)&old__UIEditMenuPresentation_displayMenu_configuration_);
    } else if (@available(iOS 15, *)) {
        WTHookMessageExecute(NSClassFromString(@"UICalloutBar"), @selector(setExtraItems:),
                             (IMP)new_UICalloutBar_setExtraItems_, (IMP *)&old_UICalloutBar_setExtraItems_);
        WTHookMessageExecute(NSClassFromString(@"UICalloutBar"), @selector(updateAvailableButtons),
                             (IMP)new_UICalloutBar_updateAvailableButtons,
                             (IMP *)&old_UICalloutBar_updateAvailableButtons);
    }
}

@end
