//
//  WritingToolsMenu.m
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/20.
//

#import "WritingToolsInjector.h"
#import "WritingToolsPresenter.h"
#import "WritingToolsMenu.h"

NSString *WT_AppleMenuIdentifier(void) {
    return @"com.apple.menu.standard-edit";
}

NSString *WT_CustomSubmenuIdentifier(void) {
    return @"wiki.qaq.writenow.editmenu";
}

NSInteger WT_SlotIndexFromSelectorName(NSString *name) {
    if (!name.length) { return -1; }
    if ([name isEqualToString:@kWritingToolSelectorName]) { return 0; }
    NSString *prefix = @kWritingToolCustomSlotPrefix;
    NSString *suffix = @kWritingToolCustomSlotSuffix;
    if ([name hasPrefix:prefix] && [name hasSuffix:suffix] && name.length > prefix.length + suffix.length) {
        NSString *mid = [name substringWithRange:NSMakeRange(prefix.length, name.length - prefix.length - suffix.length)];
        NSInteger idx = [mid integerValue];
        if (idx >= 1 && idx <= kWritingToolCustomSlotCount) {
            return idx;
        }
    }
    return -1;
}

UIMenuItem *WT_MenuItem(void) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    return [[UIMenuItem alloc] initWithTitle:presenter.writingToolMenuName
                                      action:NSSelectorFromString(@kWritingToolSelectorName)];
}

UICommand *WT_MenuItem_UICommand(void) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    UIImage *img = nil;
    if (@available(iOS 13.0, *)) {
        img = [UIImage systemImageNamed:@"sparkles"];
    }
    return [UICommand commandWithTitle:presenter.writingToolMenuName
                                 image:img
                                action:NSSelectorFromString(@kWritingToolSelectorName)
                          propertyList:nil];
}

NSArray<UICommand *> *WT_BuildCommandsForReadOnly(BOOL isReadOnly) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    NSMutableArray<UICommand *> *commands = [NSMutableArray array];

    if ([presenter shouldShowMainMenuItemForReadOnly:isReadOnly]) {
        [commands addObject:WT_MenuItem_UICommand()];
    }

    NSArray<NSDictionary<NSString *, id> *> *customItems = [presenter customSelectionMenuItemsForReadOnly:isReadOnly];
    for (NSDictionary<NSString *, id> *dict in customItems) {
        NSString *title = dict[@"title"];
        NSString *selName = dict[@"selector"];
        NSString *iconName = dict[@"icon"];
        if (![title isKindOfClass:[NSString class]] || !title.length) { continue; }
        if (![selName isKindOfClass:[NSString class]] || !selName.length) { continue; }
        UIImage *img = nil;
        if (@available(iOS 13.0, *)) {
            if ([iconName isKindOfClass:[NSString class]] && iconName.length) {
                img = [UIImage systemImageNamed:iconName];
            }
        }
        UICommand *cmd = [UICommand commandWithTitle:title
                                              image:img
                                             action:NSSelectorFromString(selName)
                                       propertyList:nil];
        if (cmd) {
            [commands addObject:cmd];
        }
    }
    return [commands copy];
}

NSArray<UIMenuElement *> *WT_BuildUIActionsForReadOnly(BOOL isReadOnly, void (^handler)(NSInteger slotIndex)) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];

    if ([presenter shouldShowMainMenuItemForReadOnly:isReadOnly]) {
        UIImage *img = [UIImage systemImageNamed:@"sparkles"];
        UIAction *mainAction = [UIAction actionWithTitle:[presenter writingToolMenuName]
                                                   image:img
                                              identifier:@"wiki.qaq.writenow.action.main"
                                                 handler:^(__kindof UIAction * _Nonnull action) {
            if (handler) { handler(0); }
        }];
        [actions addObject:mainAction];
    }

    NSArray<NSDictionary<NSString *, id> *> *customItems = [presenter customSelectionMenuItemsForReadOnly:isReadOnly];
    for (NSDictionary<NSString *, id> *dict in customItems) {
        NSString *title = dict[@"title"];
        NSString *iconName = dict[@"icon"];
        NSNumber *slotNum = dict[@"slotIndex"];
        if (![title isKindOfClass:[NSString class]] || !title.length) { continue; }
        if (![slotNum isKindOfClass:[NSNumber class]]) { continue; }
        NSInteger slotIndex = [slotNum integerValue];
        UIImage *img = nil;
        if ([iconName isKindOfClass:[NSString class]] && iconName.length) {
            img = [UIImage systemImageNamed:iconName];
        }
        NSString *ident = [NSString stringWithFormat:@"wiki.qaq.writenow.action.slot.%ld", (long)slotIndex];
        UIAction *customAction = [UIAction actionWithTitle:title
                                                     image:img
                                                identifier:ident
                                                   handler:^(__kindof UIAction * _Nonnull action) {
            if (handler) { handler(slotIndex); }
        }];
        [actions addObject:customAction];
    }

    return [actions copy];
}

BOOL WT_MenuItem_IsWritingTool(id input) {
    NSString *currentTitle = WT_MenuItem().title;
    if ([input isKindOfClass:[UIMenu class]]) {
        UIMenu *menu = (UIMenu *)input;
        if ([menu.identifier isEqualToString:WT_CustomSubmenuIdentifier()] ||
            [menu.title isEqualToString:currentTitle]) {
            return YES;
        }
    }
    if ([input isKindOfClass:[UIAction class]]) {
        UIAction *action = (UIAction *)input;
        if ([action.identifier hasPrefix:@"wiki.qaq.writenow."] ||
            [action.title isEqualToString:currentTitle]) {
            return YES;
        }
    }
    if ([input isKindOfClass:[UICommand class]]) {
        UICommand *command = (UICommand *)input;
        NSString *selectorName = NSStringFromSelector(command.action);
        if (WT_SlotIndexFromSelectorName(selectorName) >= 0) {
            return YES;
        }
    }
    return NO;
}

BOOL WT_MenuContainsWriteNow(UIMenu *menu) {
    for (id item in menu.children) {
        if (WT_MenuItem_IsWritingTool(item)) { return YES; }
        if ([item isKindOfClass:[UIMenu class]]) {
            if (WT_MenuContainsWriteNow((UIMenu *)item)) { return YES; }
        }
    }
    return NO;
}

BOOL WT_IsCopyTitle(NSString * _Nullable title) {
    if (![title isKindOfClass:[NSString class]] || !title.length) { return NO; }
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length || trimmed.length > 36) { return NO; }
    NSString *low = trimmed.lowercaseString;
    if (([low containsString:@"link"] || [low containsString:@"liên kết"] || [low containsString:@"url"] || [low containsString:@"address"] || [low containsString:@"địa chỉ"]) &&
        !([low containsString:@"text"] || [low containsString:@"văn bản"] || [low containsString:@"post"] || [low containsString:@"bài"])) {
        return NO;
    }
    if ([low isEqualToString:@"copy"] ||
        [low hasPrefix:@"copy "] ||
        [low containsString:@"sao chép"] ||
        [low isEqualToString:@"chép"] ||
        [low isEqualToString:@"拷贝"] ||
        [low isEqualToString:@"复制"] ||
        [low isEqualToString:@"コピー"] ||
        [low isEqualToString:@"복사"]) {
        return YES;
    }
    return NO;
}

BOOL WT_IsTextMenuTitle(NSString * _Nullable title) {
    if (![title isKindOfClass:[NSString class]] || !title.length) { return NO; }
    NSString *low = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (WT_IsCopyTitle(title)) { return YES; }
    for (NSString *kw in @[@"reply", @"trả lời", @"forward", @"chuyển tiếp", @"translate", @"dịch", @"quote", @"trích dẫn", @"speak", @"đọc"]) {
        if ([low containsString:kw]) { return YES; }
    }
    return NO;
}

NSArray<UIMenuItem *> *WT_BuildExtraMenuItemsForReadOnly(BOOL isReadOnly) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    NSMutableArray<UIMenuItem *> *items = [NSMutableArray array];

    if ([presenter shouldShowMainMenuItemForReadOnly:isReadOnly]) {
        [items addObject:WT_MenuItem()];
    }

    NSArray<NSDictionary<NSString *, id> *> *customItems = [presenter customSelectionMenuItemsForReadOnly:isReadOnly];
    for (NSDictionary<NSString *, id> *dict in customItems) {
        NSString *title = dict[@"title"];
        NSString *selName = dict[@"selector"];
        if (![title isKindOfClass:[NSString class]] || !title.length) { continue; }
        if (![selName isKindOfClass:[NSString class]] || !selName.length) { continue; }
        UIMenuItem *item = [[UIMenuItem alloc] initWithTitle:title action:NSSelectorFromString(selName)];
        if (item) {
            [items addObject:item];
        }
    }
    return [items copy];
}

UIMenuItem * _Nullable WT_FindCopyUIMenuItem(NSArray<UIMenuItem *> * _Nullable items) {
    for (UIMenuItem *item in items) {
        if (![item isKindOfClass:[UIMenuItem class]]) { continue; }
        NSString *selName = NSStringFromSelector(item.action).lowercaseString ?: @"";
        if (WT_IsCopyTitle(item.title) || ([selName containsString:@"copy"] && ![selName containsString:@"link"] && ![selName containsString:@"url"])) {
            return item;
        }
    }
    return nil;
}

BOOL WT_ExtraItemsContainCopyOrTextAction(NSArray<UIMenuItem *> * _Nullable items) {
    if (WT_FindCopyUIMenuItem(items) != nil) { return YES; }
    for (UIMenuItem *item in items) {
        if (![item isKindOfClass:[UIMenuItem class]]) { continue; }
        if (WT_IsTextMenuTitle(item.title)) { return YES; }
    }
    return NO;
}

id WT_FindCopyMenuElement(NSArray *elements) {
    for (id item in elements) {
        if ([item isKindOfClass:[UICommand class]] && ![item isKindOfClass:[UIAction class]]) {
            UICommand *cmd = (UICommand *)item;
            NSString *selName = NSStringFromSelector(cmd.action).lowercaseString ?: @"";
            if ([selName isEqualToString:@"copy:"] || WT_IsCopyTitle(cmd.title) || ([selName containsString:@"copy"] && ![selName containsString:@"link"] && ![selName containsString:@"url"])) {
                return cmd;
            }
        } else if ([item isKindOfClass:[UIAction class]]) {
            UIAction *act = (UIAction *)item;
            NSString *ident = act.identifier.lowercaseString ?: @"";
            if (WT_IsCopyTitle(act.title) || ([ident containsString:@"copy"] && ![ident containsString:@"link"] && ![ident containsString:@"url"])) {
                return act;
            }
        } else if ([item isKindOfClass:[UIMenu class]]) {
            id sub = WT_FindCopyMenuElement([(UIMenu *)item children]);
            if (sub) { return sub; }
        }
    }
    return nil;
}

BOOL WT_MenuLooksLikeTextOrContentMenu(NSArray *elements) {
    if (WT_FindCopyMenuElement(elements) != nil) {
        return YES;
    }
    for (id item in elements) {
        if ([item isKindOfClass:[UIAction class]]) {
            if (WT_IsTextMenuTitle([(UIAction *)item title])) { return YES; }
        } else if ([item isKindOfClass:[UICommand class]]) {
            if (WT_IsTextMenuTitle([(UICommand *)item title])) { return YES; }
        } else if ([item isKindOfClass:[UIMenu class]]) {
            if (WT_MenuLooksLikeTextOrContentMenu([(UIMenu *)item children])) {
                return YES;
            }
        }
    }
    return NO;
}
