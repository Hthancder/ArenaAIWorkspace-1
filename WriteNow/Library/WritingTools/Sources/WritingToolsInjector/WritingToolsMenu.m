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
        if ([action.title isEqualToString:currentTitle]) {
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
