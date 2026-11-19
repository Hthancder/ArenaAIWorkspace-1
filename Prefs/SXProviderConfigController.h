#import "PSListController.h"

/// Trang “Cấu hình <Nhà cung cấp>” — tải plist theo key `configPlist` của specifier gọi nó
/// (ProviderOpenAI / ProviderGemini) + nút Kiểm tra kết nối dùng chung.
@interface SXProviderConfigController : PSListController
/// Bóc BOM / ký tự vô hình / dấu nháy / xuống dòng quanh khoá API đã dán.
/// Dùng chung với màn hình Trò chuyện thử để cùng một quy tắc làm sạch.
+ (NSString *)cleanedKey:(NSString *)raw;
@end
