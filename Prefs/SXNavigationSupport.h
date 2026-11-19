#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Một chỗ duy nhất xử lý chuyện "trang con không có nút quay lại".
///
/// Settings của iOS dựng thanh điều hướng cho controller con theo cách riêng
/// (không phải UINavigationController thường). Với các trang con dựng bằng
/// UITableView thủ công, nút Back có thể biến mất — người dùng kẹt trong màn
/// hình. Hàm này:
///   1. đặt tiêu đề nút quay lại theo tên trang trước (nếu hệ thống chưa có);
///   2. nếu vẫn không có nút trái nào thì tự thêm nút "Quay lại" gọi
///      `dismissViewControllerAnimated:` / `popViewControllerAnimated:`
///      (selector `sx_goBack:` khai báo ở `UIViewController+SXBack.h`).
FOUNDATION_EXPORT void SXEnsureBackButton(UIViewController *controller, NSString * _Nullable title);

NS_ASSUME_NONNULL_END
