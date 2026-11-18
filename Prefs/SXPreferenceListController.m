#import "SXPreferenceListController.h"
#import "PSSpecifier.h"
#import "SXConfigIO.h"
#import "SXPrefs.h"
#import <notify.h>

@implementation SXPreferenceListController {
	NSDictionary *_renderedState;
}
- (NSMutableArray *)sx_visibleSpecifiers:(NSArray *)loaded settings:(NSDictionary *)settings {
	_renderedState = SXConfigPresentationState(settings);
	NSMutableArray *visible = [NSMutableArray array];
	for (PSSpecifier *specifier in loaded) {
		if (SXConfigShowsRule([specifier propertyForKey:@"sxRule"], settings)) [visible addObject:specifier];
	}
	return visible;
}
- (void)sx_refreshLayout {
	if (_specifiers && _renderedState && ![_renderedState isEqual:SXConfigPresentationState([SXPrefs shared].settings)]) [self reloadSpecifiers];
}
- (void)viewWillAppear:(BOOL)animated {
	[[SXPrefs shared] reload];
	[super viewWillAppear:animated];
	[self sx_refreshLayout];
	[self.table reloadData];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	NSDictionary *settings = [SXPrefs shared].settings;
	if ([key isEqual:@"timeoutAction"]) return SXEffectiveTimeoutAction(settings);
	id value = key ? settings[key] : nil;
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
		BOOL url = [key hasSuffix:@"Base"] || [key hasSuffix:@"BaseUrl"];
		NSString *message = url ? @"Địa chỉ API phải là HTTPS, không kèm thông tin xác thực hay tham số URL." : @"Giá trị không hợp lệ. Kiểm tra lại định dạng và thử lại.";
		[self sx_showValidationMessage:message];
		return;
	}
	[[SXPrefs shared] reload];
	NSDictionary *plan = SXConfigChangePlan([SXPrefs shared].settings, @{key: normalized});
	NSDictionary *edits = plan[@"set"];
	NSArray *remove = plan[@"remove"];
	if (!edits.count && !remove.count) return;
	if (![SXPrefs writeValues:edits removing:remove]) {
		[self reloadSpecifier:specifier animated:NO];
		[self sx_showValidationMessage:@"Không lưu được cài đặt."]; return;
	}
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	// Let Preferences finish saving or closing a picker before rebuilding rows.
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		typeof(self) self = weakSelf;
		if (!self.viewIfLoaded.window || (self.navigationController && self.navigationController.topViewController != self)) return;
		if (remove.count) {
			[self reloadSpecifiers];
			[self sx_showValidationMessage:@"Đã xóa khóa cũ để không gửi sang địa chỉ mới. Hãy nhập khóa phù hợp nếu máy chủ yêu cầu."];
		} else [self sx_refreshLayout];
	});
}
- (void)sx_showValidationMessage:(NSString *)message {
	if (!self.view.window || self.presentedViewController) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cấu hình SiriX" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end
