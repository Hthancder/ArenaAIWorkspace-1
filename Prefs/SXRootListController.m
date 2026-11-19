#import "SXPrefs.h"
#import "SXRootListController.h"
#import "SXLogViewController.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXTools.h"
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

/// Các key số dùng slider trên giao diện cũ nhưng người dùng thật sự chỉ cần
/// vài mức (“chờ 10 giây” chứ không phải 11,4 giây). Trang gốc thay slider
/// bằng danh sách mức cố định cho dễ bấm và dễ hiểu.
static NSArray<NSString *> *SXTemperatureTitles(void) {
	return @[@"0.0 · máy móc, ít sáng tạo",
			 @"0.3 · bám sát câu hỏi",
			 @"0.7 · cân bằng (khuyến nghị)",
			 @"1.0 · sáng tạo vừa",
			 @"1.5 · rất sáng tạo, dễ lan man"];
}
static NSArray<NSNumber *> *SXTemperatureValues(void) {
	return @[@0.0, @0.3, @0.7, @1.0, @1.5];
}
static NSArray<NSString *> *SXContextTitles(void) {
	return @[@"2 câu · ngắn nhất, nhanh nhất",
			 @"4 câu · đủ cho hội thoại ngắn",
			 @"8 câu · cân bằng (khuyến nghị)",
			 @"16 câu · hội thoại dài",
			 @"30 câu · nhớ lâu, tốn token"];
}
static NSArray<NSNumber *> *SXContextValues(void) {
	return @[@2, @4, @8, @16, @30];
}
static NSArray<NSString *> *SXTimeoutTitles(void) {
	return @[@"6 giây · chỉ model thật nhanh",
			 @"10 giây · cân bằng (khuyến nghị)",
			 @"15 giây · model lớn / mạng chậm",
			 @"20 giây · kiên nhẫn",
			 @"30 giây · giữ luồng Siri lâu"];
}
static NSArray<NSNumber *> *SXTimeoutValues(void) {
	return @[@6, @10, @15, @20, @30];
}
static NSArray<NSString *> *SXToolRoundTitles(void) {
	return @[@"1 vòng · nhanh nhất",
			 @"2 vòng · đủ cho hầu hết câu",
			 @"3 vòng · mặc định",
			 @"4 vòng · câu hỏi nhiều bước"];
}
static NSArray<NSNumber *> *SXToolRoundValues(void) {
	return @[@1, @2, @3, @4];
}

#pragma mark - Bộ chọn mức
/// Danh sách mức cố định cho một key số. Cell vẫn khai báo `PSLinkListCell`
/// trong plist nhưng các mục do lớp này cung cấp (không dùng
/// PSListItemsController) để tiêu đề đọc được ngay trong danh sách.
@interface SXChoiceController : PSListController
@property (nonatomic, copy) NSString *prefsKey;
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
}

- (NSArray<NSNumber *> *)values {
	if ([self.prefsKey isEqualToString:@"temperature"]) return SXTemperatureValues();
	if ([self.prefsKey isEqualToString:@"contextTurns"]) return SXContextValues();
	if ([self.prefsKey isEqualToString:@"timeout"]) return SXTimeoutValues();
	if ([self.prefsKey isEqualToString:@"maxToolRounds"]) return SXToolRoundValues();
	return @[];
}

- (NSArray<NSString *> *)titlesForValues {
	if ([self.prefsKey isEqualToString:@"temperature"]) return SXTemperatureTitles();
	if ([self.prefsKey isEqualToString:@"contextTurns"]) return SXContextTitles();
	if ([self.prefsKey isEqualToString:@"timeout"]) return SXTimeoutTitles();
	if ([self.prefsKey isEqualToString:@"maxToolRounds"]) return SXToolRoundTitles();
	return @[];
}

- (double)sx_currentValue {
	SXPrefs *prefs = [SXPrefs shared];
	if ([self.prefsKey isEqualToString:@"temperature"]) return prefs.temperature;
	if ([self.prefsKey isEqualToString:@"contextTurns"]) return (double)prefs.contextTurns;
	if ([self.prefsKey isEqualToString:@"timeout"]) return prefs.responseTimeout;
	if ([self.prefsKey isEqualToString:@"maxToolRounds"]) return (double)prefs.maxToolRounds;
	return 0;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *items = [NSMutableArray array];
		PSSpecifier *group = [PSSpecifier groupSpecifierWithName:self.title];
		group.cellType = PSGroupCell;
		[items addObject:group];
		NSArray<NSNumber *> *values = [self values];
		NSArray<NSString *> *titles = [self titlesForValues];
		double current = [self sx_currentValue];
		NSUInteger best = 0;
		double bestDelta = DBL_MAX;
		for (NSUInteger i = 0; i < values.count && i < titles.count; i++) {
			double delta = fabs(values[i].doubleValue - current);
			if (delta < bestDelta) { bestDelta = delta; best = i; }
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:titles[i]
															  target:self
																 set:@selector(sx_pick:specifier:)
																 get:nil
															  detail:nil
																cell:PSListItemCell
																edit:nil];
			[row setProperty:@(i) forKey:@"sxIndex"];
			// Dấu ✓ đặt qua property "value": PSTableCell tự hiển thị.
			[row setProperty:i == best ? @"✓" : @"" forKey:PSValueKey];
			[items addObject:row];
		}
		_specifiers = items;
	}
	return _specifiers;
}

- (void)sx_pick:(PSSpecifier *)row specifier:(PSSpecifier *)group {
	(void)group;
	NSNumber *index = [row propertyForKey:@"sxIndex"];
	NSArray<NSNumber *> *values = [self values];
	if (![index isKindOfClass:[NSNumber class]] || index.unsignedIntegerValue >= values.count) return;
	[SXPrefs setValue:values[index.unsignedIntegerValue] forKey:self.prefsKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	[self.navigationController popViewControllerAnimated:YES];
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
		NSMutableArray *loaded = nil;
		@try {
			loaded = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"loadSpecifiers EXCEPTION: %@ — %@", exception.name, exception.reason);
			loaded = nil;
		}
		if (!loaded.count) {
			// Settings không được để trống hoặc crash: bảng dự phòng tối giản.
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Không tải được bảng cài đặt. Mở “Xem & sao chép log” để lấy log gửi lại."
					   forKey:@"footerText"];
			PSSpecifier *log = [PSSpecifier preferenceSpecifierNamed:@"Xem & sao chép log"
															  target:self set:NULL get:NULL
															  detail:NSClassFromString(@"SXLogViewController")
																cell:PSLinkCell edit:nil];
			loaded = [NSMutableArray arrayWithObjects:group, log, nil];
		}
		_specifiers = [self sx_applyChoiceDetails:loaded];
		// Đọc lại toàn bộ prefs một lần trước khi vẽ: tránh hàng “Tổng quan” hiện
		// giá trị cũ do CFPreferences chưa đồng bộ từ tiến trình khác.
		[[SXPrefs shared] reload];
		SXLogInf(@"pref", @"bảng cài đặt sẵn sàng: %lu specifier", (unsigned long)_specifiers.count);
	}
	return _specifiers;
}

/// Trỏ các cell số sang bộ chọn mức cố định và gắn footer ngắn giải thích.
- (NSMutableArray *)sx_applyChoiceDetails:(NSMutableArray *)specifiers {
	NSDictionary<NSString *, Class> *choosers = @{
		@"temperature": [SXChoiceController class],
		@"contextTurns": [SXChoiceController class],
		@"timeout": [SXChoiceController class],
		@"maxToolRounds": [SXChoiceController class],
	};
	for (PSSpecifier *specifier in specifiers) {
		NSString *key = [specifier propertyForKey:@"key"];
		Class chooser = choosers[key];
		if (!chooser) continue;
		[specifier setProperty:chooser forKey:@"detail"];
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
		if ([key isEqualToString:@"mode"]) {
			return prefs.mode == SXReplyModeFull ? @"Thay thế mọi câu" : @"Thông minh";
		}
		if ([key isEqualToString:@"triggerMode"]) {
			return [prefs.triggerMode isEqualToString:@"prefix"] ? @"Tiền tố @ai" : @"Tự động";
		}
		if ([key isEqualToString:@"provider"]) {
			return prefs.provider == SXProviderGemini ? @"Google Gemini" : @"OpenAI tương thích";
		}
		if ([key isEqualToString:@"timeoutAction"]) {
			return [prefs.timeoutAction isEqualToString:@"keep"] ? @"Giữ Siri gốc" : @"Bubble “chưa kịp”";
		}
		if ([key isEqualToString:@"temperature"]) {
			return [NSString stringWithFormat:@"%.1f", prefs.temperature];
		}
		if ([key isEqualToString:@"contextTurns"]) {
			return [NSString stringWithFormat:@"%ld câu", (long)prefs.contextTurns];
		}
		if ([key isEqualToString:@"timeout"]) {
			return [NSString stringWithFormat:@"%.0f giây", prefs.responseTimeout];
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
			[strongSelf sx_scheduleTableRefresh];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"notify handler EXCEPTION: %@", exception.reason);
		}
	});
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sx_updateStatusPill];
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
