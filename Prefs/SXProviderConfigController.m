#import "SXPrefs.h"
#import "SXProviderConfigController.h"
#import "SXChatTestController.h"
#import "SXHeadersController.h"
#import "SXModelPickerController.h"
#import "SXAPIChoiceController.h"
#import "PSSpecifier.h"
#import "PSTableCell.h"
#import "SXLog.h"
#import "SXLLM.h"
#import "SXUISupport.h"
#import <notify.h>
#import <UIKit/UIKit.h>

/// Trang cấu hình một nhà cung cấp.
///
/// Bài học từ hai bản trước: mọi lần gõ một ký tự lại `reload` cả bảng thì bàn
/// phím bị thu, con trỏ nhảy về đầu và dòng tóm tắt cũng nháy. Ở bản này
/// - ô nhập ghi thẳng xuống prefs (không reload);
/// - chỉ dòng tóm tắt (“Khóa đang dùng”, “Đang gửi”, “Đang dùng”) được làm mới,
///   bằng cách cập nhật chữ tại chỗ, không dựng lại cell;
/// - “Kiểm tra kết nối” thu bàn phím một lần, chạy ping và cập nhật đúng một dòng.
@interface SXProviderConfigController ()
@property (nonatomic, copy) NSString *configPlistName;
@property (nonatomic, copy) NSString *headerSignature;
@property (nonatomic, copy) NSString *testResult;
@property (nonatomic) BOOL testing;
- (NSString *)fallbackModelKey;
@end

/// Đuôi đường dẫn tương ứng giao thức đang chọn — một nơi duy nhất để mọi
/// dòng tóm tắt hiển thị giống nhau và không lặp lại ba ngôi lồng nhau.
static NSString *SXAPIPathSuffix(SXOpenAIApi api) {
	if (api == SXOpenAIApiResponses) return @"/responses";
	if (api == SXOpenAIApiChat) return @"/chat/completions";
	return @" (tự dò)";
}

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

- (NSString *)keyName { return self.provider == SXProviderGemini ? @"geminiKey" : @"openaiKey"; }
- (NSString *)modelKey { return self.provider == SXProviderGemini ? @"geminiModel" : @"openaiModel"; }
- (NSString *)fallbackModelKey { return self.provider == SXProviderGemini ? @"geminiFallbackModel" : @"openaiFallbackModel"; }
- (NSString *)baseKey { return self.provider == SXProviderGemini ? nil : @"openaiBase"; }
- (NSString *)lastTestKey {
	return self.provider == SXProviderGemini ? @"lastTest.gemini" : @"lastTest.openai";
}

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		@try {
			_specifiers = [[self loadSpecifiersFromPlistName:self.configPlistName target:self] mutableCopy];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"load %@ EXCEPTION: %@ — %@", self.configPlistName,
					 exception.name, exception.reason);
			_specifiers = nil;
		}
		if (!_specifiers.count) {
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Không tải được trang cấu hình này. Mở “Xem & sao chép log” để xem chi tiết."
					   forKey:@"footerText"];
			_specifiers = [NSMutableArray arrayWithObject:group];
		}
		// Hàng “Giao thức API” được dựng BẰNG CODE, không bằng cell plist.
		// Lý do: `PSLinkListCell` trong plist là loại cell duy nhất khác biệt giữa
		// trang OpenAI (văng khi mở) và trang Gemini (chạy tốt); cùng đường dẫn
		// dựng specifier như 5 hàng chọn số ở trang gốc thì an toàn và đã được
		// chứng minh trên máy thật.
		if (self.provider == SXProviderOpenAI) {
			NSUInteger insertAt = _specifiers.count;
			for (NSUInteger i = 0; i < _specifiers.count; i++) {
				PSSpecifier *candidate = _specifiers[i];
				id candidateKey = [candidate propertyForKey:@"key"];
				if ([candidateKey isKindOfClass:[NSString class]] &&
					[candidateKey isEqualToString:@"endpointDisplay"]) {
					insertAt = i + 1;
					break;
				}
			}
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Giao thức API"
															 target:self
																set:nil
																get:@selector(sx_readAPIName:)
															 detail:[SXAPIChoiceController class]
															   cell:PSLinkCell
															   edit:nil];
			[row setProperty:@"openaiApi" forKey:@"key"];
			[row setProperty:[SXAPIChoiceController class] forKey:@"detail"];
			[row setProperty:@"openaiApi" forKey:@"configKey"];
			[_specifiers insertObject:row atIndex:MIN(insertAt, _specifiers.count)];
		}
		[self sx_applyCellTweaks];
	}
	return _specifiers;
}

/// Chữ bên phải hàng “Giao thức API”.
- (id)sx_readAPIName:(PSSpecifier *)specifier {
	(void)specifier;
	return SXOpenAIApiDisplayName([SXPrefs shared].openaiApi);
}

/// Ô nhập tự lưu: không cần nút “Lưu”, và không có cú reload nào để làm rơi
/// bàn phím. Đây là điều người dùng thật mong đợi ở một trang Settings.
- (void)sx_applyCellTweaks {
	// (Chỗ này từng đánh dấu ô nhập “tự lưu” bằng property riêng; giờ việc lưu do
	// UITextFieldTextDidChangeNotification trong trang đảm nhận, không cần cờ.)
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [NSString stringWithFormat:@"Cấu hình %@", SXProviderDisplayName(self.provider)];
	// Ghi nhớ chữ ký header ngay khi vào trang để lần quay lại từ màn hình con
	// mới biết có thay đổi hay không.
	self.headerSignature = [self sx_currentHeaderSignature];

	__weak typeof(self) weakSelf = self;
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(sx_textDidChange:)
												 name:UITextFieldTextDidChangeNotification
											   object:nil];
	(void)weakSelf;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sx_refreshSummaryRows];
	NSString *signature = [self sx_currentHeaderSignature];
	if (self.headerSignature && ![signature isEqualToString:self.headerSignature]) {
		[self sx_invalidateTestResult];
	}
	self.headerSignature = signature;
}

#pragma mark - Ô nhập

/// Ô nhập nào cũng thuộc một specifier có `key` và `defaults`. Ghi thẳng giá trị
/// người dùng vừa gõ xuống prefs, không reload gì cả.
- (void)sx_textDidChange:(NSNotification *)note {
	UITextField *field = note.object;
	if (![field isKindOfClass:[UITextField class]]) return;
	PSSpecifier *specifier = [self sx_specifierForField:field];
	if (!specifier) return;
	NSString *key = [specifier propertyForKey:@"key"];
	if (!key.length) return;

	NSString *text = field.text ?: @"";
	// Khoá API và endpoint: cắt khoảng trắng thừa ngay khi gõ xong từng ký tự là
	// phản cảm (người dùng đang dán giữa chừng) — chỉ cắt khi rời ô.
	if ([key isEqualToString:self.keyName] || [key isEqualToString:@"openaiBase"]) return;
	if ([key isEqualToString:self.fallbackModelKey]) [self sx_invalidateTestResult];

	[self sx_storeText:text forKey:key specifier:specifier];
}

/// Rời ô nhập: chuẩn hoá rồi lưu. Không bao giờ dựng lại bảng ở đây.
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	PSSpecifier *specifier = [self sx_specifierForField:textField];
	if (!specifier) return;
	NSString *key = [specifier propertyForKey:@"key"];
	NSString *text = textField.text ?: @"";
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if ([key isEqualToString:self.keyName]) {
		// Dán khoá thường kèm xuống dòng/BOM/dấu nháy — bóc trước khi lưu.
		text = [SXProviderConfigController cleanedKey:text];
		textField.text = text;
		[self sx_invalidateTestResult];
	} else if ([key isEqualToString:@"openaiBase"]) {
		NSString *normalized = [SXPrefs normalizedBaseURL:text];
		if (text.length && !normalized.length) {
			[SXUI alertOn:self title:@"Địa chỉ API không hợp lệ"
				  message:@"Địa chỉ phải bắt đầu bằng https:// (hoặc http:// cho máy chủ trong LAN) và có tên miền."];
			// Giữ nguyên chữ người dùng gõ để họ sửa, nhưng không lưu giá trị hỏng.
			return;
		}
		if (normalized.length) {
			text = normalized;
			textField.text = text;
		}
		[self sx_invalidateTestResult];
	} else if ([key isEqualToString:self.modelKey]) {
		if (!text.length) {
			// Mô hình trống = quay về mặc định, không lưu chuỗi rỗng đè lên.
			[SXPrefs setValue:nil forKey:key];
			[[SXPrefs shared] reload];
			[self sx_refreshSummaryRows];
			[self sx_postPrefsChanged];
			return;
		}
		[self sx_invalidateTestResult];
	} else if ([key isEqualToString:self.fallbackModelKey]) {
		if (!text.length) {
			[SXPrefs setValue:nil forKey:key];
			[[SXPrefs shared] reload];
			[self sx_refreshSummaryRows];
			[self sx_postPrefsChanged];
			return;
		}
		// Bỏ khoảng trắng đầu/cuối: dán kèm khoảng trắng làm model dự phòng bị
		// 404 đúng vào lúc cần nó nhất (khi retry).
		text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		textField.text = text;
		if (!text.length) {
			[SXPrefs setValue:nil forKey:key];
			[[SXPrefs shared] reload];
			[self sx_refreshSummaryRows];
			[self sx_postPrefsChanged];
			return;
		}
		[self sx_invalidateTestResult];
	} else if ([key isEqualToString:@"geminiModel"]) {
		if (!text.length) {
			[SXPrefs setValue:nil forKey:key];
			[[SXPrefs shared] reload];
			[self sx_refreshSummaryRows];
			[self sx_postPrefsChanged];
			return;
		}
	}

	[self sx_storeText:text forKey:key specifier:specifier];
	[self sx_refreshSummaryRows];
}

- (void)sx_storeText:(NSString *)text forKey:(NSString *)key specifier:(PSSpecifier *)specifier {
	if (!key.length) return;
	[SXPrefs setString:text forKey:key];
	[[SXPrefs shared] reload];
	(void)specifier;
	[self sx_postPrefsChanged];
}

- (void)sx_postPrefsChanged {
	notify_post("com.sirix.tweak/prefs.changed");
}

/// Tìm specifier của một UITextField bằng cách đối chiếu ô nhập đang hiển thị.
- (PSSpecifier *)sx_specifierForField:(UITextField *)field {
	for (PSSpecifier *specifier in self.specifiers) {
		id cellValue = [specifier propertyForKey:@"cell"];
		NSString *cellName = [cellValue isKindOfClass:[NSString class]] ? cellValue : nil;
		BOOL editable = [cellName isEqualToString:@"PSEditTextCell"] ||
						[cellName isEqualToString:@"PSSecureEditTextCell"];
		if (!editable) continue;
		UITableViewCell *cell = nil;
		@try {
			cell = [self cachedCellForSpecifier:specifier];
		} @catch (NSException *exception) {
			(void)exception;
		}
		if (!cell) continue;
		for (UIView *view in cell.contentView.subviews) {
			if (view == field) return specifier;
			if ([view isKindOfClass:[UITextField class]] && view == field) return specifier;
			for (UIView *deep in view.subviews) {
				if (deep == field) return specifier;
			}
		}
	}
	return nil;
}

/// Bóc BOM, ký tự vô hình, dấu nháy và xuống dòng quanh khoá API.
+ (NSString *)cleanedKey:(NSString *)raw {
	if (![raw isKindOfClass:[NSString class]]) return @"";
	NSMutableString *text = [raw mutableCopy];
	for (NSString *token in @[@"\uFEFF", @"\u200B", @"\u200C", @"\u200D", @"\u2060"]) {
		[text replaceOccurrencesOfString:token withString:@"" options:0
								   range:NSMakeRange(0, text.length)];
	}
	NSString *trimmed = [text stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSRange newline = [trimmed rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
	if (newline.location != NSNotFound) trimmed = [trimmed substringToIndex:newline.location];
	trimmed = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (trimmed.length >= 2) {
		unichar first = [trimmed characterAtIndex:0];
		unichar last = [trimmed characterAtIndex:trimmed.length - 1];
		if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
			trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
		}
	}
	return [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Dòng tóm tắt

- (NSString *)currentKey {
	SXPrefs *prefs = [SXPrefs shared];
	return self.provider == SXProviderGemini ? prefs.geminiKey : prefs.openaiKey;
}

- (NSString *)currentModel {
	SXPrefs *prefs = [SXPrefs shared];
	NSString *model = self.provider == SXProviderGemini ? prefs.geminiModel : prefs.openaiModel;
	return model.length ? model : (self.provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini");
}

- (NSString *)sx_currentHeaderSignature {
	return SXHeadersSummary([[SXPrefs shared] headersForProvider:self.provider]);
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
			NSString *base = normalized.length ? normalized
				: (raw.length ? @"⚠️ địa chỉ không hợp lệ" : @"Mặc định");
			// Giao thức nằm cùng dòng cho gọn: endpoint + đường dẫn sẽ gọi.
			return [base stringByAppendingString:SXAPIPathSuffix([SXPrefs shared].openaiApi)];
		}
		if ([key isEqualToString:@"testStatus"]) return [self testStatusText];
		if ([key isEqualToString:@"headersDisplay"]) {
			@try {
				return [[SXPrefs shared] headersSummaryForProvider:self.provider];
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"tóm tắt header lỗi: %@", exception.reason);
				return @"—";
			}
		}
		if ([key isEqualToString:self.keyName]) {
			// Ô khoá hiển thị khoá đã che; không bao giờ trả khoá thật cho bảng.
			NSString *live = [self currentKey];
			return live.length ? [SXPrefs maskedKey:live] : @"";
		}
		return [super readPreferenceValue:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"readPreferenceValue EXCEPTION (key=%@): %@ — %@",
				 [specifier propertyForKey:@"key"], exception.name, exception.reason);
		return nil;
	}
}

/// Chỉ đổi chữ của cell tóm tắt tại chỗ — không gọi reload nên bàn phím và con
/// trỏ của ô đang gõ không bị ảnh hưởng.
- (void)sx_refreshSummaryRows {
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	NSString *keyText = [self currentKey];
	NSString *rawBase = prefs.openaiBase;
	NSString *endpoint = nil;
	if (self.provider == SXProviderGemini) {
		endpoint = @"generativelanguage.googleapis.com";
	} else {
		NSString *base = [SXPrefs normalizedBaseURL:rawBase];
		if (!base.length) base = rawBase.length ? @"⚠️ địa chỉ không hợp lệ" : @"Mặc định";
		endpoint = [base stringByAppendingString:SXAPIPathSuffix(prefs.openaiApi)];
	}
	NSDictionary<NSString *, NSString *> *updates = @{
		@"keyDisplay": keyText.length ? [SXPrefs maskedKey:keyText] : @"Chưa đặt",
		@"modelDisplay": [self currentModel],
		@"endpointDisplay": endpoint,
		@"headersDisplay": [self sx_safeHeadersSummary],
		@"testStatus": [self testStatusText],
	};
	[updates enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		(void)stop;
		PSSpecifier *specifier = [self sx_specifierWithKey:key];
		if (!specifier) return;
		UITableViewCell *cell = nil;
		@try {
			cell = [self cachedCellForSpecifier:specifier];
		} @catch (NSException *exception) {
			return;
		}
		if (!cell) return;
		if (![cell isKindOfClass:[PSTableCell class]]) return;
		PSTableCell *tableCell = (PSTableCell *)cell;
		// setValue:forKey:@"value" không an toàn với cell không có KVC đó; dùng
		// refreshCellContents nếu cell còn specifier, còn không thì gán nhãn.
		@try {
			[tableCell setValue:value forKey:@"value"];
		} @catch (NSException *exception) {
			(void)exception;
		}
	}];
}

/// Một dòng tóm tắt lỗi không được làm hỏng cả bảng cấu hình.
- (NSString *)sx_safeHeadersSummary {
	@try {
		return [[SXPrefs shared] headersSummaryForProvider:self.provider];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"tóm tắt header lỗi: %@", exception.reason);
		return @"—";
	}
}

- (PSSpecifier *)sx_specifierWithKey:(NSString *)key {
	if (!key.length) return nil;
	for (PSSpecifier *specifier in self.specifiers) {
		id specifierKey = [specifier propertyForKey:@"key"];
		if ([specifierKey isKindOfClass:[NSString class]] && [specifierKey isEqualToString:key]) return specifier;
		id identifier = [specifier propertyForKey:@"id"];
		if ([identifier isKindOfClass:[NSString class]] && [identifier isEqualToString:key]) return specifier;
	}
	return nil;
}

/// Kết quả kiểm tra cũ đo bằng cấu hình khác nên không còn giá trị.
- (void)sx_invalidateTestResult {
	BOOL hadResult = self.testResult.length > 0;
	self.testResult = nil;
	[SXPrefs setValue:nil forKey:self.lastTestKey];
	if (hadResult) [self sx_refreshSummaryRows];
}

#pragma mark - Hành động

- (void)sx_pasteKey:(id)sender {
	(void)sender;
	NSString *clipboard = UIPasteboard.generalPasteboard.string;
	if (![clipboard isKindOfClass:[NSString class]] || !clipboard.length) {
		[SXUI alertOn:self title:@"Bộ nhớ tạm trống" message:@"Hãy sao chép khoá API trước, rồi quay lại đây."];
		return;
	}
	NSString *key = [SXProviderConfigController cleanedKey:clipboard];
	if (key.length < 8) {
		[SXUI alertOn:self title:@"Khoá không hợp lệ"
			  message:@"Nội dung trong bộ nhớ tạm quá ngắn để là một khoá API."];
		return;
	}
	[SXPrefs setString:key forKey:self.keyName];
	[[SXPrefs shared] reload];
	[self sx_invalidateTestResult];
	[SXUI tapFeedback];
	[self sx_refreshSummaryRows];
	[self sx_postPrefsChanged];
	SXLogInf(@"pref", @"dán khoá %@ (%@)", SXProviderDisplayName(self.provider), [SXPrefs maskedKey:key]);
	[SXUI alertOn:self
			title:@"Đã dán khoá"
		  message:[NSString stringWithFormat:@"Khoá đang dùng: %@", [SXPrefs maskedKey:key]]];
}

- (void)sx_testConnection:(id)sender {
	(void)sender;
	if (self.testing) return;
	[self.view endEditing:YES];
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];

	NSString *key = [self currentKey];
	key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!key.length) {
		[SXUI alertOn:self title:@"Chưa có khoá API"
			  message:[NSString stringWithFormat:@"Dán khoá %@ trước khi kiểm tra.",
					   SXProviderDisplayName(self.provider)]];
		return;
	}
	if (self.provider == SXProviderOpenAI && ![SXPrefs isValidBaseURL:prefs.openaiBase]) {
		[SXUI alertOn:self title:@"Địa chỉ API không hợp lệ"
			  message:@"Địa chỉ phải bắt đầu bằng https:// (hoặc http:// với máy chủ nội bộ) và có tên miền."];
		return;
	}

	self.testing = YES;
	self.testResult = @"⏳ Đang gửi thử…";
	[self sx_refreshSummaryRows];
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
				strongSelf.testResult = [NSString stringWithFormat:@"✗ %@", [SXUI truncate:error.localizedDescription limit:90]];
				SXLogWrn(@"pref", @"kiểm tra kết nối thất bại: %@", error.localizedDescription);
			} else {
				NSString *model = [info[@"model"] isKindOfClass:[NSString class]] ? info[@"model"] : strongSelf.currentModel;
				NSInteger ms = [info[@"ms"] integerValue];
				strongSelf.testResult = [NSString stringWithFormat:@"✓ %@ · %ld ms · %@", model, (long)ms, stamp];
				SXLogInf(@"pref", @"kiểm tra kết nối OK — %@ · %ld ms", model, (long)ms);
			}
			[SXPrefs setString:strongSelf.testResult forKey:strongSelf.lastTestKey];
			[strongSelf sx_refreshSummaryRows];
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
