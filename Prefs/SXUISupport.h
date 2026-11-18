#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Bộ dựng giao diện dùng chung cho toàn bộ Settings của SiriX.
/// Mục tiêu: mọi màn hình cùng một ngôn ngữ thị giác (màu, pill trạng thái,
/// empty state, alert, định dạng ngày) — không màn hình nào tự vẽ kiểu riêng.
@interface SXUI : NSObject

+ (UIColor *)accentColor;
+ (UIColor *)successColor;
+ (UIColor *)warningColor;
+ (UIColor *)dangerColor;
+ (UIColor *)cardColor;

/// Màu theo trạng thái: "Sẵn sàng" xanh, "Thiếu khóa API" vàng, "Đã tắt" xám.
+ (UIColor *)colorForStatusText:(nullable NSString *)text;

/// Pill bo tròn: chấm màu + chữ. Tự co theo nội dung, dùng được trong header.
+ (UIView *)statusPillWithText:(NSString *)text color:(UIColor *)color;

/// Nhãn ghi chú nhiều dòng (dùng làm footer tuỳ biến / mô tả dưới tiêu đề).
+ (UILabel *)footnoteLabel:(NSString *)text;

/// Khung rỗng: SF Symbol + tiêu đề + mô tả. Gán cho `table.backgroundView`.
+ (UIView *)emptyStateWithSymbol:(NSString *)symbol
						   title:(NSString *)title
						 message:(NSString *)message;

/// Alert một nút OK.
+ (void)alertOn:(UIViewController *)controller
		  title:(NSString *)title
		message:(nullable NSString *)message;

/// Alert xác nhận hành động phá huỷ (xóa, khôi phục mặc định…).
+ (void)confirmOn:(UIViewController *)controller
			title:(NSString *)title
		  message:(nullable NSString *)message
	  confirmText:(NSString *)confirmText
		   action:(void (^)(void))action;

/// Rung nhẹ khi hoàn tất một hành động.
+ (void)tapFeedback;

/// "Hôm nay 14:05" / "Hôm qua 09:12" / "12/03 08:30" / "" nếu nil.
+ (NSString *)relativeStringForDate:(nullable NSDate *)date;

/// Cắt chuỗi theo giới hạn ký tự, thêm "…" — an toàn cho nhãn một dòng.
+ (NSString *)truncate:(nullable NSString *)text limit:(NSUInteger)limit;

/// "1 234" — đọc số liệu dễ hơn trong thống kê.
+ (NSString *)groupedNumber:(NSInteger)value;

@end

NS_ASSUME_NONNULL_END
