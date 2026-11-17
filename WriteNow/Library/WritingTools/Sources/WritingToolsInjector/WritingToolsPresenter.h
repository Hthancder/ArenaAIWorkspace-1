//
//  WritingToolsPresenter.h
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/19.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class WritingToolsPresenter;

@interface WritingToolsPresenter
+ (instancetype)sharedInstance;
- (NSString *)writingToolMenuName;
- (void)presentToolController:(UIResponder *)responder;
- (void)presentToolController:(UIResponder *)responder slotIndex:(NSInteger)slotIndex;
- (BOOL)isReadOnlyEnabled;
- (BOOL)isResponderReadOnly:(UIResponder *)responder;
- (BOOL)canPerformCustomSlot:(NSInteger)slotIndex isReadOnly:(BOOL)isReadOnly;
- (BOOL)shouldShowMainMenuItemForReadOnly:(BOOL)isReadOnly;
- (NSString *)menuPresentationMode;
- (NSArray<NSDictionary<NSString *, id> *> *)customSelectionMenuItemsForReadOnly:(BOOL)isReadOnly;
@end

NS_ASSUME_NONNULL_END
