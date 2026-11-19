#import "SXToolsController.h"
#import "SXUISupport.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXToolkit.h"
#import "SXTools.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#pragma mark - Ô công cụ

/// Ô hai dòng: tên tiếng Việt + mô tả, phụ đề là tên kỹ thuật (đúng tên model
/// nhìn thấy) và công tắc. Tự vẽ thay vì PSSpecifier để mô tả xuống dòng được —
/// danh sách công cụ mà chỉ có một dòng cắt cụt thì người dùng không hiểu nó làm gì.
@interface SXToolCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, copy) NSString *toolName;
@end

@implementation SXToolCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.backgroundColor = [SXUI cardColor];

	_titleLabel = [[UILabel alloc] init];
	_titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_titleLabel.adjustsFontForContentSizeCategory = YES;
	_titleLabel.numberOfLines = 0;

	_detailLabel = [[UILabel alloc] init];
	_detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	_detailLabel.adjustsFontForContentSizeCategory = YES;
	_detailLabel.textColor = UIColor.secondaryLabelColor;
	_detailLabel.numberOfLines = 0;

	_nameLabel = [[UILabel alloc] init];
	_nameLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
	_nameLabel.textColor = UIColor.tertiaryLabelColor;
	_nameLabel.numberOfLines = 1;

	_toggle = [[UISwitch alloc] init];
	_toggle.onTintColor = [SXUI accentColor];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _detailLabel, _nameLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 3;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];

	_toggle.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_toggle];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
		[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
		[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor constant:-12],

		[_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_toggle.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[_toggle.widthAnchor constraintEqualToConstant:51],
		[self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:56],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	_toolName = nil;
	[self.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
}

@end

#pragma mark - Màn hình

@interface SXToolsController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSNumber *> *categories;   // nhóm có công cụ, theo thứ tự enum
@property (nonatomic, copy) NSMutableDictionary<NSNumber *, NSArray<SXTool *> *> *grouped;
@property (nonatomic, strong) UILabel *summaryLabel;
@end

@implementation SXToolsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Công cụ AI";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 72;
	[self.table registerClass:[SXToolCell class] forCellReuseIdentifier:@"tool"];
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.table.tableHeaderView = [self buildHeader];
	[self reloadCatalog];
	[self.table reloadData];
}

#pragma mark - Dữ liệu

- (void)reloadCatalog {
	NSArray<SXTool *> *tools = [SXTools catalog];   // cài đặt catalog nếu chưa
	NSMutableDictionary<NSNumber *, NSMutableArray<SXTool *> *> *buckets = [NSMutableDictionary dictionary];
	for (SXTool *tool in tools) {
		NSNumber *key = @(tool.category);
		NSMutableArray *bucket = buckets[key];
		if (!bucket) {
			bucket = [NSMutableArray array];
			buckets[key] = bucket;
		}
		[bucket addObject:tool];
	}
	NSArray<NSNumber *> *order = [buckets.allKeys sortedArrayUsingSelector:@selector(compare:)];
	NSMutableDictionary<NSNumber *, NSArray<SXTool *> *> *grouped = [NSMutableDictionary dictionary];
	for (NSNumber *key in order) {
		NSArray *bucket = [buckets[key] sortedArrayUsingComparator:^NSComparisonResult(SXTool *a, SXTool *b) {
			return [a.name compare:b.name];
		}];
		grouped[key] = bucket;
	}
	self.grouped = grouped;
	self.categories = order;
	[self updateSummary];
}

- (void)updateSummary {
	NSUInteger total = 0, enabled = 0;
	SXPrefs *prefs = [SXPrefs shared];
	for (NSNumber *key in self.categories) {
		for (SXTool *tool in self.grouped[key]) {
			total++;
			if ([prefs isToolEnabled:tool.name]) enabled++;
		}
	}
	self.summaryLabel.text = [NSString stringWithFormat:
		@"%lu/%lu công cụ đang bật · AI chỉ thấy những công cụ được bật.",
		(unsigned long)enabled, (unsigned long)total];
}

#pragma mark - Header

- (UIView *)buildHeader {
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 0)];

	UILabel *title = [[UILabel alloc] init];
	title.text = @"AI có thể tự làm, không chỉ trả lời";
	title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	title.adjustsFontForContentSizeCategory = YES;
	title.numberOfLines = 0;

	self.summaryLabel = [[UILabel alloc] init];
	self.summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	self.summaryLabel.adjustsFontForContentSizeCategory = YES;
	self.summaryLabel.textColor = UIColor.secondaryLabelColor;
	self.summaryLabel.numberOfLines = 0;

	UILabel *note = [[UILabel alloc] init];
	note.text = @"Mỗi công cụ chạy thật trên máy: đọc pin, chép vào bảng nhớ tạm, mở ứng dụng, "
				@"đọc một trang web, ghi nhớ điều bạn dặn. Tắt công cụ nào thì model không còn thấy "
				@"công cụ đó nữa, và nếu nó vẫn cố gọi thì bị từ chối — không có tác dụng phụ nào chạy ngầm.";
	note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	note.adjustsFontForContentSizeCategory = YES;
	note.textColor = UIColor.secondaryLabelColor;
	note.numberOfLines = 0;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.summaryLabel, note]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 6;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
		[stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:32],
		[stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-32],
		[stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-14],
	]];
	[self layoutHeader:container];
	return container;
}

- (void)layoutHeader:(UIView *)container {
	[container setNeedsLayout];
	[container layoutIfNeeded];
	CGSize size = [container systemLayoutSizeFittingSize:CGSizeMake(self.view.bounds.size.width, 0)
							  withHorizontalFittingPriority:UILayoutPriorityRequired
									verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
	container.frame = CGRectMake(0, 0, self.view.bounds.size.width, size.height);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	// +1 cho nhóm "Khôi phục" ở cuối.
	return (NSInteger)self.categories.count + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section >= (NSInteger)self.categories.count) return 1;
	return (NSInteger)[self.grouped[self.categories[section]] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section >= (NSInteger)self.categories.count) return nil;
	return SXToolCategoryTitle((SXToolCategory)[self.categories[section] integerValue]);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != (NSInteger)self.categories.count) {
		if (section == (NSInteger)self.categories.count - 1) {
			return @"Công cụ có tác dụng phụ (mở ứng dụng, chép, xoá) chỉ chạy khi bạn hỏi. "
				   @"Ghi nhớ lâu dài nằm trong /var/mobile/Library/SiriX/memory.plist và chỉ trên máy bạn.";
		}
		return nil;
	}
	return @"Bật lại toàn bộ công cụ. Cài đặt này chỉ ảnh hưởng SiriX, không đổi cấu hình Siri gốc.";
}

- (SXTool *)toolAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.categories.count) return nil;
	NSArray<SXTool *> *tools = self.grouped[self.categories[indexPath.section]];
	if (indexPath.row >= (NSInteger)tools.count) return nil;
	return tools[indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.categories.count) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
													   reuseIdentifier:nil];
		cell.textLabel.text = @"Bật lại tất cả công cụ";
		cell.textLabel.textColor = [SXUI accentColor];
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	SXToolCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tool" forIndexPath:indexPath];
	SXTool *tool = [self toolAtIndexPath:indexPath];
	if (!tool) return cell;

	cell.toolName = tool.name;
	cell.titleLabel.text = tool.title;
	cell.detailLabel.text = tool.summary;
	cell.nameLabel.text = [NSString stringWithFormat:@"%@%@", tool.name,
						   tool.sideEffect ? @"  ·  có tác dụng phụ" : @""];
	cell.toggle.on = [[SXPrefs shared] isToolEnabled:tool.name];
	cell.toggle.accessibilityLabel = [NSString stringWithFormat:@"Công cụ %@", tool.title];
	cell.toggle.accessibilityHint = tool.sideEffect
		? @"Công cụ này thay đổi trạng thái máy khi AI gọi."
		: @"Công cụ này chỉ đọc thông tin.";
	// Gắn vị trí vào công tắc: lúc bấm không phải dò indexPath từ toạ độ.
	cell.toggle.tag = indexPath.section * 1000 + indexPath.row;
	[cell.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
	[cell.toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section < (NSInteger)self.categories.count) {
		// Chạm vào ô (ngoài công tắc) cũng đổi trạng thái — vùng chạm rộng hơn.
		SXToolCell *cell = (SXToolCell *)[tableView cellForRowAtIndexPath:indexPath];
		[cell.toggle setOn:!cell.toggle.isOn animated:YES];
		[self toggleChanged:cell.toggle];
		return;
	}

	[SXUI confirmOn:self
			  title:@"Bật lại tất cả công cụ?"
			message:@"Mọi công cụ sẽ hiện lại với AI."
		confirmText:@"Bật tất cả"
			 action:^{
		// Một lần ghi duy nhất: 13 lần ghi riêng lẻ sẽ reload prefs + notify 13 lần.
		[SXPrefs setDisabledTools:[NSSet set]];
		[self reloadCatalog];
		[self.table reloadData];
		[SXUI tapFeedback];
	}];
}

#pragma mark - Công tắc

- (void)toggleChanged:(UISwitch *)sender {
	NSInteger section = sender.tag / 1000;
	NSInteger row = sender.tag % 1000;
	SXTool *tool = [self toolAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
	NSString *name = tool.name;
	if (!name.length) return;

	[SXPrefs setToolNamed:name enabled:sender.isOn];
	SXLogDbg(@"pref", @"công cụ %@ → %@", name, sender.isOn ? @"bật" : @"tắt");
	[self updateSummary];
	[SXUI tapFeedback];
	// Tweak đang chạy đọc lại cấu hình nhờ notify này; không cần respring.
	notify_post("com.sirix.tweak/prefs.changed");
}

@end
