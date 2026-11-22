#import "PSViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Màn hình "Ghi nhớ": mọi điều AI đã ghi nhớ bằng công cụ `remember`, kèm
/// ngày, nhãn và nút xoá từng mục / xoá tất cả.
///
/// Vì sao cần: `remember` ghi xuống `/var/mobile/Library/SiriX/memory.plist`
/// nhưng trước bản này không có chỗ nào trong Settings đọc hay xoá dữ liệu đó
/// — AI nhớ được, người dùng thì không thấy và không xoá được khỏi máy.
@interface SXMemoryController : PSViewController
@end

NS_ASSUME_NONNULL_END
