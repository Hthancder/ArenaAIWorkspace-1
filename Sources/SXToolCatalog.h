#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Đăng ký toàn bộ công cụ có sẵn vào SXToolkit. Idempotent — gọi được nhiều lần.
FOUNDATION_EXPORT void SXInstallBuiltinTools(void);

/// Ghi chú lâu dài mà công cụ `remember` tạo ra (`/var/mobile/Library/SiriX/memory.plist`).
/// Màn Cài đặt → Ghi nhớ dùng để xem/xoá; trước đây AI ghi được mà người dùng
/// không có cách nào đọc hay xoá khỏi máy (dữ liệu riêng tư bị "kẹt" lại).
@interface SXMemoryNote : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *tags;
@property (nonatomic, strong, nullable) NSDate *date;
@end

@interface SXMemory : NSObject
+ (instancetype)shared;
/// Mới nhất ở cuối mảng.
- (NSArray<SXMemoryNote *> *)notes;
/// Trần số ghi chú đang giữ (mới nhất được giữ lại khi vượt trần).
+ (NSUInteger)capacity;
- (BOOL)removeNoteWithIdentifier:(NSString *)identifier;
/// Xoá mọi ghi chú; trả về số đã xoá.
- (NSUInteger)removeAllNotes;
@end

NS_ASSUME_NONNULL_END
