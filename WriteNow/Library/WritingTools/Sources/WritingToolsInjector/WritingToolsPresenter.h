//
//  WritingToolsPresenter.h
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/16.
//

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface WritingToolsPresenter : NSObject

@property (nonatomic, copy, readonly) NSString *writingToolMenuName;

+ (instancetype)sharedInstance;

- (BOOL)isReadOnlyEnabled;
- (BOOL)isResponderReadOnly:(UIResponder *)responder;
- (BOOL)canPerformCustomSlot:(NSInteger)slotIndex isReadOnly:(BOOL)isReadOnly;
- (BOOL)shouldShowMainMenuItemForReadOnly:(BOOL)isReadOnly;
- (NSString *)menuPresentationMode;
- (NSArray<NSDictionary<NSString *, id> *> *)customSelectionMenuItemsForReadOnly:(BOOL)isReadOnly;

- (BOOL)shouldInjectIntoContextMenus;
- (BOOL)shouldUnlockBlockedSelection;
- (BOOL)hasExtractableTextNearView:(nullable UIView *)view windowPoint:(CGPoint)windowPoint;

- (void)attachScreenPickerToWindow:(UIWindow *)window;
- (void)presentFromUniversalMenuTarget:(nullable UIView *)targetView
                           windowPoint:(CGPoint)windowPoint
                    fallbackCopyAction:(nullable id)copyAction
                             slotIndex:(NSInteger)slotIndex;
- (void)presentFromRestrictedMenuTarget:(nullable UIView *)targetView
                     fallbackCopyAction:(nullable id)copyAction
                              slotIndex:(NSInteger)slotIndex;
- (void)presentFromContextMenuView:(nullable UIView *)view
                       windowPoint:(CGPoint)windowPoint
                         slotIndex:(NSInteger)slotIndex
                fallbackCopyAction:(nullable id)copyAction;
- (void)attachCopySheetAccessoryToPresentedVC:(UIViewController *)presentedVC
                                   targetView:(nullable UIView *)targetView
                                  windowPoint:(CGPoint)windowPoint
                                     copyView:(nullable UIView *)copyView;
- (void)attachCopySheetAccessoryToWindow:(UIWindow *)window
                              targetView:(nullable UIView *)targetView
                             windowPoint:(CGPoint)windowPoint
                                copyView:(nullable UIView *)copyView;

- (void)presentToolController:(UIResponder *)responder;
- (void)presentToolController:(UIResponder *)responder slotIndex:(NSInteger)slotIndex;

@end

NS_ASSUME_NONNULL_END
