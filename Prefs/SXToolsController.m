#import "SXToolsController.h"
#import "SXNavigationSupport.h"
#import "SXUISupport.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXToolkit.h"
#import "SXTools.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#pragma mark - Ô công cụ

/// Ô ba dòng: tên tiếng Việt, mô tả một câu, tên kỹ thuật kèm nhãn tác dụng phụ.
/// Tự vẽ thay vì PSSpecifier để mô tả xuống dòng được — danh sách công cụ mà chỉ
/// có một dòng cắt cụt thì người dùng không hiểu nó làm gì.
@interface SXToolCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, copy) NSString *toolName;
@property (nonatomic, copy) void (^onToggle)(BOOL enabled);
@end

@implementation SXToolCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleDefault;
	self.backgroundColor = [SXUI cardColor];
	self.isAccessibilityElement = YES;

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
	_nameLabel.numberOfLines = 0;

	_toggle = [[UISwitch alloc] init];
	_toggle.onTintColor = [SXUI accentColor];
	// Công tắc chỉ để nhìn; thao tác do ô đảm nhiệm (một vùng chạm, một hành vi).
	_toggle.userInteractionEnabled = NO;

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
		[self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:56],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	_toolName = nil;
	_onToggle = nil;
	_toggle.on = NO;
	_titleLabel.textColor = UIColor.labelColor;
	_detailLabel.textColor = UIColor.secondaryLabelColor;
}

- (void)setToolEnabled:(BOOL)enabled {
	self.toggle.on = enabled;
	// Trạng thái tắt vẫn đọc được nhưng mờ hơn: mắt không phải quét cột công tắc.
	self.titleLabel.textColor = enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
	self.accessibilityValue = enabled ? @"đang bật" : @"đang tắt";
	self.accessibilityTraits = enabled ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone;
}

- (BOOL)accessibilityActivate {
	if (!self.onToggle) return NO;
	BOOL next = !self.toggle.isOn;
	self.onToggle(next);
	return YES;
}

- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions {
	if (!self.onToggle) return nil;
	__weak typeof(self) weakSelf = self;
	NSString *title = self.toggle.isOn ? @"Tắt công cụ" : @"Bật công cụ";
	return @[[[UIAccessibilityCustomAction alloc] initWithName:title actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
		(void)action;
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.onToggle) return NO;
		strongSelf.onToggle(!strongSelf.toggle.isOn);
		return YES;
	}]];
}

@end

#pragma mark - Màn hình

@interface SXToolsController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSNumber *> *categories;   // nhóm có công cụ, theo thứ tự enum
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<SXTool *> *> *grouped;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIView *header;
@property (nonatomic) NSUInteger enabledCount;
@property (nonatomic) NSUInteger totalCount;
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

	self.header = [self buildHeader];
	self.table.tableHeaderView = self.header;
	UILongPressGestureRecognizer *longPress =
		[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sx_handleLongPress:)];
	longPress.minimumPressDuration = 0.45;
	longPress.cancelsTouchesInView = YES;
	[self.table addGestureRecognizer:longPress];

	[self reloadCatalog];
	[self sx_layoutHeader];
	[self.table reloadData];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = CGRectGetWidth(self.table.bounds);
	if (width > 0 && fabs(CGRectGetWidth(self.header.frame) - width) > 0.5) {
		self.header.frame = CGRectMake(0, 0, width, CGRectGetHeight(self.header.frame));
		[self sx_layoutHeader];
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Công cụ");
	// Cấu hình có thể đổi từ màn hình khác (khôi phục mặc định…).
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
		grouped[key] = [buckets[key] sortedArrayUsingComparator:^NSComparisonResult(SXTool *a, SXTool *b) {
			return [a.title compare:b.title];
		}];
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
	self.enabledCount = enabled;
	self.totalCount = total;
	self.summaryLabel.text = [NSString stringWithFormat:@"%lu/%lu công cụ đang bật · AI chỉ thấy những công cụ được bật.",
							  (unsigned long)enabled, (unsigned long)total];
	self.summaryLabel.textColor = enabled ? UIColor.secondaryLabelColor : [SXUI warningColor];
	self.navigationItem.prompt = total
		? [NSString stringWithFormat:@"%lu/%lu công cụ đang bật", (unsigned long)enabled, (unsigned long)total]
		: nil;
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

	UILabel *note = [SXUI footnoteLabel:
		@"Mỗi công cụ chạy thật trên máy: đọc pin, chép vào bảng nhớ tạm, mở ứng dụng, "
		@"đọc một trang web, ghi nhớ điều bạn dặn. Tắt công cụ nào thì model không còn thấy "
		@"công cụ đó nữa, và nếu nó vẫn cố gọi thì bị từ chối — không có tác dụng phụ nào chạy ngầm. "
		@"Chạm vào một công cụ để bật/tắt, nhấn giữ để xem khi nào AI dùng nó."];

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
	return container;
}

- (void)sx_layoutHeader {
	CGFloat width = CGRectGetWidth(self.table.bounds);
	if (width <= 0) width = UIScreen.mainScreen.bounds.size.width;
	if (CGRectGetWidth(self.header.frame) != width) {
		self.header.frame = CGRectMake(0, 0, width, 0);
	}
	[self.header setNeedsLayout];
	[self.header layoutIfNeeded];
	CGSize size = [self.header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
						 withHorizontalFittingPriority:UILayoutPriorityRequired
							   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
	self.header.frame = CGRectMake(0, 0, width, ceil(size.height));
	// Gán lại để UIKit đo lại chiều cao phần đầu bảng.
	self.table.tableHeaderView = self.header;
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	// +1 cho nhóm "Khôi phục" ở cuối.
	return (NSInteger)self.categories.count + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0) return 0;
	if (section >= (NSInteger)self.categories.count) return 2;
	return (NSInteger)[self.grouped[self.categories[(NSUInteger)section]] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || section >= (NSInteger)self.categories.count) return @"Khôi phục";
	NSArray<SXTool *> *tools = self.grouped[self.categories[(NSUInteger)section]];
	NSUInteger enabled = 0;
	for (SXTool *tool in tools) {
		if ([[SXPrefs shared] isToolEnabled:tool.name]) enabled++;
	}
	return [NSString stringWithFormat:@"%@ · %lu/%lu",
			SXToolCategoryTitle((SXToolCategory)[self.categories[(NSUInteger)section] integerValue]),
			(unsigned long)enabled, (unsigned long)tools.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section != (NSInteger)self.categories.count) {
		return section == (NSInteger)self.categories.count - 1
			? @"Công cụ có tác dụng phụ (mở ứng dụng, chép, xoá) chỉ chạy khi bạn hỏi. "
			  @"Ghi nhớ lâu dài nằm trong /var/mobile/Library/SiriX/memory.plist và chỉ trên máy bạn."
			: nil;
	}
	return @"Bật hoặc tắt toàn bộ công cụ trong một lần. Cài đặt này chỉ ảnh hưởng SiriX, không đổi cấu hình Siri gốc.";
}

- (SXTool *)toolAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || indexPath.section >= (NSInteger)self.categories.count) return nil;
	NSArray<SXTool *> *tools = self.grouped[self.categories[(NSUInteger)indexPath.section]];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)tools.count) return nil;
	return tools[(NSUInteger)indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.categories.count) {
		static NSString *actionIdentifier = @"action";
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionIdentifier];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:actionIdentifier];
			cell.textLabel.adjustsFontForContentSizeCategory = YES;
		}
		BOOL allOn = self.totalCount > 0 && self.enabledCount == self.totalCount;
		cell.textLabel.text = allOn ? @"Tắt tất cả công cụ" : @"Bật lại tất cả công cụ";
		cell.textLabel.textColor = allOn ? [SXUI dangerColor] : [SXUI accentColor];
		cell.accessibilityLabel = cell.textLabel.text;
		return cell;
	}

	SXToolCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tool" forIndexPath:indexPath];
	SXTool *tool = [self toolAtIndexPath:indexPath];
	if (!tool) return cell;

	BOOL enabled = [[SXPrefs shared] isToolEnabled:tool.name];
	cell.toolName = tool.name;
	cell.titleLabel.text = tool.title;
	cell.detailLabel.text = tool.summary;
	NSString *nameLine = tool.name;
	if (tool.sideEffect) nameLine = [nameLine stringByAppendingString:@"  ·  có tác dụng phụ"];
	if (tool.requiresMainThread) nameLine = [nameLine stringByAppendingString:@"  ·  cần giao diện"];
	cell.nameLabel.text = nameLine;
	[cell setToolEnabled:enabled];
	cell.accessibilityLabel = tool.title;
	cell.accessibilityHint = tool.summary;
	__weak typeof(self) weakSelf = self;
	cell.onToggle = ^(BOOL next) {
		[weakSelf sx_setTool:tool.name enabled:next];
	};
	return cell;
}

#pragma mark - Thao tác

- (void)sx_setTool:(NSString *)name enabled:(BOOL)enabled {
	if (!name.length) return;
	[SXPrefs setToolNamed:name enabled:enabled];
	SXLogDbg(@"pref", @"công cụ %@ → %@", name, enabled ? @"bật" : @"tắt");
	[SXUI tapFeedback];
	notify_post("com.sirix.tweak/prefs.changed");
	// Chỉ cập nhật con số + đúng hàng vừa đổi: reload toàn bảng làm mất vị trí cuộn.
	[self updateSummary];
	[self.table reloadSections:[NSIndexSet indexSetWithIndex:(NSUInteger)self.categories.count]
			   withRowAnimation:UITableViewRowAnimationNone];
	for (NSNumber *key in self.categories) {
		NSUInteger section = (NSUInteger)[self.categories indexOfObject:key];
		NSArray<SXTool *> *tools = self.grouped[key];
		NSUInteger row = [tools indexOfObjectPassingTest:^BOOL(SXTool *tool, NSUInteger index, BOOL *stop) {
			(void)index; (void)stop;
			return [tool.name isEqualToString:name];
		}];
		if (row == NSNotFound) continue;
		// Vẽ lại tiêu đề mục (đếm lại) và hàng vừa đổi.
		@try {
			[self.table reloadSections:[NSIndexSet indexSetWithIndex:section]
					  withRowAnimation:UITableViewRowAnimationNone];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"reload mục công cụ: %@", exception.reason);
			[self.table reloadData];
		}
		break;
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section < (NSInteger)self.categories.count) {
		SXTool *tool = [self toolAtIndexPath:indexPath];
		if (!tool) return;
		[self sx_setTool:tool.name enabled:![[SXPrefs shared] isToolEnabled:tool.name]];
		return;
	}
	BOOL allOn = self.totalCount > 0 && self.enabledCount == self.totalCount;
	if (allOn) {
		__weak typeof(self) weakSelf = self;
		[SXUI confirmOn:self
				  title:@"Tắt tất cả công cụ?"
				message:@"AI sẽ chỉ trả lời bằng kiến thức của mô hình, không đọc dữ liệu máy, không mở ứng dụng."
			confirmText:@"Tắt tất cả"
				 action:^{
			NSMutableSet<NSString *> *all = [NSMutableSet set];
			for (SXTool *tool in [SXTools catalog]) {
				if (tool.name.length) [all addObject:tool.name];
			}
			[SXPrefs setDisabledTools:all];
			[weakSelf sx_afterBulkChange];
		}];
		return;
	}
	// Một lần ghi duy nhất: từng công cụ một sẽ reload prefs + notify N lần.
	[SXPrefs setDisabledTools:[NSSet set]];
	[self sx_afterBulkChange];
}

- (void)sx_afterBulkChange {
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	[self reloadCatalog];
	[self.table reloadData];
}

- (void)sx_showToolInfo:(SXTool *)tool {
	if (!tool) return;
	BOOL enabled = [[SXPrefs shared] isToolEnabled:tool.name];
	NSString *message = [NSString stringWithFormat:@"%@\n\nKhi nào AI dùng:\n%@\n\nMã: %@",
						 tool.summary,
						 tool.prompt,
						 tool.name];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:tool.title
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ công cụ này",
													  enabled ? @"Tắt" : @"Bật"]
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[self sx_setTool:tool.name enabled:!enabled];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

/// Nhấn giữ một dòng: xem khi nào AI dùng công cụ, kèm nút bật/tắt.
- (void)sx_handleLongPress:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) return;
	CGPoint point = [gesture locationInView:self.table];
	NSIndexPath *indexPath = [self.table indexPathForRowAtPoint:point];
	SXTool *tool = [self toolAtIndexPath:indexPath];
	if (!tool) return;
	[self sx_showToolInfo:tool];
}

@end
