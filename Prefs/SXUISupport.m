#import "SXUISupport.h"
#import "SXLog.h"
#import "SXLogFile.h"
#import "UIViewController+SXBack.h"

@implementation SXUI

#pragma mark - Màu

+ (UIColor *)accentColor {
	return [UIColor colorWithRed:0.35 green:0.34 blue:0.84 alpha:1.0];
}

+ (UIColor *)successColor {
	return [UIColor systemGreenColor];
}

+ (UIColor *)warningColor {
	return [UIColor systemOrangeColor];
}

+ (UIColor *)dangerColor {
	return [UIColor systemRedColor];
}

+ (UIColor *)cardColor {
	if (@available(iOS 13.0, *)) return [UIColor secondarySystemGroupedBackgroundColor];
	return [UIColor whiteColor];
}

+ (UIColor *)colorForStatusText:(NSString *)text {
	NSString *lower = [text lowercaseString] ?: @"";
	if ([lower isEqualToString:@"đã tắt"] || [lower rangeOfString:@"chưa kiểm tra"].location != NSNotFound)
		return [UIColor secondaryLabelColor];
	if ([lower containsString:@"sẵn sàng"] || [lower containsString:@"hoạt động"]) return [self successColor];
	if ([lower containsString:@"khóa"] || [lower containsString:@"chưa"] || [lower containsString:@"thiếu"]) return [self warningColor];
	if ([lower containsString:@"tắt"] || [lower containsString:@"lỗi"] || [lower containsString:@"thất bại"]) return [self dangerColor];
	return [UIColor secondaryLabelColor];
}

#pragma mark - Thành phần

+ (UIView *)statusPillWithText:(NSString *)text color:(UIColor *)color {
	UIView *pill = [[UIView alloc] init];
	pill.translatesAutoresizingMaskIntoConstraints = NO;
	pill.backgroundColor = [color colorWithAlphaComponent:0.14];
	pill.layer.cornerRadius = 11;
	if (@available(iOS 13.0, *)) pill.layer.cornerCurve = kCACornerCurveContinuous;

	UIView *dot = [[UIView alloc] init];
	dot.translatesAutoresizingMaskIntoConstraints = NO;
	dot.backgroundColor = color;
	dot.layer.cornerRadius = 4;
	[dot.widthAnchor constraintEqualToConstant:8].active = YES;
	[dot.heightAnchor constraintEqualToConstant:8].active = YES;

	UILabel *label = [[UILabel alloc] init];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = text;
	label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
	label.textColor = color;
	label.numberOfLines = 1;

	[pill addSubview:dot];
	[pill addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[dot.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
		[dot.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
		[label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6],
		[label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10],
		[label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
		[label.topAnchor constraintGreaterThanOrEqualToAnchor:pill.topAnchor constant:4],
		[label.bottomAnchor constraintLessThanOrEqualToAnchor:pill.bottomAnchor constant:-4],
		[pill.heightAnchor constraintGreaterThanOrEqualToConstant:22],
	]];
	return pill;
}

+ (UILabel *)footnoteLabel:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	label.textColor = [UIColor secondaryLabelColor];
	label.numberOfLines = 0;
	return label;
}

+ (UIView *)emptyStateWithSymbol:(NSString *)symbol title:(NSString *)title message:(NSString *)message {
	UIView *container = [[UIView alloc] init];

	UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
	icon.tintColor = [UIColor tertiaryLabelColor];
	icon.contentMode = UIViewContentModeScaleAspectFit;
	[icon.heightAnchor constraintEqualToConstant:44].active = YES;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = title;
	titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	titleLabel.textColor = [UIColor labelColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.numberOfLines = 0;

	UILabel *messageLabel = [[UILabel alloc] init];
	messageLabel.text = message;
	messageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	messageLabel.textColor = [UIColor secondaryLabelColor];
	messageLabel.textAlignment = NSTextAlignmentCenter;
	messageLabel.numberOfLines = 0;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, titleLabel, messageLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 10;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-24],
		[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:32],
		[stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-32],
		[messageLabel.widthAnchor constraintLessThanOrEqualToConstant:300],
	]];
	return container;
}

#pragma mark - Alert

+ (BOOL)canPresentOn:(UIViewController *)controller {
	return controller != nil && controller.isViewLoaded && controller.view.window != nil &&
		   controller.presentedViewController == nil;
}

+ (void)alertOn:(UIViewController *)controller title:(NSString *)title message:(NSString *)message {
	if (!controller) return;
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self alertOn:controller title:title message:message];
		});
		return;
	}
	if (![self canPresentOn:controller]) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[controller presentViewController:alert animated:YES completion:nil];
}

+ (void)confirmOn:(UIViewController *)controller
			title:(NSString *)title
		  message:(NSString *)message
	  confirmText:(NSString *)confirmText
		   action:(void (^)(void))action {
	if (!controller || !action) return;
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self confirmOn:controller title:title message:message confirmText:confirmText action:action];
		});
		return;
	}
	if (![self canPresentOn:controller]) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:confirmText
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *item) {
		(void)item;
		action();
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[controller presentViewController:alert animated:YES completion:nil];
}

+ (void)tapFeedback {
	if (![NSThread isMainThread]) return;
	UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[generator impactOccurred];
}

#pragma mark - Định dạng

+ (NSString *)relativeStringForDate:(NSDate *)date {
	if (![date isKindOfClass:[NSDate class]]) return @"";
	NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
	timeFormatter.timeStyle = NSDateFormatterShortStyle;
	timeFormatter.dateStyle = NSDateFormatterNoStyle;
	NSString *time = [timeFormatter stringFromDate:date];

	NSCalendar *calendar = [NSCalendar currentCalendar];
	if ([calendar isDateInToday:date]) return [@"Hôm nay " stringByAppendingString:time];
	if ([calendar isDateInYesterday:date]) return [@"Hôm qua " stringByAppendingString:time];

	NSDateFormatter *dayFormatter = [[NSDateFormatter alloc] init];
	dayFormatter.dateStyle = NSDateFormatterShortStyle;
	dayFormatter.timeStyle = NSDateFormatterNoStyle;
	return [NSString stringWithFormat:@"%@ %@", [dayFormatter stringFromDate:date], time];
}

+ (NSString *)truncate:(NSString *)text limit:(NSUInteger)limit {
	if (![text isKindOfClass:[NSString class]]) return @"";
	if (text.length <= limit || limit == 0) return text;
	return [[text substringToIndex:limit] stringByAppendingString:@"…"];
}

+ (BOOL)copyText:(NSString *)text {
	if (![text isKindOfClass:[NSString class]] || !text.length) return NO;
	[UIPasteboard generalPasteboard].string = text;
	[self tapFeedback];
	return YES;
}

+ (NSString *)groupedNumber:(NSInteger)value {
	static NSNumberFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSNumberFormatter alloc] init];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.groupingSeparator = @" ";
		formatter.usesGroupingSeparator = YES;
	});
	return [formatter stringFromNumber:@(value)] ?: [NSString stringWithFormat:@"%ld", (long)value];
}

#pragma mark - Lưới an toàn cho trang con

/// Thẻ của khối dự phòng. Đặt số lạ để không đụng tag của PreferenceLoader.
static const NSInteger SXContentFallbackTag = 0x5EEDF001;

/// Bảng có ít nhất một hàng chưa? Hỏi qua `dataSource` thay vì
/// `visibleCells`: trang vừa mở có thể chưa layout nên `visibleCells` rỗng dù
/// dữ liệu đã có, và ta sẽ chèn khối dự phòng đè lên nội dung thật.
static BOOL SXTableHasRows(UITableView *table) {
	if (!table) return NO;
	NSInteger sections = table.numberOfSections;
	if (sections <= 0) return NO;
	@try {
		for (NSInteger section = 0; section < sections; section++) {
			if ([table.dataSource tableView:table numberOfRowsInSection:section] > 0) return YES;
		}
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"đếm hàng bảng: %@ — %@", exception.name, exception.reason);
		// Không đếm được thì coi như có nội dung: thà bỏ sót một trang trống còn
		// hơn che mất một trang đang chạy tốt.
		return YES;
	}
	return NO;
}

/// Trang có nội dung nhìn thấy được không? Đếm hàng của mọi UITableView đang
/// hiện, rồi tới các nhãn có chữ. Màn hình chỉ có nền và thanh điều hướng bị
/// coi là trống. `ignoreTag` bỏ qua chính khối dự phòng (nếu không thì lần kiểm
/// tra sau sẽ thấy nhãn của nó và tưởng trang đã có nội dung).
/// Nút "Sao chép log" của khối dự phòng đang chạy việc nặng.
///
/// Trước đây nó đọc **toàn bộ** tệp log (tới 512 KB, hoặc 1 MB sau khi thêm
/// xoay vòng giữa phiên) bằng `stringWithContentsOfFile:` ngay trong action —
/// tức là trên luồng chính của Preferences, đúng lúc người dùng đang cần thoát
/// khỏi một màn hình hỏng. Nay đọc phần đuôi trên luồng nền (cùng hàm với màn
/// Nhật ký), giới hạn 160 KB, rồi mới sao chép trên luồng chính.
static void SXCopyLogTailAsync(UILabel *detailLabel) {
	__weak UILabel *weakDetail = detailLabel;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		char *buffer = malloc(160 * 1024 + 1);
		NSString *text = nil;
		if (buffer) {
			off_t size = 0;
			int truncated = 0;
			ssize_t got = SXLogFileReadTail(SXLogFilePath().fileSystemRepresentation,
											buffer, 160 * 1024, &size, &truncated);
			if (got > 0) {
				text = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)got encoding:NSUTF8StringEncoding];
				if (!text) text = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)got
													  encoding:NSISOLatin1StringEncoding];
				if (text.length && truncated) text = [@"(đã cắt phần đầu)\n" stringByAppendingString:text];
			}
			free(buffer);
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			UILabel *label = weakDetail;
			if (!text.length) {
				if (label) label.text = [NSString stringWithFormat:@"Không đọc được %@", SXLogFilePath()];
				return;
			}
			if (![SXUI copyText:text] && label) label.text = @"Không có nội dung log để sao chép.";
		});
	});
}

static BOOL SXHasVisibleContentIgnoringTag(UIView *view, NSInteger ignoreTag) {
	if (!view) return NO;
	// `PSListController` dùng chính `view` làm bảng ⇒ phải xét cả gốc, không chỉ
	// các view con.
	if ([view isKindOfClass:[UITableView class]] && SXTableHasRows((UITableView *)view)) return YES;
	for (UIView *subview in view.subviews) {
		if (ignoreTag != 0 && subview.tag == ignoreTag) continue;
		if ([subview isKindOfClass:[UITableView class]]) {
			UITableView *table = (UITableView *)subview;
			if (SXTableHasRows(table)) return YES;
			// Bảng 0 hàng vẫn có thể đang hiện `backgroundView` (trạng thái rỗng) —
			// trừ khi chính nó là khối dự phòng đang được bỏ qua.
			if (table.backgroundView && !table.backgroundView.hidden &&
				(ignoreTag == 0 || table.backgroundView.tag != ignoreTag)) return YES;
			continue;
		}
		if ([subview isKindOfClass:[UILabel class]]) {
			UILabel *label = (UILabel *)subview;
			if (!label.hidden && label.alpha > 0.01 && label.text.length) return YES;
		}
		if ([subview isKindOfClass:[UITextView class]] || [subview isKindOfClass:[UITextField class]]) {
			if (!subview.hidden && subview.alpha > 0.01) return YES;
		}
		if ([subview isKindOfClass:[UIControl class]] && !subview.hidden) return YES;
		if ([subview isKindOfClass:[UIScrollView class]] && !subview.hidden &&
			subview.subviews.count > 0) return YES;
		if (SXHasVisibleContentIgnoringTag(subview, ignoreTag)) return YES;
	}
	return NO;
}

static BOOL SXHasVisibleContent(UIView *view) {
	return SXHasVisibleContentIgnoringTag(view, 0);
}

/// Khối dự phòng đang hiện, nếu có. Với `PSListController` nó nằm ở
/// `backgroundView` chứ không phải view con, nên tìm cả hai chỗ.
static UIView *SXContentFallbackView(UIView *view) {
	UIView *found = [view viewWithTag:SXContentFallbackTag];
	if (found) return found;
	if ([view isKindOfClass:[UITableView class]]) {
		UITableView *table = (UITableView *)view;
		if (table.backgroundView.tag == SXContentFallbackTag) return table.backgroundView;
		// Trang tự dựng bảng con: khối có thể nằm trong backgroundView của bảng đó.
		for (UIView *subview in view.subviews) {
			if (![subview isKindOfClass:[UITableView class]]) continue;
			UITableView *inner = (UITableView *)subview;
			if (inner.backgroundView.tag == SXContentFallbackTag) return inner.backgroundView;
		}
	}
	return nil;
}

BOOL SXShowContentFallbackIfNeeded(UIViewController *controller, NSString *title, NSString *reason) {
	if (!controller || !controller.isViewLoaded) return NO;
	if (![NSThread isMainThread]) return NO;
	UIView *view = controller.view;
	if (!view) return NO;
	// Đã chèn rồi thì thôi (viewDidAppear có thể chạy lại).
	if (SXContentFallbackView(view)) return YES;
	if (SXHasVisibleContent(view)) return NO;

	SXLogErr(@"pref", @"trang %@ TRỐNG — hiện chỗ trống dự phòng (%@)",
			 title.length ? title : NSStringFromClass(controller.class), reason ?: @"không rõ");

	UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
	container.tag = SXContentFallbackTag;
	container.translatesAutoresizingMaskIntoConstraints = NO;
	container.backgroundColor = UIColor.systemGroupedBackgroundColor;

	UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle"]];
	icon.tintColor = [SXUI warningColor];
	icon.contentMode = UIViewContentModeScaleAspectFit;
	[icon.widthAnchor constraintEqualToConstant:34].active = YES;
	[icon.heightAnchor constraintEqualToConstant:34].active = YES;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = title.length ? [NSString stringWithFormat:@"%@ chưa hiện được", title] : @"Trang chưa hiện được";
	titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.numberOfLines = 0;

	NSString *detail = [NSString stringWithFormat:@"Lý do: %@.\nBản %@ · %@",
						reason.length ? reason : @"không có nội dung",
						SX_VERSION,
						[NSProcessInfo.processInfo.operatingSystemVersionString stringByReplacingOccurrencesOfString:@"Version " withString:@""]];
	UILabel *detailLabel = [SXUI footnoteLabel:detail];
	detailLabel.textAlignment = NSTextAlignmentCenter;
	detailLabel.numberOfLines = 0;

	UIButton *logButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[logButton setTitle:@"Sao chép log để gửi lại" forState:UIControlStateNormal];
	logButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	[logButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
		(void)action;
		SXCopyLogTailAsync(detailLabel);
	}] forControlEvents:UIControlEventTouchUpInside];

	UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[backButton setTitle:@"Quay lại" forState:UIControlStateNormal];
	backButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	// `controller` giữ `view` giữ nút giữ block ⇒ phải tham chiếu yếu, nếu không
	// màn hình không bao giờ được giải phóng.
	__weak UIViewController *weakBackTarget = controller;
	[backButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
		(void)action;
		UIViewController *target = weakBackTarget;
		if (!target) return;
		if ([target respondsToSelector:@selector(sx_goBack:)]) {
			SEL selector = @selector(sx_goBack:);
			void (*goBack)(id, SEL, id) = (void (*)(id, SEL, id))[target methodForSelector:selector];
			if (goBack) goBack(target, selector, nil);
		} else if (target.navigationController.viewControllers.count > 1) {
			[target.navigationController popViewControllerAnimated:YES];
		} else {
			[target dismissViewControllerAnimated:YES completion:nil];
		}
	}] forControlEvents:UIControlEventTouchUpInside];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, titleLabel, detailLabel, logButton, backButton]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 12;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
		[stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
		[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28],
		[stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28],
	]];

	if ([view isKindOfClass:[UITableView class]]) {
		// Gốc là bảng: gắn làm `backgroundView` để khối đứng yên, không cuộn theo
		// nội dung và không bị gỡ khi bảng reload.
		container.translatesAutoresizingMaskIntoConstraints = YES;
		container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		container.frame = view.bounds;
		((UITableView *)view).backgroundView = container;
	} else {
		[view addSubview:container];
		[NSLayoutConstraint activateConstraints:@[
			[container.topAnchor constraintEqualToAnchor:view.topAnchor],
			[container.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
			[container.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
			[container.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
		]];
	}

	// Dữ liệu có thể về muộn (đọc đĩa/mạng ở luồng nền). Kiểm tra lại vài lần:
	// nội dung thật xuất hiện thì gỡ khối này, đừng che mất trang.
	for (NSNumber *delay in @[@1.5, @4.0, @9.0]) {
		__weak UIViewController *weakController = controller;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
									  (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
					   dispatch_get_main_queue(), ^{
			UIViewController *strongController = weakController;
			if (!strongController || !strongController.isViewLoaded) return;
			UIView *current = strongController.view;
			UIView *placeholder = SXContentFallbackView(current);
			if (!placeholder) return;
			if (!SXHasVisibleContentIgnoringTag(current, SXContentFallbackTag)) return;
			SXLogInf(@"pref", @"trang %@ đã có nội dung — gỡ khối dự phòng", title ?: @"?");
			if ([current isKindOfClass:[UITableView class]] &&
				((UITableView *)current).backgroundView == placeholder) {
				((UITableView *)current).backgroundView = nil;
			}
			[placeholder removeFromSuperview];
		});
	}
	return YES;
}

@end
