// Kiểm thử phần "dùng chung" của SXPrefs (SXPrefsShared.m) trên macOS.
//
// Lý do tồn tại: bản 1.1.10–1.1.12 văng ngay khi mở trang cấu hình OpenAI vì
// `-headersSummaryForProvider:` được KHAI BÁO trong header và GỌI từ Settings
// nhưng chưa từng được viết. Test này gọi đúng selector đó, nên nếu ai lại quên
// thân hàm thì CI đỏ ngay chứ không tới tay người dùng.
#import <Foundation/Foundation.h>
#import "SXPrefs.h"
#import "SXHeaders.h"
#include <assert.h>
#include <stdio.h>

static NSMutableDictionary<NSString *, id> *gStore;

// Lớp giả của SXPrefs: chỉ giữ đúng phần lưu trữ mà category dùng tới.
@implementation SXPrefs
+ (instancetype)shared {
	static SXPrefs *prefs;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ prefs = [SXPrefs new]; });
	return prefs;
}
- (id)valueFor:(NSString *)key { return gStore[key]; }
+ (void)setValue:(id)value forKey:(NSString *)key { if (value) gStore[key] = value; }
+ (void)setString:(NSString *)value forKey:(NSString *)key { if (value) gStore[key] = value; }
+ (void)setBool:(BOOL)value forKey:(NSString *)key { gStore[key] = @(value); }
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key { gStore[key] = @(value); }
- (void)reload {}
@end

int main(void) {
	@autoreleasepool {
		gStore = [NSMutableDictionary dictionary];

		// --- selector phải tồn tại thật: đúng lỗi đã xảy ra ở 1.1.10–1.1.12
		assert([[SXPrefs shared] respondsToSelector:@selector(headersSummaryForProvider:)]);

		// --- chưa cấu hình header: vẫn trả chuỗi, không nil
		NSString *empty = [[SXPrefs shared] headersSummaryForProvider:SXProviderOpenAI];
		assert([empty isKindOfClass:[NSString class]]);
		assert([empty isEqualToString:SXHeadersSummary(@[])]);

		// --- đã cấu hình: tóm tắt khớp dữ liệu
		NSArray *headers = @[
			@{@"name": @"User-Agent", @"value": @"SiriX", @"enabled": @YES},
			@{@"name": @"x-opencode-client", @"value": @"1", @"enabled": @NO},
		];
		gStore[@"openaiHeaders"] = headers;
		NSString *summary = [[SXPrefs shared] headersSummaryForProvider:SXProviderOpenAI];
		assert([summary isEqualToString:SXHeadersSummary(headers)]);

		// --- hai nhà cung cấp không dùng chung kho
		assert([[[SXPrefs shared] headersSummaryForProvider:SXProviderGemini]
				isEqualToString:SXHeadersSummary(@[])]);

		// --- dữ liệu sai kiểu (plist hỏng) không được làm văng
		gStore[@"openaiHeaders"] = @"không phải mảng";
		NSString *broken = [[SXPrefs shared] headersSummaryForProvider:SXProviderOpenAI];
		assert([broken isKindOfClass:[NSString class]]);

		printf("✓ prefs_shared_test: headersSummaryForProvider luôn trả về chuỗi\n");
	}
	return 0;
}
