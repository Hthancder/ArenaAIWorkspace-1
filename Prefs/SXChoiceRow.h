#import <UIKit/UIKit.h>
#import "PSTableCell.h"

NS_ASSUME_NONNULL_BEGIN

/// Hàng chọn giá trị tự vẽ, CÓ trạng thái nhìn thấy được.
///
/// Vì sao không dùng `PSLinkListCell`/`PSListItemCell` của Preferences:
/// - Cell của Apple hiện "đang chọn" bằng cách tra giá trị trả về của
///   `readPreferenceValue:` trong `validValues` của hàng. Ta từng trả nhãn đã
///   dịch ("Thông minh") nên không khớp `validValues` ("smart") ⇒ ô bên phải
///   rỗng, không ✓, không giá trị — đúng hiện tượng "chọn xong không thấy gì".
/// - Hàng `PSListItemCell` dựng tay chỉ hiện chữ ở ô `value`; trên một số bản
///   iOS 15 hàng do plist tạo còn không được truyền setter nên chạm vào không có
///   phản hồi.
///
/// Cell này tự vẽ: nhãn bên trái, chú thích nhỏ bên dưới, và bên phải là giá trị
/// đang dùng (chế độ `SXChoiceCellModeValue`) hoặc dấu ✓ (chế độ
/// `SXChoiceCellModeOption`). Dùng được cả ở hàng nạp từ plist (`cellClass`) và
/// ở bảng tự dựng (`cellForTable:`).
typedef NS_ENUM(NSInteger, SXChoiceCellMode) {
	/// Hàng ở trang gốc: "Chế độ trả lời        Thông minh (khuyến nghị) ›"
	SXChoiceCellModeValue = 0,
	/// Hàng trong trang chọn: "Thông minh ✓"
	SXChoiceCellModeOption,
};

/// Khoá specifier dùng để truyền trạng thái vào cell.
FOUNDATION_EXPORT NSString *const SXChoiceActiveKey;   // @YES nếu hàng đang được chọn
FOUNDATION_EXPORT NSString *const SXChoiceTrailingKey; // chuỗi hiện ở mép phải
FOUNDATION_EXPORT NSString *const SXChoiceHintKey;     // chú thích nhỏ dưới nhãn
FOUNDATION_EXPORT NSString *const SXChoiceModeKey;     // @(SXChoiceCellMode)

@interface SXChoiceRow : PSTableCell

/// Dequeue (hoặc tạo) cell cho bảng tự dựng. `specifier` mang các khoá ở trên.
+ (instancetype)cellForTable:(UITableView *)tableView specifier:(PSSpecifier *)specifier;

@end

NS_ASSUME_NONNULL_END
