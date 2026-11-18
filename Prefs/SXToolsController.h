#import "PSViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Màn hình "Công cụ AI": liệt kê từng công cụ thật mà AI có thể gọi, kèm mô tả
/// và công tắc bật/tắt. Danh sách lấy trực tiếp từ SXToolkit (cùng nguồn với
/// những gì gửi cho model), nên không bao giờ lệch với thực tế chạy trên máy.
@interface SXToolsController : PSViewController
@end

NS_ASSUME_NONNULL_END
