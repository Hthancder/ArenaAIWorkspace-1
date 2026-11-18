#import "SXUISupport.h"

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

@end
