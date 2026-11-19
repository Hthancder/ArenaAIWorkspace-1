#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Kiểm tra bản phát hành mới trên GitHub Releases.
///
/// Không tự tải/tự cài: chỉ đọc `releases/latest` (công khai, không cần khoá),
/// so sánh số phiên bản và trả về thông tin để Settings hiện một dòng "Có bản
/// mới 1.2.0 — Mở trang phát hành". Bản phát hành do CI tạo khi commit có
/// `[release]`, nên đây chính là nguồn đúng của "bản mới nhất".
@interface SXUpdate : NSObject

/// Repo công khai chứa bản phát hành.
+ (NSString *)repository;

/// So sánh semver dạng "1.2.3" (bỏ tiền tố `v`, hậu tố `-build.N`).
/// Trả về YES khi `candidate` mới hơn `current`.
+ (BOOL)isVersion:(NSString *)candidate newerThan:(NSString *)current;

/// Gọi đồng bộ (luồng nền). Trả về dict:
///   @{@"current": …, @"latest": …, @"newer": @YES/@NO, @"url": NSURL/NSString, @"name": …}
/// hoặc nil + error (mạng/JSON). Không bao giờ ném exception.
+ (nullable NSDictionary *)checkWithTimeout:(NSTimeInterval)timeout
									  error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
