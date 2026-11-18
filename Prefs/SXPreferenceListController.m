#import "SXPreferenceListController.h"
#import "PSSpecifier.h"
#import "SXConfigIO.h"
#import "SXPrefs.h"
#import <notify.h>

@implementation SXPreferenceListController
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	id value = key ? [SXPrefs shared].settings[key] : nil;
	return value ?: [super readPreferenceValue:specifier];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	id sample = key ? SXConfigDefaults()[key] : nil;
	if (!sample) { [super setPreferenceValue:value specifier:specifier]; return; }
	if (CFGetTypeID((__bridge CFTypeRef)sample) == CFBooleanGetTypeID() && [value isKindOfClass:NSNumber.class]) value = @([value boolValue]);
	id normalized = SXConfigValue(key, value);
	if (!normalized) {
		[self reloadSpecifier:specifier animated:NO];
		[self sx_showValidationMessage:@"Giá trị không hợp lệ. Địa chỉ API phải là HTTPS, không kèm thông tin xác thực hay tham số URL."];
		return;
	}
	NSDictionary *old = [SXPrefs shared].settings;
	if ([old[key] isEqual:normalized]) return;
	NSDictionary *origin = @{@"openaiBase": @"openaiKey", @"sttBaseUrl": @"sttApiKey", @"sttSource": @"sttApiKey", @"ttsBaseUrl": @"ttsApiKey", @"ttsSource": @"ttsApiKey"};
	NSString *secret = origin[key];
	// Clear the bound credential before allowing a different endpoint/source.
	NSMutableDictionary *values = [@{key: normalized} mutableCopy];
	BOOL clear = secret && [old[secret] length];
	if (secret) values[secret] = @"";
	if ([key isEqual:@"ttsSource"]) values[@"ttsVoice"] = @"";
	if (![SXPrefs writeValues:values removing:@[]]) { [self sx_showValidationMessage:@"Không lưu được cài đặt."]; return; }
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	if (clear) {
		[self reloadSpecifiers];
		[self sx_showValidationMessage:@"Khóa cũ đã được xóa để không gửi sang địa chỉ/nguồn mới. Hãy nhập khóa phù hợp."];
	}
}
- (void)sx_showValidationMessage:(NSString *)message {
	if (!self.view.window || self.presentedViewController) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cấu hình SiriX" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end
