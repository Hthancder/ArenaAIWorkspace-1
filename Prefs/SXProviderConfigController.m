#import "SXProviderConfigController.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import <UIKit/UIKit.h>

@implementation SXProviderConfigController {
	SXRequest *_probe;
}

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSString *plistName = nil;
		@try {
			plistName = [[self specifier] propertyForKey:@"configPlist"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc configPlist: %@", exception.name);
		}
		if (![plistName isKindOfClass:[NSString class]] || !plistName.length) {
			plistName = @"ProviderOpenAI";
		}
		@try {
			_specifiers = [self loadSpecifiersFromPlistName:plistName target:self];
			SXLogInf(@"pref", @"trang cấu hình %@: %lu specifier",
					 plistName, (unsigned long)_specifiers.count);
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"load %@ EXCEPTION: %@", plistName, exception.name);
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Tải trang cấu hình thất bại — quay lại và xem log nhé."
					   forKey:@"footerText"];
			_specifiers = [NSMutableArray arrayWithObject:group];
		}
	}
	return _specifiers;
}

#pragma mark - Kiểm tra kết nối

- (void)dealloc { [_probe cancel]; }
- (void)sx_testConnection:(id)sender {
	(void)sender;
	[self.view endEditing:YES];
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	if (_probe || self.presentedViewController) return;
	if (prefs.localOnly) {
		[self showAlert:@"SiriX đang không gửi mạng" message:@"Tắt chế độ Chỉ dùng Siri gốc để kiểm tra API." error:NO]; return;
	}
	NSString *plistName = [[self specifier] propertyForKey:@"configPlist"];
	SXProvider provider = [plistName isEqual:@"ProviderGemini"] ? SXProviderGemini : SXProviderOpenAI;
	NSString *key = provider == SXProviderGemini ? prefs.geminiKey : prefs.openaiKey;
	if (!key.length) {
		[self showAlert:@"Chưa có khóa API" message:@"Hãy dán khóa API trước khi kiểm tra." error:NO]; return;
	}
	SXRequest *probe = [[SXRequest alloc] initWithTimeout:12];
	_probe = probe;
	UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Đang kiểm tra…" message:@"Gửi một câu hỏi thử tới API đã cấu hình." preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[progress addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
		(void)action;
		[probe cancel];
		typeof(self) self = weakSelf; if (self && self->_probe == probe) self->_probe = nil;
	}]];
	[self presentViewController:progress animated:YES completion:nil];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[SXLLM performQuestion:@"Ping. Reply with pong." history:@[] tools:@[] executor:nil prefs:prefs provider:provider
			model:nil prompt:@"Connection check." maxTokens:64 request:probe progress:nil completion:^(NSString *answer, NSError *error, NSDictionary *info) {
				dispatch_async(dispatch_get_main_queue(), ^{
					typeof(self) self = weakSelf;
					if (!self || self->_probe != probe) return;
					self->_probe = nil;
					if (self.presentedViewController != progress) return;
					[progress dismissViewControllerAnimated:YES completion:^{
						if (error || !answer.length) {
							NSString *message = [error.domain isEqual:NSURLErrorDomain] ? @"Kiểm tra kết nối mạng và địa chỉ API." : error.localizedDescription;
							[self showAlert:@"⚠️ Không kết nối được" message:message error:YES];
						} else {
							NSString *message = [NSString stringWithFormat:@"%@ / %@ — %ld ms", info[@"provider"] ?: @"?", info[@"model"] ?: @"?", (long)[info[@"ms"] integerValue]];
							[self showAlert:@"✓ Hoạt động" message:message error:NO];
						}
					}];
				});
			}];
	});
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
