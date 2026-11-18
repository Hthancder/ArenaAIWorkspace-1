#import "SXRootListController.h"
#import "SXLogViewController.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#ifndef SX_SCHEME
#define SX_SCHEME "unknown"
#endif

@implementation SXRootListController {
	int _prefsToken;
}

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
		NSString *activeProvider = [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai";
		NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:loaded.count];
		for (PSSpecifier *specifier in loaded) {
			NSString *providerTag = [specifier propertyForKey:@"provider"];
			if ([providerTag isKindOfClass:[NSString class]] && providerTag.length &&
				![providerTag isEqualToString:activeProvider]) {
				continue;
			}
			[filtered addObject:specifier];
		}
		_specifiers = filtered;
	}
	return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"status"]) {
		return [self statusText];
	}
	if ([key isEqualToString:@"packageScheme"]) {
		return @SX_SCHEME;
	}
	return [super readPreferenceValue:specifier];
}

- (NSString *)statusText {
	SXPrefs *prefs = [SXPrefs shared];
	if (!prefs.enabled) return @"Đã tắt";
	if (!prefs.activeAPIKey.length) return @"Chưa có khóa API";
	return @"Sẵn sàng — trả lời bằng AI";
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"SiriX";
	[self buildHeader];

	// Tải lại cài đặt + danh sách (lọc provider) mỗi khi có thay đổi.
	__weak SXRootListController *weakSelf = self;
	notify_register_dispatch("com.sirix.tweak/prefs.changed", &_prefsToken,
							 dispatch_get_main_queue(), ^(int token) {
		[SXPrefs shared];
		[[SXPrefs shared] reload];
		SXRootListController *strongSelf = weakSelf;
		if (strongSelf) {
			strongSelf->_specifiers = nil;
			[strongSelf reloadSpecifiers];
		}
	});
}

- (void)dealloc {
	if (_prefsToken) notify_cancel(_prefsToken);
}

- (void)buildHeader {
	CGFloat width = UIScreen.mainScreen.bounds.size.width;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 124)];

	UIImage *iconImage = [UIImage imageNamed:@"SiriXIcon"
									inBundle:[NSBundle bundleForClass:self.class]
			   compatibleWithTraitCollection:nil];
	UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
	iconView.frame = CGRectMake((width - 68) / 2, 10, 68, 68);
	iconView.contentMode = UIViewContentModeScaleAspectFill;
	iconView.layer.cornerRadius = 15;
	iconView.clipsToBounds = YES;
	iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[header addSubview:iconView];

	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 84, width, 28)];
	titleLabel.text = @"SiriX";
	titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.adjustsFontSizeToFitWidth = YES;
	titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:titleLabel];

	UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 112, width, 16)];
	subtitleLabel.text = @"Trợ lý AI ngay trong giao diện Siri";
	subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
	subtitleLabel.textColor = [UIColor secondaryLabelColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.adjustsFontSizeToFitWidth = YES;
	subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:subtitleLabel];

	((UITableView *)self.view).tableHeaderView = header;
}

#pragma mark - Hành động

- (void)sx_testConnection:(id)sender {
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	if (!prefs.activeAPIKey.length) {
		[self showAlert:@"Chưa có khóa API"
				message:@"Hãy chọn nhà cung cấp và dán khóa API trước khi kiểm tra."
				   error:NO];
		return;
	}

	UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"Đang kiểm tra…"
																	 message:@"Gửi một câu hỏi thử tới API đã cấu hình."
															  preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:progress animated:YES completion:nil];

	__weak SXRootListController *weakSelf = self;
	[SXLLM askQuestion:@"Ping. Trả lời đúng một từ: pong"
			   history:@[]
				 tools:@[]
			   executor:nil
			completion:^(NSString *answer, NSError *error, NSDictionary *info) {
		dispatch_async(dispatch_get_main_queue(), ^{
			SXRootListController *strongSelf = weakSelf;
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

- (void)sx_resetHistory:(id)sender {
	notify_post("com.sirix.tweak/resetHistory");
	[self showAlert:@"Đã xóa lịch sử hội thoại"
			message:@"Các câu hỏi/ trả lời trước đó đã được xoá khỏi bộ nhớ của SiriX."
			   error:NO];
}

- (void)sx_respring:(id)sender {
	notify_post("com.sirix.respring");
}

- (void)showAlert:(NSString *)title message:(NSString *)message error:(BOOL)isError {
	if (!self.view.window) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
	(void)isError;
}

@end
