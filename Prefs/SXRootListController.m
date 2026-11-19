#import "SXRootListController.h"
#import "SXLogViewController.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
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

@interface SXRootListController ()
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusDot;
@end

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
		if (!loaded.count) {
			// Bảng dự phòng tối giản — Settings không được để trống hoặc crash.
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Không tải được bảng cài đặt. Mở “Xem & sao chép log” để lấy log gửi lại."
					  forKey:@"footerText"];
			PSSpecifier *log = [PSSpecifier preferenceSpecifierNamed:@"Xem & sao chép log"
															 target:self
																set:NULL
																get:NULL
															 detail:NSClassFromString(@"SXLogViewController")
															   cell:PSLinkCell
															   edit:nil];
			loaded = [NSMutableArray arrayWithObjects:group, log, nil];
		}
		_specifiers = loaded;
		SXLogInf(@"pref", @"bảng cài đặt sẵn sàng: %lu specifier", (unsigned long)loaded.count);
	}
	return _specifiers;
}

#pragma mark - Giá trị động

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	@try {
		NSString *key = [specifier propertyForKey:@"key"];
		SXPrefs *prefs = [SXPrefs shared];

		if ([key isEqualToString:@"toolsDisplay"]) {
			NSArray *tools = [SXTools catalog];
			NSUInteger enabled = 0;
			for (SXTool *tool in tools) {
				if ([prefs isToolEnabled:tool.name]) enabled++;
			}
			if (!tools.count) return @"Chưa cài công cụ nào";
			return [NSString stringWithFormat:@"%lu/%lu · %ld vòng",
					(unsigned long)enabled, (unsigned long)tools.count, (long)prefs.maxToolRounds];
		}
		if ([key isEqualToString:@"summary.status"]) return prefs.statusSummary;
		if ([key isEqualToString:@"summary.provider"]) return prefs.providerSummary;
		if ([key isEqualToString:@"summary.reply"]) return prefs.replySummary;
		if ([key isEqualToString:@"summary.history"]) return prefs.historySummary;
		if ([key isEqualToString:@"version"]) return SX_VERSION;
		if ([key isEqualToString:@"packageScheme"]) return @SX_SCHEME;
		if ([key isEqualToString:@"status"]) return prefs.statusSummary;

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
	// Một nguồn duy nhất: ghi xong thì phát notify; chính trang này cũng nghe notify
	// nên không cần làm mới ở đây (tránh refresh hai lần cho mỗi lần bấm).
	notify_post("com.sirix.tweak/prefs.changed");
}

/// Gộp các thay đổi liên tiếp (kéo slider) thành một lần làm mới duy nhất.
- (void)sx_scheduleTableRefresh {
	[NSObject cancelPreviousPerformRequestsWithTarget:self
											 selector:@selector(sx_applyTableRefresh)
											   object:nil];
	[self performSelector:@selector(sx_applyTableRefresh) withObject:nil afterDelay:0.2];
}

- (void)sx_applyTableRefresh {
	@try {
		[self reload];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload EXCEPTION: %@", exception.reason);
	}
	@try {
		UITableView *table = self.tableView ?: ([self.view isKindOfClass:[UITableView class]]
											   ? (UITableView *)self.view : nil);
		[table reloadData];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reloadData EXCEPTION: %@", exception.reason);
	}
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	SXLogInf(@"pref", @"viewDidLoad — start");
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
			// Cấu trúc bảng không đổi — chỉ đọc lại giá trị, gộp nhiều thay đổi liên tiếp.
			[strongSelf sx_scheduleTableRefresh];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"notify handler EXCEPTION: %@", exception.reason);
		}
	});
	SXLogInf(@"pref", @"viewDidLoad — xong");
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sx_updateStatusPill];
}

- (void)dealloc {
	if (_prefsToken) notify_cancel(_prefsToken);
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

	CGFloat width = UIScreen.mainScreen.bounds.size.width;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 178)];

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

	UILabel *subtitleLabel = [SXUI footnoteLabel:@"Trợ lý AI ngay trong giao diện Siri"];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;

	SXPrefs *prefs = [SXPrefs shared];
	NSString *status = prefs.statusSummary;
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
	SXLogInf(@"pref", @"header cài đặt đã gắn (icon=%d, table=%@)", iconImage != nil,
			 NSStringFromClass([table class]));
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
			message:@"Toàn bộ tuỳ chọn, khóa API và prompt tuỳ chỉnh sẽ bị xoá. Lịch sử hội thoại và log không bị ảnh hưởng."
		confirmText:@"Khôi phục"
			 action:^{
		[SXPrefs resetAll];
		[[SXPrefs shared] reload];
		notify_post("com.sirix.tweak/prefs.changed");
		[SXUI tapFeedback];
		typeof(self) strongSelf = weakSelf;
		if (strongSelf) {
			@try {
				strongSelf->_specifiers = nil;
				[strongSelf reloadSpecifiers];
				[strongSelf sx_updateStatusPill];
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"reset reload EXCEPTION: %@", exception.reason);
			}
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

- (void)sx_resetHistory:(id)sender {
	(void)sender;
	notify_post("com.sirix.tweak/resetHistory");
	[SXUI alertOn:self title:@"Đã xoá ngữ cảnh" message:@"Các câu hỏi/trả lời trước đó đã được xoá khỏi bộ nhớ của SiriX."];
}

@end
