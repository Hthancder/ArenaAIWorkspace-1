// SBHook.h — hook bằng objc runtime thuần, KHÔNG dùng Logos/MSHookMessageEx
//
// Vì sao: dylib build bằng zig+Theos liên kết `_MSHookMessageEx` ở dạng
// undefined → dyld phải resolve lúc load. Nếu process bị inject không có
// symbol đó (hoặc substrate nạp sau), quá trình load chết → SpringBoard/Siri
// sập → safe mode. Ở đây ta chỉ dùng API công khai của libobjc, không có
// undefined symbol nào ngoài framework hệ thống.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// Trả về IMP gốc của method (NULL nếu không hook được).
typedef IMP _Nullable (*SBHookFn)(Class cls, SEL sel, IMP replacement);

/// Hook một instance method. `replacement` phải là IMP của một method C/ObjC.
/// Trả về IMP gốc để gọi lại, hoặc NULL nếu class/method không tồn tại.
IMP _Nullable SBHookInstanceMethod(Class cls, SEL sel, IMP replacement);

/// Lấy IMP gốc đã lưu cho (cls, sel) — dùng trong thân hook.
IMP _Nullable SBOriginalIMP(Class cls, SEL sel);

/// Gọi IMP gốc nếu có.
BOOL SBHasHook(Class cls, SEL sel);

/// setValue:forKey: không bao giờ ném. Trả NO nếu key không hợp lệ.
BOOL SBSetSafe(id obj, NSString *key, id _Nullable value);

NS_ASSUME_NONNULL_END
