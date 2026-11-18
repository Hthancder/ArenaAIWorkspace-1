#import <Foundation/Foundation.h>

#define SX_VERSION @"1.1.0"

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

/// A UTF-16 cap that never leaves half of a surrogate pair.
static inline NSString *SXPrefix(NSString *string, NSUInteger limit) {
	if (string.length <= limit) return string;
	if (limit && CFStringIsSurrogateHighCharacter([string characterAtIndex:limit - 1])) limit--;
	return [string substringToIndex:limit];
}
static inline NSString *SXShort(NSString * _Nullable string, NSUInteger maxLength) {
	if (!string) return @"(nil)";
	return string.length <= maxLength ? string : [SXPrefix(string, maxLength) stringByAppendingString:@"…"];
}

NS_ASSUME_NONNULL_END
