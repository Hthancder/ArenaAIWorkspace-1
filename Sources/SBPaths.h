// SBPaths.h — đường dẫn dùng chung, hoạt động trên cả rootless và roothide
//
// Rootless : tweak nằm ở /var/jb/... , dữ liệu người dùng vẫn ở /var/mobile
// RootHide : jbroot bị random hoá → phải gọi jbroot() của libroothide
//
// Ta dùng đúng 1 API: `jbroot(const char*)` resolve qua dlsym (KHÔNG link
// libroothide) để cùng một binary chạy được ở cả hai môi trường.
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *SBJailbreakRoot(void);        // "/" hoặc "/var/jb" hoặc jbroot thật
FOUNDATION_EXPORT BOOL      SBIsRootHide(void);           // YES nếu đang chạy trên roothide

/// Trả về các đường dẫn ứng viên cho một đường dẫn "logic" (vd /var/mobile/Library/Preferences/x.plist)
/// theo thứ tự ưu tiên: bản roothide → bản rootless → bản gốc.
FOUNDATION_EXPORT NSArray<NSString *> *SBPathCandidates(NSString *logicalPath);

/// Đường dẫn plist cấu hình dùng để GHI (tạo thư mục nếu cần).
FOUNDATION_EXPORT NSString *SBPrimaryPreferencesPath(void);
