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

UIMenuItem *WT_MenuItem(void) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    return [[UIMenuItem alloc] initWithTitle:presenter.writingToolMenuName
                                      action:NSSelectorFromString(@kWritingToolSelectorName)];
}

UICommand *WT_MenuItem_UICommand(void) {
    WritingToolsPresenter *presenter = [WritingToolsPresenter sharedInstance];
    return [UICommand commandWithTitle:presenter.writingToolMenuName
                                 image:nil
                                action:NSSelectorFromString(@kWritingToolSelectorName)
                          propertyList:nil];
}

BOOL WT_MenuItem_IsWritingTool(id input) {
    NSString *currentTitle = WT_MenuItem().title;
    if ([input isKindOfClass:[UIMenu class]]) {
        UIMenu *menu = (UIMenu *)input;
        if ([menu.title isEqualToString:currentTitle]) {
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
        if ([selectorName isEqualToString:@kWritingToolSelectorName]) {
            return YES;
        }
    }
    return NO;
}
