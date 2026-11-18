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

#pragma mark - Chẩn đoán exception

static NSUncaughtExceptionHandler *SXPrevExceptionHandler = NULL;

static void SXExceptionHandler(NSException *exception) {
	SXLogErr(@"pref", @"EXCEPTION không bắt được: %@ — %@ | %@",
			 exception.name, exception.reason,
			 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
	if (SXPrevExceptionHandler) SXPrevExceptionHandler(exception);
}

@implementation SXRootListController {
	int _prefsToken;
}

/// Chạy ngay khi bundle được nạp — mốc sớm nhất để chẩn đoán crash khi mở Settings.
+ (void)load {
	SXLogInit();
	SXPrevExceptionHandler = NSGetUncaughtExceptionHandler();
	NSSetUncaughtExceptionHandler(&SXExceptionHandler);
	SXLogInf(@"pref", @"bundle SiriXPreferences NẠP THÀNH CÔNG (process=%@)",
			 NSProcessInfo.processInfo.processName);
}

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		SXLogInf(@"pref", @"bắt đầu tạo bảng cài đặt…");
		NSMutableArray *loaded = nil;
		@try {
			loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"loadSpecifiers EXCEPTION: %@ — %@ | %@",
					 exception.name, exception.reason,
					 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
			loaded = nil;
		}
		if (!loaded) {
			// Bảng dự phòng tối giản — Settings không được crash.
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Tải bảng cài đặt thất bại. Hãy gửi log tại "
							  @"/var/mobile/Library/Logs/SiriX.log để mình sửa."
					   forKey:@"footerText"];
			loaded = [NSMutableArray arrayWithObject:group];
		}

		NSString *activeProvider = [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai";
		NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:loaded.count];
		for (PSSpecifier *specifier in loaded) {
			NSString *providerTag = nil;
			@try {
				providerTag = [specifier propertyForKey:@"provider"];
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"propertyForKey EXCEPTION: %@", exception.reason);
			}
			if ([providerTag isKindOfClass:[NSString class]] && providerTag.length &&
				![providerTag isEqualToString:activeProvider]) {
				continue;
			}
			[filtered addObject:specifier];
		}
		_specifiers = filtered;
		SXLogInf(@"pref", @"bảng cài đặt sẵn sàng: %lu/%lu specifier (provider=%@)",
				 (unsigned long)filtered.count, (unsigned long)loaded.count, activeProvider);
	}
	return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	@try {
		NSString *key = [specifier propertyForKey:@"key"];
		if ([key isEqualToString:@"status"]) return [self statusText];
		if ([key isEqualToString:@"packageScheme"]) return @SX_SCHEME;
		return [super readPreferenceValue:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"readPreferenceValue EXCEPTION (key=%@): %@ — %@",
				 [specifier propertyForKey:@"key"], exception.name, exception.reason);
		return nil;
	}
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
	SXLogInf(@"pref", @"viewDidLoad — start");
	self.title = @"SiriX";

	@try {
		[self buildHeader];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"buildHeader EXCEPTION: %@ — %@", exception.name, exception.reason);
	}

	// Tải lại cài đặt + danh sách (lọc provider) mỗi khi có thay đổi.
	__weak SXRootListController *weakSelf = self;
	notify_register_dispatch("com.sirix.tweak/prefs.changed", &_prefsToken,
							 dispatch_get_main_queue(), ^(int token) {
		[[SXPrefs shared] reload];
		SXRootListController *strongSelf = weakSelf;
		if (strongSelf) {
			@try {
				strongSelf->_specifiers = nil;
				[strongSelf reloadSpecifiers];
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"reloadSpecifiers EXCEPTION: %@", exception.reason);
			}
		}
	});
	SXLogInf(@"pref", @"viewDidLoad — xong");
}

- (void)dealloc {
	if (_prefsToken) notify_cancel(_prefsToken);
}

- (void)buildHeader {
	// Tìm UITableView: có thể là self.view hoặc một trong các subview (iOS 15).
	UITableView *table = nil;
	if ([self.view isKindOfClass:[UITableView class]]) {
		table = (UITableView *)self.view;
	} else {
		for (UIView *subview in self.view.subviews) {
			if ([subview isKindOfClass:[UITableView class]]) {
				table = (UITableView *)subview;
				break;
			}
		}
	}
	if (!table) {
		NSMutableArray<NSString *> *subviewClasses = [NSMutableArray array];
		for (UIView *subview in self.view.subviews) {
			[subviewClasses addObject:NSStringFromClass(subview.class)];
		}
		SXLogWrn(@"pref", @"không tìm thấy UITableView (view=%@, subviews=%@) — bỏ header",
				 NSStringFromClass(self.view.class),
				 [subviewClasses componentsJoinedByString:@","]);
		return;
	}

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

	table.tableHeaderView = header;
	SXLogInf(@"pref", @"header cài đặt đã gắn (icon=%d, table=%@)", iconImage != nil,
			 NSStringFromClass([table class]));
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
			message:@"Các câu hỏi/trả lời trước đó đã được xoá khỏi bộ nhớ của SiriX."
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
