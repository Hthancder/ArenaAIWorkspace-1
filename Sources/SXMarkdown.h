#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Trình bày Markdown thành chữ đẹp cho bong bóng Siri (iOS 15 — text thuần).
/// Giữ nguyên cấu trúc: tiêu đề, danh sách, code block, link, trích dẫn, bảng.
FOUNDATION_EXPORT NSString *SXMarkdownRender(NSString * _Nullable markdown);

NS_ASSUME_NONNULL_END
