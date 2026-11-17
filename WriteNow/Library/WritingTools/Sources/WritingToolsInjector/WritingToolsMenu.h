//
//  WritingToolsMenu.h
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/20.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

NSString *WT_AppleMenuIdentifier(void);
NSString *WT_CustomSubmenuIdentifier(void);
NSInteger WT_SlotIndexFromSelectorName(NSString *name);

UIMenuItem *WT_MenuItem(void);
UICommand *WT_MenuItem_UICommand(void);
NSArray<UICommand *> *WT_BuildCommandsForReadOnly(BOOL isReadOnly);
NSArray<UIMenuElement *> *WT_BuildUIActionsForReadOnly(BOOL isReadOnly, void (^handler)(NSInteger slotIndex));
BOOL WT_MenuItem_IsWritingTool(id input);
BOOL WT_MenuContainsWriteNow(UIMenu *menu);
nullable id WT_FindCopyMenuElement(NSArray *elements);
BOOL WT_MenuLooksLikeTextOrContentMenu(NSArray *elements);

NS_ASSUME_NONNULL_END
