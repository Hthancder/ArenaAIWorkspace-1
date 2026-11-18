#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Đăng ký toàn bộ công cụ có sẵn vào SXToolkit. Idempotent — gọi được nhiều lần.
FOUNDATION_EXPORT void SXInstallBuiltinTools(void);

NS_ASSUME_NONNULL_END
