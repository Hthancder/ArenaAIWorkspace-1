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

- (SXProvider)configuredProvider {
	NSString *identifier = [self.specifier propertyForKey:@"sxProvider"];
	return identifier ? SXProviderFromID(identifier) : [SXPrefs shared].provider;
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [NSString stringWithFormat:@"Cấu hình %@", SXProviderName([self configuredProvider])];
}
- (NSArray *)specifiers {
	if (!_specifiers) {
		SXProvider provider = [self configuredProvider];
		NSMutableDictionary *settings = [[SXPrefs shared].settings mutableCopy];
		settings[@"provider"] = SXProviderID(provider);
		NSMutableArray *loaded = nil;
		@try {
			loaded = [self loadSpecifiersFromPlistName:@"ProviderConfig" target:self];
			NSDictionary *keys = @{@"key": SXChatKey(provider, @"Key"), @"model": SXChatKey(provider, @"Model"),
				@"fallback": SXChatKey(provider, @"FallbackModel"), @"base": @"customBase"};
			for (PSSpecifier *specifier in loaded) {
				NSString *field = [specifier propertyForKey:@"sxField"];
				NSString *key = field ? keys[field] : nil;
				if (key) [specifier setProperty:key forKey:@"key"];
				if ([field isEqual:@"model"]) {
					NSString *model = SXChatDefaultModel(provider);
					[specifier setProperty:model.length ? model : @"Nhập mã mô hình" forKey:@"placeholder"];
				}
				if ([specifier.identifier isEqual:@"sx-provider-about"]) {
					NSString *note = provider == SXProviderCustom ? @"Nhập địa chỉ HTTPS gốc của máy chủ tương thích /chat/completions và mô hình máy chủ hỗ trợ. Đổi địa chỉ sẽ xóa khóa cũ." :
						[NSString stringWithFormat:@"SiriX dùng địa chỉ chính thức của %@. Chỉ cần nhập khóa API; có thể đổi mô hình nếu muốn.", SXProviderName(provider)];
					[specifier setProperty:note forKey:@"footerText"];
				}
			}
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"load ProviderConfig: %@", exception.name);
		}
		if (!loaded) {
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Không tải được trang cấu hình. Quay lại và xem log để kiểm tra." forKey:@"footerText"];
			loaded = [NSMutableArray arrayWithObject:group];
		}
		_specifiers = [self sx_visibleSpecifiers:loaded settings:settings];
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
	SXProvider provider = [self configuredProvider];
	NSString *issue = SXChatIssue(prefs.settings, provider);
	if (issue) {
		[self showAlert:@"Cấu hình chưa đủ" message:issue error:NO]; return;
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
							NSString *message = [error.domain isEqual:NSURLErrorDomain] ? (provider == SXProviderCustom ? @"Kiểm tra mạng và địa chỉ API đã nhập." : @"Kiểm tra mạng rồi thử lại.") : error.localizedDescription;
							[self showAlert:@"⚠️ Không kết nối được" message:message error:YES];
						} else {
							NSString *message = [NSString stringWithFormat:@"%@ / %@ — %ld ms", SXProviderName(provider), info[@"model"] ?: @"?", (long)[info[@"ms"] integerValue]];
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
