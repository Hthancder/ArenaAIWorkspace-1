#import "SXChoiceRow.h"
#import "PSSpecifier.h"
#import "SXUISupport.h"

NSString *const SXChoiceActiveKey = @"sxChoiceActive";
NSString *const SXChoiceTrailingKey = @"sxChoiceTrailing";
NSString *const SXChoiceHintKey = @"sxChoiceHint";
NSString *const SXChoiceModeKey = @"sxChoiceMode";

static const NSInteger SXChoiceCheckTag = 0x5EEDF003;
static const NSInteger SXChoiceTrailingTag = 0x5EEDF004;

@implementation SXChoiceRow

+ (instancetype)cellForTable:(UITableView *)tableView specifier:(PSSpecifier *)specifier {
	SXChoiceRow *cell = [tableView dequeueReusableCellWithIdentifier:@"sxChoiceRow"];
	if (!cell) {
		cell = [[self alloc] initWithStyle:UITableViewCellStyleDefault
						   reuseIdentifier:@"sxChoiceRow"
								 specifier:specifier];
	}
	cell.specifier = specifier;
	[cell refreshCellContentsWithSpecifier:specifier];
	return cell;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
			  reuseIdentifier:(NSString *)reuseIdentifier
					specifier:(PSSpecifier *)specifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
	if (!self) return nil;
	self.tintColor = [SXUI accentColor];
	self.selectionStyle = UITableViewCellSelectionStyleDefault;

	self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.titleLabel.adjustsFontForContentSizeCategory = YES;
	self.titleLabel.numberOfLines = 0;
	// Nhãn phải co lại nhường chỗ cho giá trị bên phải, nếu không chuỗi dài
	// ("OpenAI / tương thích", "Bubble “chưa kịp trả lời”") sẽ đè lên nhau.
	[self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
													 forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *trailing = [[UILabel alloc] init];
	trailing.tag = SXChoiceTrailingTag;
	trailing.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	trailing.textColor = UIColor.secondaryLabelColor;
	trailing.textAlignment = NSTextAlignmentRight;
	trailing.adjustsFontForContentSizeCategory = YES;
	trailing.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:trailing];
	[NSLayoutConstraint activateConstraints:@[
		[trailing.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
		[trailing.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[trailing.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor constant:8],
	]];

	UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
	check.tag = SXChoiceCheckTag;
	check.tintColor = [SXUI accentColor];
	check.hidden = YES;
	check.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:check];
	[NSLayoutConstraint activateConstraints:@[
		[check.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
		[check.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[check.widthAnchor constraintEqualToConstant:18],
		[check.heightAnchor constraintEqualToConstant:18],
	]];
	return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	[super refreshCellContentsWithSpecifier:specifier];
	PSSpecifier *source = specifier ?: self.specifier;
	if (!source) return;

	self.titleLabel.text = source.name;
	self.titleLabel.textColor = UIColor.labelColor;

	SXChoiceCellMode mode = (SXChoiceCellMode)[[source propertyForKey:SXChoiceModeKey] integerValue];
	BOOL active = [[source propertyForKey:SXChoiceActiveKey] boolValue];
	NSString *trailingText = [source propertyForKey:SXChoiceTrailingKey];
	NSString *hint = [source propertyForKey:SXChoiceHintKey];

	UILabel *trailing = (UILabel *)[self.contentView viewWithTag:SXChoiceTrailingTag];
	UIImageView *check = (UIImageView *)[self.contentView viewWithTag:SXChoiceCheckTag];

	if (mode == SXChoiceCellModeValue) {
		check.hidden = YES;
		trailing.hidden = !trailingText.length;
		trailing.text = trailingText;
		self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		self.accessibilityValue = trailingText;
		self.accessibilityHint = hint;
	} else {
		trailing.hidden = YES;
		trailing.text = nil;
		check.hidden = !active;
		self.accessoryType = UITableViewCellAccessoryNone;
		self.accessibilityValue = active ? @"Đang chọn" : nil;
		self.accessibilityHint = hint;
	}
}

@end
