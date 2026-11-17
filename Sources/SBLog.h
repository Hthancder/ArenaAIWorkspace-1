// SBLog.h — log ra NSLog VÀ ra file để debug trên máy thật
//
// File: /var/mobile/Library/Logs/SiriBridge.log (tự cắt khi > 300 KB)
// Xem trên máy: Filza → đường dẫn trên, hoặc `cat` qua SSH.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void SBLogMsg(NSString *_Nullable tag, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
void SBLogSetTag(NSString *_Nullable tag);

/// Ghi một mốc rõ ràng (dùng để biết tweak chết ở đâu).
#define SBLog(fmt, ...) SBLogMsg(nil, fmt, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
