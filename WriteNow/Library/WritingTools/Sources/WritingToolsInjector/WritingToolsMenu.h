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
BOOL WT_IsCopyTitle(NSString * _Nullable title);
BOOL WT_IsTextMenuTitle(NSString * _Nullable title);
id _Nullable WT_FindCopyMenuElement(NSArray *elements);
BOOL WT_MenuLooksLikeTextOrContentMenu(NSArray *elements);
NSArray<UIMenuItem *> *WT_BuildExtraMenuItemsForReadOnly(BOOL isReadOnly);
BOOL WT_ExtraItemsContainCopyOrTextAction(NSArray<UIMenuItem *> * _Nullable items);
UIMenuItem * _Nullable WT_FindCopyUIMenuItem(NSArray<UIMenuItem *> * _Nullable items);

NS_ASSUME_NONNULL_END
