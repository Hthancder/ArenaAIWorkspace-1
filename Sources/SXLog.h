#import <Foundation/Foundation.h>

#define SX_VERSION @"1.1.6"

typedef NS_ENUM(NSInteger, SXLogLevel) {
	SXLogLevelDebug = 0,
	SXLogLevelInfo,
	SXLogLevelWarn,
	SXLogLevelError,
};

NS_ASSUME_NONNULL_BEGIN

/// Đường dẫn log cố định — nằm ngoài /var/jb nên dùng được trên cả rootless lẫn roothide.
FOUNDATION_EXPORT NSString *SXLogFilePath(void);

/// Mở file log (xoay vòng khi > 512 KB) + banner khởi động. Gọi một lần mỗi process.
FOUNDATION_EXPORT void SXLogInit(void);

FOUNDATION_EXPORT void SXLogSetVerbose(BOOL verbose);

FOUNDATION_EXPORT void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) NS_FORMAT_FUNCTION(3, 4);

/// "sk-…abcd (51 ký tự)" — không bao giờ ghi khóa API đầy đủ vào log.
FOUNDATION_EXPORT NSString *SXRedactKey(NSString * _Nullable key);

#define SXLogDbg(cat, ...) SXLogWrite(SXLogLevelDebug, (cat), __VA_ARGS__)
#define SXLogInf(cat, ...) SXLogWrite(SXLogLevelInfo, (cat), __VA_ARGS__)
#define SXLogWrn(cat, ...) SXLogWrite(SXLogLevelWarn, (cat), __VA_ARGS__)
#define SXLogErr(cat, ...) SXLogWrite(SXLogLevelError, (cat), __VA_ARGS__)

/// Cắt chuỗi cho log — format precision trên '@' là không an toàn, phải cắt trước.
static inline NSString *SXShort(NSString * _Nullable string, NSUInteger maxLength) {
	if (!string) return @"(nil)";
	return string.length <= maxLength ? string : [[string substringToIndex:maxLength] stringByAppendingString:@"…"];
}

NS_ASSUME_NONNULL_END
