#import "PSListController.h"
#import "SXPrefs.h"

NS_ASSUME_NONNULL_BEGIN

/// Bộ chọn giao thức API của nhánh OpenAI (Tự dò / Responses / Chat completions).
///
/// Trước đây hàng này là `PSListItemsController` — controller của Apple chỉ đọc
/// `values`/`titles` từ specifier. Trong trang cấu hình được nạp bằng
/// `loadSpecifiersFromPlistName:` thì các key đó không tới được cell theo cách
/// nó mong đợi, và đây là trang duy nhất trong SiriX dùng nó. Tự dựng lấy ba
/// hàng giống hệt bộ chọn số ở trang gốc: không phụ thuộc hành vi riêng của
/// Apple, và giữ nguyên nút Back của hệ thống.
@interface SXAPIChoiceController : PSListController
@end

NS_ASSUME_NONNULL_END
