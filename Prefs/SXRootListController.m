#import "SXPrefs.h"
#import "SXRootListController.h"
#import "SXLogViewController.h"
#import "SXChoiceRow.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXTools.h"
#import "SXUpdate.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#ifndef SX_SCHEME
#define SX_SCHEME "unknown"
#endif

#pragma mark - Nạp plist cài đặt ở đúng nơi

/// Bundle chứa tài nguyên cài đặt. Trên máy roothide, `NSBundle mainBundle` của
/// Preferences là `/var/containers/...` còn bundle thật nằm dưới `/var/jb`; nhầm
/// một trong hai thì `loadSpecifiersFromPlistName:` trả nil và trang trắng.
static NSBundle *SXSettingsBundle(Class aClass) {
	NSBundle *bundle = [NSBundle bundleForClass:aClass];
	if (bundle) return bundle;
	NSString *path = @"/Library/PreferenceBundles/SiriXPreferences.bundle";
	for (NSString *prefix in @[@"/var/jb", @""]) {
		NSString *candidate = [prefix stringByAppendingString:path];
		NSBundle *found = [NSBundle bundleWithPath:candidate];
		if (found && [found pathForResource:@"Root" ofType:@"plist"]) return found;
	}
	return nil;
}

/// Tải specifier từ plist với đường dẫn dự phòng. `loadSpecifiersFromPlistName:`
/// dựa vào `self.bundle`; nếu bundle chưa đúng thì gán lại rồi thử lần nữa.
NSMutableArray *SXLoadSpecifiers(PSListController *controller, Class aClass, NSString *plistName) {
	NSMutableArray *loaded = nil;
	@try {
		loaded = [[controller loadSpecifiersFromPlistName:plistName target:controller] mutableCopy];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"load %@ EXCEPTION: %@ — %@", plistName, exception.name, exception.reason);
		loaded = nil;
	}
	if (loaded.count) return loaded;

	NSBundle *bundle = SXSettingsBundle(aClass);
	NSString *found = [bundle pathForResource:plistName ofType:@"plist"];
	SXLogWrn(@"pref", @"load %@ trả rỗng — thử lại với bundle=%@ (plist=%@)",
			 plistName, bundle.bundlePath ?: @"?", found ?: @"(không thấy)");
	if (!bundle || !found) return loaded;
	@try {
		NSMutableArray *retry = [[controller loadSpecifiersFromPlistName:plistName
																  target:controller
																  bundle:bundle] mutableCopy];
		if (retry.count) {
			SXLogInf(@"pref", @"load %@ thành công với bundle tường minh (%lu mục)",
					 plistName, (unsigned long)retry.count);
			return retry;
		}
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"load %@ với bundle tường minh EXCEPTION: %@ — %@",
				 plistName, exception.name, exception.reason);
	}
	return loaded;
}

#pragma mark - Chẩn đoán exception

static NSUncaughtExceptionHandler *SXPrevExceptionHandler = NULL;

static void SXExceptionHandler(NSException *exception) {
	SXLogErr(@"pref", @"EXCEPTION không bắt được: %@ — %@ | %@",
			 exception.name, exception.reason,
			 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
	if (SXPrevExceptionHandler) SXPrevExceptionHandler(exception);
}

#pragma mark - Bộ chọn giá trị

/// Một mức gợi ý: giá trị + nhãn + ghi chú ngắn.
@interface SXChoiceOption : NSObject
@property (nonatomic) double value;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *hint;
@property (nonatomic) BOOL isDefault;
+ (instancetype)value:(double)value title:(NSString *)title hint:(NSString *)hint isDefault:(BOOL)isDefault;
@end

@implementation SXChoiceOption
+ (instancetype)value:(double)value title:(NSString *)title hint:(NSString *)hint isDefault:(BOOL)isDefault {
	SXChoiceOption *option = [SXChoiceOption new];
	option.value = value;
	option.title = title;
	option.hint = hint;
	option.isDefault = isDefault;
	return option;
}
@end

/// Định nghĩa một key số chỉnh được: miền giá trị, đơn vị, các mức gợi ý và
/// cách đọc/ghi. Thêm một key mới = thêm một hàm dựng ở đây, không phải sửa
/// màn hình — trước đây mỗi mức là một mảng song song dễ lệch nhau.
@interface SXChoiceDefinition : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic) double minimum;
@property (nonatomic) double maximum;
@property (nonatomic) BOOL integerOnly;
@property (nonatomic) double defaultValue;
@property (nonatomic, copy) NSArray<SXChoiceOption *> *options;
@property (nonatomic, copy) NSString *footer;
/// Đọc giá trị hiện tại (đã chuẩn hoá) từ prefs.
@property (nonatomic, copy) double (^readBlock)(SXPrefs *prefs);
@end

@implementation SXChoiceDefinition
@end

static SXChoiceDefinition *SXChoiceDefinitionFor(NSString *key) {
	SXChoiceDefinition *definition = [SXChoiceDefinition new];
	definition.key = key;
	if ([key isEqualToString:@"temperature"]) {
		definition.title = @"Nhiệt độ";
		definition.unit = @"";
		definition.minimum = 0.0;
		definition.maximum = 2.0;
		definition.integerOnly = NO;
		definition.defaultValue = 0.7;
		definition.readBlock = ^double(SXPrefs *prefs) { return prefs.temperature; };
		definition.options = @[
			[SXChoiceOption value:0.0 title:@"0.0 · máy móc, ít sáng tạo" hint:@"Câu trả lời ổn định nhất" isDefault:NO],
			[SXChoiceOption value:0.3 title:@"0.3 · bám sát câu hỏi" hint:@"Ít lan man, phù hợp tra cứu" isDefault:NO],
			[SXChoiceOption value:0.7 title:@"0.7 · cân bằng" hint:@"Mức khuyến nghị" isDefault:YES],
			[SXChoiceOption value:1.0 title:@"1.0 · sáng tạo vừa" hint:@"Đa dạng cách diễn đạt" isDefault:NO],
			[SXChoiceOption value:1.5 title:@"1.5 · rất sáng tạo" hint:@"Dễ lan man, có thể sai chi tiết" isDefault:NO],
		];
		definition.footer = @"Thấp = bám sát câu hỏi, lặp lại được. Cao = nhiều cách diễn đạt hơn nhưng dễ bịa. Nhập giá trị bất kỳ từ 0.0 đến 2.0 (bước 0.05).";
		return definition;
	}
	if ([key isEqualToString:@"contextTurns"]) {
		definition.title = @"Ngữ cảnh hội thoại";
		definition.unit = @"câu";
		definition.minimum = 0;
		definition.maximum = 40;
		definition.integerOnly = YES;
		definition.defaultValue = 8;
		definition.readBlock = ^double(SXPrefs *prefs) { return (double)prefs.contextTurns; };
		definition.options = @[
			[SXChoiceOption value:0 title:@"0 câu · không nhớ gì" hint:@"Mỗi câu độc lập, tốn ít token nhất" isDefault:NO],
			[SXChoiceOption value:4 title:@"4 câu · hội thoại ngắn" hint:@"Đủ cho hỏi–đáp liền mạch" isDefault:NO],
			[SXChoiceOption value:8 title:@"8 câu · cân bằng" hint:@"Mức khuyến nghị" isDefault:YES],
			[SXChoiceOption value:16 title:@"16 câu · hội thoại dài" hint:@"Nhớ lâu hơn, tốn token hơn" isDefault:NO],
			[SXChoiceOption value:30 title:@"30 câu · nhớ rất lâu" hint:@"Chỉ dùng khi cần trao đổi dài" isDefault:NO],
		];
		definition.footer = @"Số cặp hỏi/đáp gần nhất gửi kèm mỗi câu hỏi. 0 = mỗi câu độc lập (rẻ nhất); càng cao càng tốn token và dễ nhiễu. Lịch sử lưu trên máy vẫn giữ tới 40 lượt.";
		return definition;
	}
	if ([key isEqualToString:@"timeout"]) {
		definition.title = @"Thời gian chờ AI";
		definition.unit = @"giây";
		definition.minimum = 2;
		definition.maximum = 120;
		definition.integerOnly = YES;
		definition.defaultValue = 10;
		definition.readBlock = ^double(SXPrefs *prefs) { return prefs.responseTimeout; };
		definition.options = @[
			[SXChoiceOption value:6 title:@"6 giây · chỉ model thật nhanh" hint:@"gpt-4o-mini, Gemini Flash" isDefault:NO],
			[SXChoiceOption value:10 title:@"10 giây · cân bằng" hint:@"Mức khuyến nghị" isDefault:YES],
			[SXChoiceOption value:15 title:@"15 giây · model lớn" hint:@"gpt-4o, Gemini Pro" isDefault:NO],
			[SXChoiceOption value:30 title:@"30 giây · model suy luận" hint:@"o4-mini, R1…" isDefault:NO],
			[SXChoiceOption value:60 title:@"60 giây · kiên nhẫn" hint:@"Cần tăng trần chờ Siri ở dưới" isDefault:NO],
		];
		definition.footer = @"Ngân sách tối đa cho toàn bộ một câu hỏi (gồm mọi vòng gọi công cụ). Đặt cao hơn trần chờ Siri bên dưới thì đáp án tới sau trần sẽ không được hiển thị.";
		return definition;
	}
	if ([key isEqualToString:@"replyDeadline"]) {
		definition.title = @"Trần chờ Siri";
		definition.unit = @"giây";
		definition.minimum = 2;
		definition.maximum = 20;
		definition.integerOnly = YES;
		definition.defaultValue = 8;
		definition.readBlock = ^double(SXPrefs *prefs) { return prefs.replyDeadline; };
		definition.options = @[
			[SXChoiceOption value:5 title:@"5 giây · nhanh, an toàn" hint:@"Chỉ model rất nhanh kịp" isDefault:NO],
			[SXChoiceOption value:8 title:@"8 giây · cân bằng" hint:@"Mức khuyến nghị" isDefault:YES],
			[SXChoiceOption value:12 title:@"12 giây · chờ lâu hơn" hint:@"Model lớn có cơ hội trả lời" isDefault:NO],
			[SXChoiceOption value:16 title:@"16 giây · kiên nhẫn" hint:@"Siri có thể tự đóng giao diện" isDefault:NO],
		];
		definition.footer = @"Bao lâu SiriX giữ giao diện Siri chờ trước khi quyết định dùng Siri gốc hay bubble “chưa kịp”. Siri gốc tự đóng sau khoảng 8–10 giây nên để cao hơn thường không có tác dụng.";
		return definition;
	}
	if ([key isEqualToString:@"maxToolRounds"]) {
		definition.title = @"Số vòng công cụ";
		definition.unit = @"vòng";
		definition.minimum = 1;
		definition.maximum = 6;
		definition.integerOnly = YES;
		definition.defaultValue = 3;
		definition.readBlock = ^double(SXPrefs *prefs) { return (double)prefs.maxToolRounds; };
		definition.options = @[
			[SXChoiceOption value:1 title:@"1 vòng · nhanh nhất" hint:@"Chỉ một lần gọi công cụ" isDefault:NO],
			[SXChoiceOption value:2 title:@"2 vòng · đủ cho hầu hết câu" hint:@"Đọc dữ liệu rồi trả lời" isDefault:NO],
			[SXChoiceOption value:3 title:@"3 vòng · mặc định" hint:@"Câu hỏi cần vài bước" isDefault:YES],
			[SXChoiceOption value:5 title:@"5 vòng · câu hỏi nhiều bước" hint:@"Chậm hơn, tốn token hơn" isDefault:NO],
		];
		definition.footer = @"Số lần AI được gọi công cụ trong một câu hỏi. Nhiều vòng hơn thì giải được câu nhiều bước nhưng lâu hơn và dễ vượt trần chờ Siri.";
		return definition;
	}
	return nil;
}

@interface SXChoiceController : PSListController <UITextFieldDelegate>
@property (nonatomic, copy) NSString *prefsKey;
@property (nonatomic, strong) SXChoiceDefinition *definition;
@end

@implementation SXChoiceController

- (void)viewDidLoad {
	[super viewDidLoad];
	// `specifier` là hàng PSLinkListCell vừa được chọn ở trang gốc: key nằm ở đó,
	// nên bộ chọn không cần plist riêng hay thuộc tính đặc biệt trên hàng.
	if (!self.prefsKey.length) {
		NSString *key = [self.specifier propertyForKey:PSKeyNameKey];
		if (key.length) self.prefsKey = key;
	}
	// Không chốt `definition` ở đây: `specifier` có thể tới sau. `specifiers`
	// đọc lại và ghi vào cùng thuộc tính này.
	self.definition = SXChoiceDefinitionFor(self.prefsKey);
	self.title = self.definition.title ?: @"Giá trị";
	SXLogDbg(@"pref", @"bộ chọn mở: key=%@, specifier=%@",
			 self.prefsKey ?: @"(trống)", NSStringFromClass([self.specifier class]));
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, self.definition.title ?: @"Giá trị",
								  @"không dựng được danh sách lựa chọn");
}

- (double)sx_currentValue {
	if (!self.definition) return 0;
	return self.definition.readBlock ? self.definition.readBlock([SXPrefs shared]) : self.definition.defaultValue;
}

- (NSString *)sx_formatValue:(double)value {
	if (self.definition.integerOnly) return [NSString stringWithFormat:@"%.0f", value];
	return [NSString stringWithFormat:@"%.2f", value];
}

/// Nhãn đọc nhanh: "10 giây", "0.70", "8 câu".
- (NSString *)sx_displayValue:(double)value {
	NSString *number = [self sx_formatValue:value];
	return self.definition.unit.length
		? [NSString stringWithFormat:@"%@ %@", number, self.definition.unit] : number;
}

- (double)sx_normalize:(double)value {
	SXChoiceDefinition *definition = self.definition;
	double clamped = MIN(MAX(value, definition.minimum), definition.maximum);
	if (definition.integerOnly) return round(clamped);
	return round(clamped * 20.0) / 20.0;   // bước 0.05
}

#pragma mark - Ghi

- (void)sx_applyValue:(double)value {
	if (!self.definition || !self.prefsKey.length) return;
	double normalized = [self sx_normalize:value];
	id stored = self.definition.integerOnly ? @((NSInteger)normalized) : @(normalized);
	[SXPrefs setValue:stored forKey:self.prefsKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"%@ = %@", self.prefsKey, [self sx_displayValue:normalized]);
	[self.navigationController popViewControllerAnimated:YES];
}

/// Ô nhập số nằm trong một PSEditTextCell do Preferences dựng; lấy giá trị từ
/// chính cell đang hiển thị thay vì giữ con trỏ (cell có thể bị tái sử dụng).
- (UITextField *)sx_editingField {
	// `self.table` là thuộc tính của PSListController đời cũ; trên iOS 15 nó
	// không còn (đã đổi sang `tableView`), truy cập là văng. Lấy bảng từ view.
	UITableView *table = nil;
	if ([self respondsToSelector:@selector(tableView)]) table = [self performSelector:@selector(tableView)];
	if (!table && [self.view isKindOfClass:[UITableView class]]) table = (UITableView *)self.view;
	if (!table) {
		for (UIView *subview in self.view.subviews) {
			if ([subview isKindOfClass:[UITableView class]]) { table = (UITableView *)subview; break; }
		}
	}
	if (!table) return nil;
	for (UITableViewCell *cell in table.visibleCells) {
		if (![cell isKindOfClass:[UITableViewCell class]]) continue;
		if ([cell respondsToSelector:@selector(editingTextField)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			id field = [cell performSelector:@selector(editingTextField)];
#pragma clang diagnostic pop
			if ([field isKindOfClass:[UITextField class]]) return field;
		}
		for (UIView *subview in cell.contentView.subviews) {
			if ([subview isKindOfClass:[UITextField class]]) return (UITextField *)subview;
		}
	}
	return nil;
}

- (void)sx_applyCustomField {
	UITextField *field = [self sx_editingField];
	NSString *raw = field.text;
	if (!raw.length) {
		[SXUI alertOn:self title:@"Chưa nhập gì"
			  message:@"Gõ một số vào ô “Giá trị” rồi bấm Dùng giá trị này."];
		return;
	}
	NSString *text = [raw stringByReplacingOccurrencesOfString:@"," withString:@"."];
	text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSScanner *scanner = [NSScanner scannerWithString:text];
	double parsed = 0;
	BOOL ok = text.length && [scanner scanDouble:&parsed] && scanner.isAtEnd;
	if (!ok) {
		[SXUI alertOn:self title:@"Giá trị không hợp lệ"
			  message:[NSString stringWithFormat:@"Hãy nhập một số từ %@ đến %@.",
					   [self sx_formatValue:self.definition.minimum],
					   [self sx_formatValue:self.definition.maximum]]];
		return;
	}
	if (self.definition.integerOnly && floor(parsed) != parsed) {
		[SXUI alertOn:self title:@"Cần số nguyên"
			  message:[NSString stringWithFormat:@"Mục này chỉ nhận số nguyên (%@).", self.definition.unit]];
		return;
	}
	if (parsed < self.definition.minimum || parsed > self.definition.maximum) {
		[SXUI alertOn:self title:@"Ngoài khoảng cho phép"
			  message:[NSString stringWithFormat:@"Chọn từ %@ đến %@.",
					   [self sx_displayValue:self.definition.minimum],
					   [self sx_displayValue:self.definition.maximum]]];
		return;
	}
	[self.view endEditing:YES];
	[self sx_applyValue:parsed];
}

#pragma mark - Sao lưu cấu hình

- (void)sx_exportSettings:(id)sender {
	(void)sender;
	[[SXPrefs shared] reload];
	NSDictionary *settings = [[SXPrefs shared] exportableSettings];
	if (!settings.count) {
		[SXUI alertOn:self title:@"Chưa có gì để xuất" message:@"Bạn chưa đổi cài đặt nào khỏi mặc định."];
		return;
	}
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:settings
															 format:NSPropertyListXMLFormat_v1_0
															options:0
															  error:&error];
	if (!data) {
		[SXUI alertOn:self title:@"Không tạo được tệp" message:error.localizedDescription];
		return;
	}
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.dateFormat = @"yyyyMMdd-HHmm";
	NSString *name = [NSString stringWithFormat:@"SiriX-%@.plist", [formatter stringFromDate:NSDate.date]];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	if (![data writeToFile:path atomically:YES]) {
		[SXUI alertOn:self title:@"Không ghi được tệp" message:@"Thử lại sau khi đóng bớt ứng dụng."];
		return;
	}
	SXLogInf(@"pref", @"xuất cấu hình (%lu key) → %@", (unsigned long)settings.count, name);
	UIActivityViewController *activity =
		[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
										 applicationActivities:nil];
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) popover.sourceView = self.view;
	[self presentViewController:activity animated:YES completion:nil];
}

- (void)sx_importSettings:(id)sender {
	(void)sender;
	// Preferences không có UIDocumentPicker sẵn — dán nội dung tệp là cách chắc chắn
	// chạy được trên mọi jailbreak (không phụ thuộc quyền truy cập tệp của Settings).
	UIAlertController *alert = [UIAlertController
		alertControllerWithTitle:@"Phục hồi cấu hình"
						 message:@"Dán nội dung tệp sao lưu (.plist) vào ô dưới. Cấu hình hiện tại sẽ bị thay; lịch sử và thống kê giữ nguyên."
				  preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = @"<plist>…";
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	__weak UIAlertController *weakAlert = alert;
	[alert addAction:[UIAlertAction actionWithTitle:@"Phục hồi" style:UIAlertActionStyleDestructive
										   handler:^(UIAlertAction *action) {
		(void)action;
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *text = weakAlert.textFields.firstObject.text ?: @"";
		NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
		id parsed = nil;
		if (data.length) {
			parsed = [NSPropertyListSerialization propertyListWithData:data
															  options:NSPropertyListImmutable
															   format:NULL
																error:NULL];
		}
		if (![parsed isKindOfClass:[NSDictionary class]]) {
			[SXUI alertOn:strongSelf title:@"Không đọc được tệp"
				  message:@"Nội dung phải là plist dạng XML hoặc nhị phân của bản sao lưu SiriX."];
			return;
		}
		[SXUI confirmOn:strongSelf
				  title:@"Ghi đè cấu hình hiện tại?"
				message:@"Khoá API, endpoint, model và tuỳ chọn sẽ được thay bằng nội dung tệp."
			confirmText:@"Phục hồi"
				 action:^{
			NSInteger written = [[SXPrefs shared] importSettings:(NSDictionary *)parsed];
			if (written <= 0) {
				[SXUI alertOn:strongSelf title:@"Tệp không có cấu hình SiriX" message:nil];
				return;
			}
			notify_post("com.sirix.tweak/prefs.changed");
			[SXUI tapFeedback];
			SXLogInf(@"pref", @"phục hồi cấu hình từ tệp (%ld key)", (long)written);
			strongSelf->_specifiers = nil;
			@try {
				[strongSelf reloadSpecifiers];
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"reload sau phục hồi: %@", exception.reason);
			}
			[SXUI alertOn:strongSelf
					title:@"Đã phục hồi"
				  message:[NSString stringWithFormat:@"%ld mục đã được ghi. Khởi động lại SpringBoard nếu cần áp dụng ngay.",
						   (long)written]];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Hành động

- (void)sx_pick:(PSSpecifier *)row specifier:(PSSpecifier *)group {
	(void)group;
	NSNumber *value = [row propertyForKey:@"sxValue"];
	if (![value isKindOfClass:[NSNumber class]]) return;
	[self.view endEditing:YES];
	[self sx_applyValue:value.doubleValue];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	(void)textField;
	[self sx_applyCustomField];
	return YES;
}

#pragma mark - Bảng

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *items = [NSMutableArray array];
		SXChoiceDefinition *definition = self.definition;
		if (!definition) {
			// `specifier` (hàng vừa bấm) có thể chưa được Preferences gán lúc
			// viewDidLoad; đọc lại ở đây. Không suy ra được key thì hiện thông
			// báo thay vì màn hình trống.
			@try {
				NSString *key = [self.specifier propertyForKey:PSKeyNameKey];
				if (key.length && !self.prefsKey.length) self.prefsKey = key;
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"đọc key ở specifiers: %@", exception.reason);
			}
			if (!definition) definition = SXChoiceDefinitionFor(self.prefsKey);
			self.definition = definition;
			if (definition.title.length) self.title = definition.title;
		}
		if (!definition) {
			SXLogErr(@"pref", @"bộ chọn %@ thiếu định nghĩa (specifier=%@) — hiện thông báo",
					 self.prefsKey ?: @"(trống)", NSStringFromClass([self.specifier class]));
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:self.title ?: @"Giá trị"];
			[group setProperty:[NSString stringWithFormat:
					@"Không tìm thấy định nghĩa cho khoá “%@”. Mở lại từ trang chính, hoặc gửi log để mình thêm định nghĩa.",
					self.prefsKey.length ? self.prefsKey : @"(không đọc được key)"]
					forKey:@"footerText"];
			[items addObject:group];
			_specifiers = items;
			return _specifiers;
		}
		double current = [self sx_currentValue];

		// Nhóm 1: giá trị đang dùng + ô nhập số tuỳ chỉnh.
		PSSpecifier *currentGroup = [PSSpecifier groupSpecifierWithName:@"Giá trị đang dùng"];
		currentGroup.cellType = PSGroupCell;
		[items addObject:currentGroup];

		PSSpecifier *valueRow = [PSSpecifier preferenceSpecifierNamed:[self sx_displayValue:current]
															   target:self
																  set:nil
																  get:@selector(sx_readCurrentForSpecifier:)
															   detail:nil
																 cell:PSTitleValueCell
																 edit:nil];
		[valueRow setProperty:self.prefsKey forKey:PSKeyNameKey];
		[items addObject:valueRow];

		PSSpecifier *customGroup = [PSSpecifier groupSpecifierWithName:@"Nhập giá trị riêng"];
		customGroup.cellType = PSGroupCell;
		[customGroup setProperty:[NSString stringWithFormat:@"Số từ %@ đến %@. %@",
								  [self sx_formatValue:definition.minimum],
								  [self sx_formatValue:definition.maximum],
								  definition.integerOnly ? @"Chỉ nhận số nguyên." : @"Bước 0.05."]
						  forKey:@"footerText"];
		[items addObject:customGroup];

		PSSpecifier *fieldRow = [PSSpecifier preferenceSpecifierNamed:@"Giá trị"
															   target:self
																  set:nil get:nil
															   detail:nil
																 cell:PSEditTextCell
																 edit:nil];
		[fieldRow setProperty:definition.title forKey:@"placeholder"];
		[fieldRow setProperty:@(YES) forKey:@"noAutoCorrect"];
		// `autoCaps` là THUỘC TÍNH KIỂU CHUỖI của Preferences ("none"/"sentences"/
		// "words"/"all"), không phải boolean. Đặt @(NO) khiến Preferences gọi
		// -isEqualToString: lên __NSCFBoolean và ném NSInvalidArgumentException.
		[fieldRow setProperty:@"none" forKey:@"autoCaps"];
		[fieldRow setProperty:@(UIKeyboardTypeNumbersAndPunctuation) forKey:@"keyboardType"];
		[items addObject:fieldRow];

		PSSpecifier *applyRow = [PSSpecifier preferenceSpecifierNamed:@"Dùng giá trị này"
															   target:self
																  set:nil get:nil
															   detail:nil
																 cell:PSButtonCell
																 edit:nil];
		applyRow.cellType = PSButtonCell;
		[applyRow setProperty:@(YES) forKey:PSEnabledKey];
		[items addObject:applyRow];

		// Nhóm 2: các mức gợi ý.
		PSSpecifier *levelsGroup = [PSSpecifier groupSpecifierWithName:@"Mức gợi ý"];
		levelsGroup.cellType = PSGroupCell;
		[levelsGroup setProperty:definition.footer ?: @"" forKey:@"footerText"];
		[items addObject:levelsGroup];

		for (NSUInteger i = 0; i < definition.options.count; i++) {
			SXChoiceOption *option = definition.options[i];
			NSString *name = option.isDefault
				? [option.title stringByAppendingString:@" — mặc định"] : option.title;
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:name
															  target:self
																 set:@selector(sx_pick:specifier:)
																 get:nil
															  detail:nil
																cell:PSListItemCell
																edit:nil];
			[row setProperty:@(option.value) forKey:@"sxValue"];
			// Dấu "đang dùng" phải nằm trên HÀNG (dấu ✓ của cell), không phải trong
			// chữ của ô value: hàng PSListItemCell chỉ hiện chữ ở ô value nên trước
			// đây nó trông như một phần của tên mức.
			BOOL active = fabs(option.value - current) < 0.001;
			[row setProperty:@(active) forKey:SXChoiceActiveKey];
			[row setProperty:@(SXChoiceCellModeOption) forKey:SXChoiceModeKey];
			[row setProperty:option.hint forKey:SXChoiceHintKey];
			[row setProperty:NSClassFromString(@"SXChoiceRow") forKey:PSCellClassKey];
			[items addObject:row];
		}
		_specifiers = items;
	}
	return _specifiers;
}

/// Định dạng lại hàng "Giá trị đang dùng" mỗi lần bảng đọc lại.
- (id)sx_readCurrentForSpecifier:(PSSpecifier *)specifier {
	(void)specifier;
	return [self sx_displayValue:[self sx_currentValue]];
}

@end
#pragma mark - Trang gốc

@interface SXRootListController ()
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusDot;
@end

@implementation SXRootListController {
	int _prefsToken;
	NSTimer *_refreshTimer;
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
		NSMutableArray *loaded = SXLoadSpecifiers(self, self.class, @"Root");
		if (!loaded.count) {
			// Root.plist không đọc được (thiếu trong gói, hỏng, hoặc Preferences ném
			// khi dựng cell). Settings không bao giờ được để trống: hiện lý do, đường
			// dẫn bundle và lối thoát thay vì một trang trắng.
			NSBundle *bundle = [NSBundle bundleForClass:self.class];
			NSString *rootPath = [bundle pathForResource:@"Root" ofType:@"plist"];
			SXLogErr(@"pref", @"Root.plist KHÔNG tải được — hiện bảng dự phòng (bundle=%@, root=%@, version=%@, scheme=%@)",
					 bundle.bundlePath ?: @"?", rootPath ?: @"(thiếu)", SX_VERSION, @SX_SCHEME);
			NSString *footer = rootPath.length
				? [NSString stringWithFormat:@"Không dựng được bảng cài đặt từ %@. Bản %@ · %@. "
				   @"Gửi log qua “Xem & sao chép log” để mình sửa đúng chỗ.", rootPath.lastPathComponent,
				   SX_VERSION, @SX_SCHEME]
				: [NSString stringWithFormat:@"Gói cài đặt thiếu Root.plist (bundle=%@). Bản %@ · %@. "
				   @"Cài lại gói .deb đúng loại (rootless/roothide) rồi mở lại Settings.",
				   bundle.bundlePath ?: @"?", SX_VERSION, @SX_SCHEME];
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX — chưa tải được bảng cài đặt"];
			[group setProperty:footer forKey:@"footerText"];
			PSSpecifier *log = [PSSpecifier preferenceSpecifierNamed:@"Xem & sao chép log"
															  target:self set:NULL get:NULL
															  detail:NSClassFromString(@"SXLogViewController")
																cell:PSLinkCell edit:nil];
			PSSpecifier *reload = [PSSpecifier preferenceSpecifierNamed:@"Thử tải lại bảng cài đặt"
															   target:self
																  set:NULL get:NULL detail:nil
																 cell:PSButtonCell edit:nil];
			reload.cellType = PSButtonCell;
			[reload setProperty:@(YES) forKey:PSEnabledKey];
			[reload setProperty:NSStringFromSelector(@selector(sx_reloadTable:)) forKey:PSButtonActionKey];
			PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Khởi động lại SpringBoard"
																target:self
																   set:NULL get:NULL detail:nil
																  cell:PSButtonCell edit:nil];
			respring.cellType = PSButtonCell;
			[respring setProperty:@(YES) forKey:PSEnabledKey];
			[respring setProperty:NSStringFromSelector(@selector(sx_respring:)) forKey:PSButtonActionKey];
			loaded = [NSMutableArray arrayWithObjects:group, log, reload, respring, nil];
		}
		_specifiers = [self sx_applyChoiceDetails:loaded];
		// Đọc lại toàn bộ prefs một lần trước khi vẽ: tránh hàng “Tổng quan” hiện
		// giá trị cũ do CFPreferences chưa đồng bộ từ tiến trình khác.
		[[SXPrefs shared] reload];
		SXLogInf(@"pref", @"bảng cài đặt sẵn sàng: %lu specifier · version=%@ · scheme=%@ · bundle=%@",
				 (unsigned long)_specifiers.count, SX_VERSION, @SX_SCHEME,
				 [NSBundle bundleForClass:self.class].bundlePath ?: @"?");
	}
	return _specifiers;
}

/// Trỏ các cell số sang bộ chọn mức cố định và gắn footer ngắn giải thích.
- (NSMutableArray *)sx_applyChoiceDetails:(NSMutableArray *)specifiers {
	NSDictionary<NSString *, Class> *choosers = @{
		@"temperature": [SXChoiceController class],
		@"contextTurns": [SXChoiceController class],
		@"timeout": [SXChoiceController class],
		@"replyDeadline": [SXChoiceController class],
		@"maxToolRounds": [SXChoiceController class],
	};
	for (PSSpecifier *specifier in specifiers) {
		NSString *key = [specifier propertyForKey:@"key"];
		if (!key.length) continue;

		// Mọi hàng "chọn một giá trị" được vẽ bằng SXChoiceRow. Cell của
		// Preferences hiện trạng thái bằng cách tra `readPreferenceValue:` trong
		// `validValues`; ta trả nhãn đã dịch nên nó không khớp và ô phải rỗng.
		// Cell riêng thì luôn vẽ được "giá trị đang dùng" (hoặc ✓ ở trang chọn).
		if (specifier.cellType == PSLinkListCell) {
			[specifier setProperty:NSClassFromString(@"SXChoiceRow") forKey:PSCellClassKey];
			[specifier setProperty:@(SXChoiceCellModeValue) forKey:SXChoiceModeKey];
			[specifier setProperty:[self sx_valueLabelForSpecifier:specifier] ?: @""
							forKey:SXChoiceTrailingKey];
		}

		Class chooser = choosers[key];
		if (chooser) [specifier setProperty:chooser forKey:@"detail"];
	}
	return specifiers;
}

#pragma mark - Giá trị động

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	@try {
		NSString *key = [specifier propertyForKey:@"key"];
		SXPrefs *prefs = [SXPrefs shared];

		if ([key isEqualToString:@"toolsDisplay"]) {
			NSArray<SXTool *> *tools = [SXTools catalog];
			NSUInteger enabled = 0;
			for (SXTool *tool in tools) {
				if ([prefs isToolEnabled:tool.name]) enabled++;
			}
			if (!tools.count) return @"Chưa cài công cụ nào";
			return [NSString stringWithFormat:@"%lu/%lu công cụ đang bật",
					(unsigned long)enabled, (unsigned long)tools.count];
		}
		// Trả GIÁ TRỊ THẬT (`smart`, `prefix`, `gemini`, `bubble`…), không phải nhãn
		// đã dịch: `PSLinkListCell` hiện "đang chọn" bằng cách tra giá trị này
		// trong `validValues`. Trả nhãn thì không khớp ⇒ ô bên phải rỗng, không có
		// dấu ✓ — đúng hiện tượng "chọn xong không thấy trạng thái gì".
		// Nhãn dễ đọc được thêm vào `sx_valueLabelForSpecifier:` (chú thích dưới
		// hàng) nên người dùng vẫn đọc được nghĩa.
		if ([key isEqualToString:@"mode"]) {
			return prefs.mode == SXReplyModeFull ? @"full" : @"smart";
		}
		if ([key isEqualToString:@"triggerMode"]) {
			return [prefs.triggerMode isEqualToString:@"prefix"] ? @"prefix" : @"auto";
		}
		if ([key isEqualToString:@"provider"]) {
			return prefs.provider == SXProviderGemini ? @"gemini" : @"openai";
		}
		if ([key isEqualToString:@"timeoutAction"]) {
			return prefs.timeoutAction;
		}
		if ([key isEqualToString:@"temperature"]) {
			NSString *hint = prefs.temperature <= 0.05 ? @"máy móc"
				: prefs.temperature < 0.5 ? @"bám câu hỏi"
				: prefs.temperature < 0.9 ? @"cân bằng"
				: prefs.temperature < 1.3 ? @"sáng tạo" : @"rất sáng tạo";
			return [NSString stringWithFormat:@"%.2f · %@", prefs.temperature, hint];
		}
		if ([key isEqualToString:@"contextTurns"]) {
			return prefs.contextTurns == 0 ? @"Không nhớ (0 câu)"
				: [NSString stringWithFormat:@"%ld câu", (long)prefs.contextTurns];
		}
		if ([key isEqualToString:@"timeout"]) {
			return [NSString stringWithFormat:@"%.0f giây", prefs.responseTimeout];
		}
		if ([key isEqualToString:@"replyDeadline"]) {
			return [NSString stringWithFormat:@"%.0f giây", prefs.replyDeadline];
		}
		if ([key isEqualToString:@"maxToolRounds"]) {
			return [NSString stringWithFormat:@"%ld vòng", (long)prefs.maxToolRounds];
		}
		if ([key isEqualToString:@"summary.status"]) return prefs.statusSummary;
		if ([key isEqualToString:@"summary.provider"]) return prefs.providerSummary;
		if ([key isEqualToString:@"summary.reply"]) return prefs.replySummary;
		if ([key isEqualToString:@"summary.history"]) return prefs.historySummary;
		if ([key isEqualToString:@"version"]) return SX_VERSION;
		if ([key isEqualToString:@"packageScheme"]) {
			return [@SX_SCHEME isEqualToString:@"roothide"] ? @"roothide" : @"rootless";
		}

		return [super readPreferenceValue:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"readPreferenceValue EXCEPTION (key=%@): %@ — %@",
				 [specifier propertyForKey:@"key"], exception.name, exception.reason);
		return nil;
	}
}

/// Nhãn dễ đọc cho giá trị đã lưu ("smart" → "Thông minh (khuyến nghị)").
/// Dùng để gắn vào hàng dưới dạng chú thích: ô giá trị bên phải phải là giá trị
/// thật (để Preferences vẽ ✓), còn nghĩa tiếng Việt hiện ngay dưới nhãn.
- (NSString *)sx_valueLabelForSpecifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"key"];
	id raw = [self readPreferenceValue:specifier];
	NSString *value = [raw isKindOfClass:[NSString class]] ? raw : [raw description];
	if (!value.length) return nil;
	if ([key isEqualToString:@"mode"]) {
		return [value isEqualToString:@"full"] ? @"Thay thế mọi câu" : @"Thông minh (khuyến nghị)";
	}
	if ([key isEqualToString:@"triggerMode"]) {
		return [value isEqualToString:@"prefix"] ? @"Chỉ khi nói “@ai”" : @"Tự động — mọi câu";
	}
	if ([key isEqualToString:@"provider"]) {
		return [value isEqualToString:@"gemini"] ? @"Google Gemini" : @"OpenAI / tương thích";
	}
	if ([key isEqualToString:@"timeoutAction"]) {
		if ([value isEqualToString:@"keep"]) return @"Giữ nguyên câu trả lời Siri";
		if ([value isEqualToString:@"retry"]) return @"Thử lại bằng model dự phòng";
		return @"Bubble “chưa kịp trả lời”";
	}
	return nil;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	@try {
		[super setPreferenceValue:value specifier:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"setPreferenceValue EXCEPTION (key=%@): %@ — %@",
				 [specifier propertyForKey:@"key"], exception.name, exception.reason);
	}
	// Một nguồn duy nhất: ghi xong thì phát notify; chính trang này cũng nghe
	// notify nên không làm mới hai lần cho mỗi lần bấm.
	notify_post("com.sirix.tweak/prefs.changed");
}

/// Gộp các thay đổi liên tiếp (gạt công tắc nhanh) thành một lần làm mới.
- (void)sx_scheduleTableRefresh {
	[_refreshTimer invalidate];
	_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
													target:self
												  selector:@selector(sx_applyTableRefresh)
												  userInfo:nil
												   repeats:NO];
}

- (void)sx_applyTableRefresh {
	_refreshTimer = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	@try {
		[self reload];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload EXCEPTION: %@", exception.reason);
	}
#pragma clang diagnostic pop
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"SiriX";
	@try {
		[self sx_buildHeader];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"buildHeader EXCEPTION: %@ — %@", exception.name, exception.reason);
	}

	__weak SXRootListController *weakSelf = self;
	notify_register_dispatch("com.sirix.tweak/prefs.changed", &_prefsToken,
							 dispatch_get_main_queue(), ^(int token) {
		(void)token;
		[[SXPrefs shared] reload];
		SXRootListController *strongSelf = weakSelf;
		if (!strongSelf) return;
		@try {
			[strongSelf sx_updateStatusPill];
			[strongSelf sx_refreshChoiceTrailingValues];
			[strongSelf sx_scheduleTableRefresh];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"notify handler EXCEPTION: %@", exception.reason);
		}
	});
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sx_updateStatusPill];
	[self sx_refreshChoiceTrailingValues];
}

/// Cập nhật "giá trị đang dùng" ở mép phải của các hàng chọn. Cell không tự đọc
/// prefs (nó chỉ vẽ theo specifier) nên mỗi lần quay lại trang là làm mới — nhờ
/// vậy chọn xong ở trang con là thấy ngay giá trị mới ở trang gốc.
- (void)sx_refreshChoiceTrailingValues {
	for (PSSpecifier *specifier in self.specifiers) {
		if (specifier.cellType != PSLinkListCell) continue;
		[specifier setProperty:NSClassFromString(@"SXChoiceRow") forKey:PSCellClassKey];
		[specifier setProperty:@(SXChoiceCellModeValue) forKey:SXChoiceModeKey];
		id raw = [self readPreferenceValue:specifier];
		NSString *text = [self sx_valueLabelForSpecifier:specifier];
		if (!text.length && [raw isKindOfClass:[NSString class]]) text = raw;
		[specifier setProperty:text ?: @"" forKey:SXChoiceTrailingKey];
	}
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	// Trang gốc cũng có thể trắng nếu Preferences dựng cell hỏng im lặng.
	SXShowContentFallbackIfNeeded(self, @"Cài đặt SiriX", @"không dựng được các hàng cài đặt");
}

- (void)dealloc {
	if (_prefsToken) notify_cancel(_prefsToken);
	[_refreshTimer invalidate];
}

#pragma mark - Header

- (UITableView *)sx_tableView {
	if ([self.view isKindOfClass:[UITableView class]]) return (UITableView *)self.view;
	for (UIView *subview in self.view.subviews) {
		if ([subview isKindOfClass:[UITableView class]]) return (UITableView *)subview;
	}
	return nil;
}

- (void)sx_buildHeader {
	UITableView *table = [self sx_tableView];
	if (!table) {
		SXLogWrn(@"pref", @"không tìm thấy UITableView (view=%@) — bỏ header",
				 NSStringFromClass(self.view.class));
		return;
	}

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, 178)];
	UIImage *iconImage = [UIImage imageNamed:@"SiriXIcon"
								   inBundle:[NSBundle bundleForClass:self.class]
			  compatibleWithTraitCollection:nil];
	UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
	iconView.contentMode = UIViewContentModeScaleAspectFill;
	iconView.layer.cornerRadius = 16;
	iconView.clipsToBounds = YES;
	iconView.translatesAutoresizingMaskIntoConstraints = NO;
	[iconView.widthAnchor constraintEqualToConstant:66].active = YES;
	[iconView.heightAnchor constraintEqualToConstant:66].active = YES;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"SiriX";
	titleLabel.font = [UIFont systemFontOfSize:23 weight:UIFontWeightBold];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.adjustsFontForContentSizeCategory = YES;

	UILabel *subtitleLabel = [SXUI footnoteLabel:@"Trợ lý AI ngay trong giao diện Siri"];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;

	NSString *status = [SXPrefs shared].statusSummary;
	UIColor *statusColor = [SXUI colorForStatusText:status];
	UIView *pill = [SXUI statusPillWithText:status color:statusColor];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, titleLabel, subtitleLabel, pill]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 5;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[header addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
		[stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
		[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:header.leadingAnchor constant:16],
		[stack.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-16],
	]];
	if (status.length) [stack setCustomSpacing:9 afterView:subtitleLabel];
	table.tableHeaderView = header;

	self.headerView = header;
	self.statusPill = pill;
	self.statusDot = pill.subviews.firstObject;
	self.statusLabel = pill.subviews.lastObject;
	SXLogInf(@"pref", @"header cài đặt đã gắn (icon=%d)", iconImage != nil);
}

- (void)sx_updateStatusPill {
	if (!self.statusPill || !self.statusLabel) return;
	NSString *status = [SXPrefs shared].statusSummary;
	UIColor *color = [SXUI colorForStatusText:status];
	self.statusLabel.text = status;
	self.statusLabel.textColor = color;
	self.statusDot.backgroundColor = color;
	self.statusPill.backgroundColor = [color colorWithAlphaComponent:0.14];
}

#pragma mark - Hành động

- (void)sx_resetAll:(id)sender {
	(void)sender;
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Khôi phục cài đặt mặc định?"
			message:@"Toàn bộ tuỳ chọn, khoá API và prompt tuỳ chỉnh sẽ bị xoá. Lịch sử hội thoại và log không bị ảnh hưởng."
		confirmText:@"Khôi phục"
			 action:^{
		[SXPrefs resetAll];
		[[SXPrefs shared] reload];
		notify_post("com.sirix.tweak/prefs.changed");
		[SXUI tapFeedback];
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		@try {
			strongSelf->_specifiers = nil;
			[strongSelf reloadSpecifiers];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			[strongSelf reload];
#pragma clang diagnostic pop
			[strongSelf sx_updateStatusPill];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"reset reload EXCEPTION: %@", exception.reason);
		}
	}];
}

/// Đọc `releases/latest` rồi hiện kết quả: bản mới → nút mở trang tải, đã mới
/// nhất → báo yên tâm, lỗi mạng → nói rõ chứ không im lặng.
- (void)sx_checkUpdate:(id)sender {
	(void)sender;
	__weak typeof(self) weakSelf = self;
	UIAlertController *waiting = [UIAlertController alertControllerWithTitle:@"Đang kiểm tra…"
																	message:@"Hỏi GitHub Releases bản mới nhất."
															 preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:waiting animated:YES completion:nil];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSError *error = nil;
		NSDictionary *result = [SXUpdate checkWithTimeout:10.0 error:&error];
		dispatch_async(dispatch_get_main_queue(), ^{
			[waiting dismissViewControllerAnimated:YES completion:^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				if (!result) {
					[SXUI alertOn:strongSelf
							 title:@"Không kiểm tra được"
						   message:error.localizedDescription ?: @"Không rõ lỗi."];
					return;
				}
				NSString *latest = result[@"latest"];
				if (![result[@"newer"] boolValue]) {
					[SXUI alertOn:strongSelf
							 title:@"Đã là bản mới nhất"
						   message:[NSString stringWithFormat:
									@"SiriX %@ là bản mới nhất trên GitHub Releases.",
									result[@"current"] ?: SX_VERSION]];
					return;
				}
				NSString *urlString = result[@"url"];
				[SXUI confirmOn:strongSelf
						  title:[NSString stringWithFormat:@"Có bản mới %@", latest]
						message:[NSString stringWithFormat:
								 @"Bạn đang dùng %@. Mở trang phát hành để tải gói rootless "
								 @"hoặc roothide mới và cài lại bằng Sileo/Zebra.",
								 result[@"current"] ?: SX_VERSION]
					confirmText:@"Mở trang phát hành"
						 action:^{
					NSURL *url = [NSURL URLWithString:[urlString isKindOfClass:NSString.class]
													  ? urlString : @""];
					if (url) {
						[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
					}
				}];
			}];
		});
	});
}

/// Nút thoát khỏi bảng dự phòng: xoá cache specifier rồi dựng lại từ plist.
- (void)sx_reloadTable:(id)sender {
	(void)sender;
	SXLogInf(@"pref", @"người dùng yêu cầu tải lại bảng cài đặt");
	_specifiers = nil;
	@try {
		[self reloadSpecifiers];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[self reload];
#pragma clang diagnostic pop
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"tải lại bảng EXCEPTION: %@ — %@", exception.name, exception.reason);
		[SXUI alertOn:self title:@"Vẫn không tải được"
			  message:[NSString stringWithFormat:@"%@. Gửi log để mình xem chi tiết.",
					   exception.reason ?: @"không rõ lỗi"]];
	}
}

- (void)sx_respring:(id)sender {
	(void)sender;
	[SXUI confirmOn:self
			  title:@"Khởi động lại SpringBoard?"
			message:@"Màn hình sẽ tối khoảng vài giây. Cài đặt đã lưu, không mất dữ liệu."
		confirmText:@"Khởi động lại"
			 action:^{
		SXLogInf(@"pref", @"người dùng yêu cầu khởi động lại SpringBoard");
		notify_post("com.sirix.respring");
	}];
}

@end
