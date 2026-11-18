#import "SXProviderConfigController.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import <UIKit/UIKit.h>

@implementation SXProviderConfigController

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSString *plistName = nil;
		@try {
			plistName = [[self specifier] propertyForKey:@"configPlist"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc configPlist: %@", exception.reason);
		}
		if (![plistName isKindOfClass:[NSString class]] || !plistName.length) {
			plistName = @"ProviderOpenAI";
		}
		@try {
			_specifiers = [self loadSpecifiersFromPlistName:plistName target:self];
			SXLogInf(@"pref", @"trang cấu hình %@: %lu specifier",
					 plistName, (unsigned long)_specifiers.count);
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"load %@ EXCEPTION: %@ — %@", plistName,
					 exception.name, exception.reason);
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Tải trang cấu hình thất bại — quay lại và xem log nhé."
					   forKey:@"footerText"];
			_specifiers = [NSMutableArray arrayWithObject:group];
		}
	}
	return _specifiers;
}

#pragma mark - Kiểm tra kết nối

- (void)sx_testConnection:(id)sender {
	// Chốt giá trị đang gõ dở trong ô text (Preferences ghi khi end editing)
	// rồi mới đọc prefs — kẻo kiểm tra bằng giá trị cũ.
	[self.view endEditing:YES];
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	if (!prefs.activeAPIKey.length) {
		[self showAlert:@"Chưa có khóa API"
				message:@"Hãy dán khóa API trước khi kiểm tra."
				   error:NO];
		return;
	}

	UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Đang kiểm tra…"
																	 message:@"Gửi một câu hỏi thử tới API đã cấu hình."
															  preferredStyle:UIAlertControllerStyleAlert];
	[progress addAction:[UIAlertAction actionWithTitle:@"Hủy"
												 style:UIAlertActionStyleCancel
											   handler:nil]];
	[self presentViewController:progress animated:YES completion:nil];

	__weak SXProviderConfigController *weakSelf = self;
	[SXLLM askQuestion:@"Ping. Trả lời đúng một từ: pong"
			   history:@[]
				 tools:@[]
			   executor:nil
			completion:^(NSString *answer, NSError *error, NSDictionary *info) {
		dispatch_async(dispatch_get_main_queue(), ^{
			SXProviderConfigController *strongSelf = weakSelf;
			if (!strongSelf) return;
			[progress dismissViewControllerAnimated:YES completion:^{
				if (error) {
					[strongSelf showAlert:@"✗ Thất bại" message:error.localizedDescription error:YES];
				} else {
					NSString *message = [NSString stringWithFormat:@"%@ / %@ — %ld ms\n\n“%@”",
										 info[@"provider"] ?: @"?",
										 info[@"model"] ?: @"?",
										 (long)[info[@"ms"] integerValue],
										 answer ?: @""];
					[strongSelf showAlert:@"✓ Hoạt động" message:message error:NO];
				}
			}];
		});
	}];
}

- (void)showAlert:(NSString *)title message:(NSString *)message error:(BOOL)isError {
	if (!self.view.window || self.presentedViewController) return; // không chồng 2 alert
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
	(void)isError;
}

@end
