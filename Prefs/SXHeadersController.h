#import "PSViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Màn hình "Header tuỳ chỉnh" của một nhà cung cấp: thêm / sửa / bật-tắt / xoá
/// từng header, kèm gợi ý cho OpenRouter, Azure, gateway nội bộ.
///
/// Nhận `headersProvider` ("openai" | "gemini") từ specifier gọi nó. Dữ liệu
/// đọc/ghi qua `SXPrefs` + `SXHeaders`, đúng bằng bộ header `SXLLM` sẽ gửi.
@interface SXHeadersController : PSViewController
@end

NS_ASSUME_NONNULL_END
