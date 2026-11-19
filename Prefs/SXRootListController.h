#import "PSListController.h"

@interface SXRootListController : PSListController
@end

/// Nạp một plist cài đặt với bundle dự phòng. Trên roothide, `NSBundle` mặc
/// định của Preferences có thể trỏ sai chỗ nên `loadSpecifiersFromPlistName:`
/// trả rỗng dù plist có trên máy — hàm này thử lại với bundle tường minh.
/// Trả về mảng rỗng (không nil) khi không nạp được để nơi gọi tự hiện lý do.
FOUNDATION_EXPORT NSMutableArray *SXLoadSpecifiers(PSListController *controller,
												   Class aClass,
												   NSString *plistName);
