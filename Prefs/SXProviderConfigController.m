#import "SXProviderConfigController.h"
#import "SXChatTestController.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXUISupport.h"
#import <notify.h>
#import <UIKit/UIKit.h>

@interface SXProviderConfigController ()
@property (nonatomic, copy) NSString *configPlistName;
@property (nonatomic, copy) NSString *testResult;
@property (nonatomic) BOOL testing;
@end

@implementation SXProviderConfigController

#pragma mark - Nhận diện trang

- (NSString *)configPlistName {
	if (!_configPlistName) {
		NSString *name = nil;
		@try {
			name = [[self specifier] propertyForKey:@"configPlist"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc configPlist: %@", exception.reason);
		}
		_configPlistName = ([name isKindOfClass:[NSString class]] && name.length) ? name : @"ProviderOpenAI";
	}
	return _configPlistName;
}

- (SXProvider)provider {
	return [self.configPlistName isEqualToString:@"ProviderGemini"] ? SXProviderGemini : SXProviderOpenAI;
}

- (NSString *)keyName {
	return self.provider == SXProviderGemini ? @"geminiKey" : @"openaiKey";
}

- (NSString *)modelKey {
	return self.provider == SXProviderGemini ? @"geminiModel" : @"openaiModel";
}

- (NSString *)lastTestKey {
	return self.provider == SXProviderGemini ? @"lastTest.gemini" : @"lastTest.openai";
}

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		@try {
			_specifiers = [self loadSpecifiersFromPlistName:self.configPlistName target:self];
			SXLogInf(@"pref", @"trang cấu hình %@: %lu specifier",
					 self.configPlistName, (unsigned long)_specifiers.count);
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"load %@ EXCEPTION: %@ — %@", self.configPlistName,
					 exception.name, exception.reason);
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Không tải được trang cấu hình. Hãy mở log để xem chi tiết."
					  forKey:@"footerText"];
			_specifiers = [NSMutableArray arrayWithObject:group];
		}
	}
	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	@try {
		self.title = [NSString stringWithFormat:@"Cấu hình %@", SXProviderDisplayName(self.provider)];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"title: %@", exception.reason);
	}
}

#pragma mark - Giá trị hiển thị

- (NSString *)currentKey {
	SXPrefs *prefs = [SXPrefs shared];
	return self.provider == SXProviderGemini ? prefs.geminiKey : prefs.openaiKey;
}

- (NSString *)currentModel {
	SXPrefs *prefs = [SXPrefs shared];
	NSString *model = self.provider == SXProviderGemini ? prefs.geminiModel : prefs.openaiModel;
	return model.length ? model : (self.provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini");
}

- (NSString *)testStatusText {
	if (self.testing) return @"⏳ Đang gửi thử…";
	if (self.testResult.length) return self.testResult;
	NSString *stored = [SXPrefs stringForKey:self.lastTestKey];
	return stored.length ? stored : @"Chưa kiểm tra";
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	@try {
		NSString *key = [specifier propertyForKey:@"key"];
		if ([key isEqualToString:@"keyDisplay"]) {
			NSString *live = [self currentKey];
			return live.length ? [SXPrefs maskedKey:live] : @"Chưa đặt";
		}
		if ([key isEqualToString:@"modelDisplay"]) return [self currentModel];
		if ([key isEqualToString:@"endpointDisplay"]) {
			if (self.provider == SXProviderGemini) return @"generativelanguage.googleapis.com";
			NSString *raw = [SXPrefs shared].openaiBase;
			NSString *normalized = [SXPrefs normalizedBaseURL:raw];
			if (normalized.length) return normalized;
			return raw.length ? @"⚠️ địa chỉ không hợp lệ" : @"Mặc định";
		}
		if ([key isEqualToString:@"testStatus"]) return [self testStatusText];
		return [super readPreferenceValue:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"readPreferenceValue EXCEPTION (key=%@): %@ — %@",
				 [specifier propertyForKey:@"key"], exception.name, exception.reason);
		return nil;
	}
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	@try {
		[super setPreferenceValue:value specifier:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"setPreferenceValue EXCEPTION (key=%@): %@ — %@",
				 [specifier propertyForKey:@"key"], exception.name, exception.reason);
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(sx_applyDeferredRefresh)
											   object:nil];
	[self performSelector:@selector(sx_applyDeferredRefresh) withObject:nil afterDelay:0.25];
}

- (void)sx_applyDeferredRefresh {
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	// Kết quả kiểm tra cũ không còn đúng khi vừa đổi khóa/endpoint/mô hình.
	[self sx_invalidateTestResult];
	@try {
		[self reload];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload EXCEPTION: %@", exception.reason);
	}
}

/// Xoá kết quả kiểm tra (cả bản lưu) vì cấu hình vừa thay đổi.
- (void)sx_invalidateTestResult {
	self.testResult = nil;
	[SXPrefs setValue:nil forKey:self.lastTestKey];
}

- (void)sx_refreshTestRow {
	@try {
		[self reloadSpecifierID:@"testStatus" animated:NO];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reloadSpecifierID testStatus: %@", exception.reason);
		@try {
			[self reload];
		} @catch (NSException *ignored) {}
	}
}

#pragma mark - Hành động

- (void)sx_pasteKey:(id)sender {
	(void)sender;
	NSString *clipboard = UIPasteboard.generalPasteboard.string;
	if (![clipboard isKindOfClass:[NSString class]] || !clipboard.length) {
		[SXUI alertOn:self title:@"Bộ nhớ tạm trống" message:@"Hãy sao chép khóa API trước, rồi quay lại đây."];
		return;
	}
	// Khóa dán từ trang web thường kèm xuống dòng/CRLF — lấy dòng đầu tiên.
	NSString *candidate = clipboard;
	NSRange newline = [candidate rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
	if (newline.location != NSNotFound) candidate = [candidate substringToIndex:newline.location];
	NSString *key = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (key.length < 8) {
		[SXUI alertOn:self title:@"Khóa không hợp lệ" message:@"Nội dung trong bộ nhớ tạm quá ngắn để là một khóa API."];
		return;
	}
	[SXPrefs setString:key forKey:self.keyName];
	[self sx_invalidateTestResult];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	@try {
		[self reloadSpecifiers];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reloadSpecifiers sau khi dán khóa: %@", exception.reason);
	}
	[SXUI alertOn:self
			title:@"Đã dán khóa"
		  message:[NSString stringWithFormat:@"Khóa đang dùng: %@", [SXPrefs maskedKey:key]]];
}

- (void)sx_testConnection:(id)sender {
	(void)sender;
	if (self.testing) return;
	// Chốt giá trị đang gõ dở trong ô text trước khi đọc prefs.
	[self.view endEditing:YES];
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];

	NSString *key = self.currentKey;
	key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!key.length) {
		[SXUI alertOn:self title:@"Chưa có khóa API"
			  message:[NSString stringWithFormat:@"Dán khóa %@ trước khi kiểm tra.",
					   SXProviderDisplayName(self.provider)]];
		return;
	}
	if (self.provider == SXProviderOpenAI && ![SXPrefs isValidBaseURL:prefs.openaiBase]) {
		[SXUI alertOn:self title:@"Địa chỉ API không hợp lệ"
			  message:@"Địa chỉ phải bắt đầu bằng https:// (hoặc http:// với máy chủ nội bộ) và có tên miền."];
		return;
	}

	self.testing = YES;
	self.testResult = nil;
	[self sx_refreshTestRow];
	SXLogInf(@"pref", @"kiểm tra kết nối %@ (model=%@)", SXProviderDisplayName(self.provider), self.currentModel);

	__weak typeof(self) weakSelf = self;
	[SXLLM askQuestion:@"Ping. Trả lời đúng một từ: pong"
			   history:@[]
				 tools:@[]
			  executor:nil
			  provider:self.provider
			completion:^(NSString *answer, NSError *error, NSDictionary *info) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.testing = NO;
			NSString *stamp = [SXUI relativeStringForDate:[NSDate date]];
			if (error) {
				NSString *summary = [SXUI truncate:error.localizedDescription limit:70];
				strongSelf.testResult = [NSString stringWithFormat:@"✗ %@", summary];
				SXLogWrn(@"pref", @"kiểm tra kết nối thất bại: %@", error.localizedDescription);
			} else {
				NSString *model = [info[@"model"] isKindOfClass:[NSString class]] ? info[@"model"] : strongSelf.currentModel;
				NSInteger ms = [info[@"ms"] integerValue];
				strongSelf.testResult = [NSString stringWithFormat:@"✓ %@ · %ld ms · %@", model, (long)ms, stamp];
				SXLogInf(@"pref", @"kiểm tra kết nối OK — %@ · %ld ms", model, (long)ms);
			}
			[SXPrefs setString:strongSelf.testResult forKey:strongSelf.lastTestKey];
			[strongSelf sx_refreshTestRow];
			[SXUI tapFeedback];

			NSString *detail = error
				? error.localizedDescription
				: [NSString stringWithFormat:@"%@ · %@\n%ld ms\n\n“%@”",
				   info[@"provider"] ?: SXProviderDisplayName(strongSelf.provider),
				   info[@"model"] ?: strongSelf.currentModel,
				   (long)[info[@"ms"] integerValue],
				   answer ?: @""];
			[SXUI alertOn:strongSelf
					title:error ? @"✗ Kết nối thất bại" : @"✓ Hoạt động"
				  message:detail];
		});
	}];
}

- (void)sx_openChat:(id)sender {
	(void)sender;
	SXChatTestController *chat = [[SXChatTestController alloc] init];
	[self.navigationController pushViewController:chat animated:YES];
}

@end
