// SBPrefsUI.h — bộ view dùng lại cho bảng cấu hình SiriBridge
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Theme

@interface SBTheme : NSObject
+ (UIColor *)accent;
+ (UIColor *)accentSoft;
+ (UIColor *)bg;
+ (UIColor *)card;
+ (UIColor *)cardAlt;
+ (UIColor *)sep;
+ (UIColor *)label;
+ (UIColor *)secondaryLabel;
+ (UIColor *)success;
+ (UIColor *)warning;
+ (UIFont *)titleFont:(CGFloat)size;
+ (UIFont *)bodyFont:(CGFloat)size;
+ (UIFont *)monoFont:(CGFloat)size;
@end

#pragma mark - Store

/// Ghi/đọc cấu hình vào domain dùng chung + phát darwin notification (debounce).
@interface SBSettingsStore : NSObject
+ (instancetype)shared;
- (BOOL)boolForKey:(NSString *)key def:(BOOL)def;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key def:(nullable NSString *)def;
- (void)setString:(nullable NSString *)value forKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key def:(double)def;
- (void)setDouble:(double)value forKey:(NSString *)key;
- (NSInteger)intForKey:(NSString *)key def:(NSInteger)def;
- (void)setInt:(NSInteger)value forKey:(NSString *)key;
- (void)postChanged;
@end

#pragma mark - Card

@interface SBCardView : UIView
@property (nonatomic, readonly) UIStackView *stack;
- (void)addArrangedSubview:(UIView *)view;
- (void)addSeparator;
- (void)addPaddedView:(UIView *)view;
@end

#pragma mark - Row

typedef NS_ENUM(NSInteger, SBRowKind) {
    SBRowKindSwitch,
    SBRowKindText,
    SBRowKindLongText,
    SBRowKindSlider,
    SBRowKindSegment,
    SBRowKindChoice,
    SBRowKindAction,
    SBRowKindInfo,
};

@interface SBRowView : UIView

@property (nonatomic, copy, nullable) NSString *key;
@property (nonatomic, copy, nullable) void (^onChange)(id _Nullable value);
@property (nonatomic, copy, nullable) NSString *dependsOnKey;   // ẩn/hiện theo switch khác
@property (nonatomic, assign) BOOL dependsOnValue;
@property (nonatomic, assign, readonly) SBRowKind kind;

// Switch
+ (instancetype)switchRow:(NSString *)title
                 subtitle:(nullable NSString *)subtitle
                      key:(NSString *)key
                      def:(BOOL)def;

// Một dòng text
+ (instancetype)textRow:(NSString *)title
               subtitle:(nullable NSString *)subtitle
                    key:(NSString *)key
                    def:(nullable NSString *)def
            placeholder:(nullable NSString *)placeholder
               keyboard:(UIKeyboardType)keyboard
               isSecret:(BOOL)isSecret;

// Text nhiều dòng (mở editor toàn màn hình)
+ (instancetype)longTextRow:(NSString *)title
                   subtitle:(nullable NSString *)subtitle
                        key:(NSString *)key
                        def:(nullable NSString *)def
                placeholder:(nullable NSString *)placeholder;

// Slider
+ (instancetype)sliderRow:(NSString *)title
                     key:(NSString *)key
                     def:(double)def
                     min:(double)mn
                     max:(double)mx
                  format:(nullable NSString *(^)(double))format;

// Segmented
+ (instancetype)segmentRow:(NSString *)title
                       key:(NSString *)key
                       def:(NSInteger)def
                    titles:(NSArray<NSString *> *)titles;

// Chọn 1 giá trị trong danh sách (action sheet)
+ (instancetype)choiceRow:(NSString *)title
                 subtitle:(nullable NSString *)subtitle
                      key:(NSString *)key
                      def:(nullable NSString *)def
                  choices:(NSArray<NSDictionary *> *)choices;   // @{@"value":id, @"title":NSString, @"detail":NSString?}

// Nút hành động
+ (instancetype)actionRow:(NSString *)title
                 subtitle:(nullable NSString *)subtitle
                    color:(nullable UIColor *)color
                   action:(void (^)(void))action;

// Dòng thông tin tĩnh
+ (instancetype)infoRow:(NSString *)title subtitle:(nullable NSString *)subtitle;

- (void)refreshValue;
- (void)setEnabled:(BOOL)enabled;
@end

#pragma mark - Editor

@interface SBTextEditorController : UIViewController
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic, copy, nullable) NSString *hint;
@property (nonatomic, assign) BOOL monospaced;
@property (nonatomic, copy, nullable) void (^onDone)(NSString *text);
- (instancetype)initWithTitle:(NSString *)title;
@end

#pragma mark - List picker

@interface SBPickerController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                      choices:(NSArray<NSDictionary *> *)choices
                   selectedID:(nullable NSString *)selectedID
                     onSelect:(void (^)(NSString *identifier))onSelect;
@end

NS_ASSUME_NONNULL_END
