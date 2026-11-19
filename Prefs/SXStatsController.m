#import "SXStatsController.h"
#import "SXStore.h"
#import "SXUISupport.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>

static NSString *SXStatsNumber(id value) {
	return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

#pragma mark - Thanh tỉ lệ

@interface SXRateBarView : UIView
@property (nonatomic) double rate;
@end

@implementation SXRateBarView {
	UIView *_track;
	UIView *_fill;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;
	self.backgroundColor = UIColor.clearColor;
	self.isAccessibilityElement = YES;
	self.accessibilityTraits = UIAccessibilityTraitStaticText;

	_track = [[UIView alloc] init];
	_track.translatesAutoresizingMaskIntoConstraints = NO;
	_track.backgroundColor = UIColor.tertiarySystemFillColor;
	_track.layer.cornerRadius = 5;
	_track.clipsToBounds = YES;
	[self addSubview:_track];

	_fill = [[UIView alloc] init];
	_fill.backgroundColor = [SXUI accentColor];
	_fill.layer.cornerRadius = 5;
	[_track addSubview:_fill];

	[NSLayoutConstraint activateConstraints:@[
		[_track.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_track.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		[_track.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_track.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
	]];
	return self;
}

- (void)setRate:(double)rate {
	_rate = MAX(0.0, MIN(1.0, rate));
	[self setNeedsLayout];
	self.accessibilityLabel = [NSString stringWithFormat:@"Tỉ lệ thay %.0f phần trăm", _rate * 100.0];
	self.accessibilityValue = self.accessibilityLabel;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = _track.bounds;
	_fill.frame = CGRectMake(0, 0, bounds.size.width * self.rate, bounds.size.height);
}

@end

#pragma mark - Màn hình

@interface SXStatsController () <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *rateLabel;
@property (nonatomic, strong) UILabel *rateCaption;
@property (nonatomic, strong) UILabel *rateHint;
@property (nonatomic, strong) SXRateBarView *rateBar;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic) NSInteger totalEvents;
@property (nonatomic) NSInteger loadGeneration;
@end

@implementation SXStatsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Thống kê";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 48;
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
	[refresh addTarget:self action:@selector(sx_handleRefresh:) forControlEvents:UIControlEventValueChanged];
	self.table.refreshControl = refresh;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"trash"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_confirmClear)];
	self.navigationItem.rightBarButtonItem.enabled = NO;

	[self sx_buildHeader];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sx_reload];
}

#pragma mark - Header

- (void)sx_buildHeader {
	UIView *header = [[UIView alloc] initWithFrame:CGRectZero];

	UILabel *overline = [SXUI footnoteLabel:@"TỈ LỆ THAY PHẢN HỒI SIRI"];
	UIFontDescriptor *descriptor = [[UIFont preferredFontForTextStyle:UIFontTextStyleCaption2].fontDescriptor
									 fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
	if (descriptor) overline.font = [UIFont fontWithDescriptor:descriptor size:0];

	self.rateLabel = [[UILabel alloc] init];
	self.rateLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
	self.rateLabel.adjustsFontForContentSizeCategory = YES;
	self.rateLabel.textColor = [SXUI accentColor];
	self.rateLabel.text = @"—";
	self.rateLabel.adjustsFontSizeToFitWidth = YES;
	self.rateLabel.minimumScaleFactor = 0.6;
	self.rateLabel.accessibilityTraits = UIAccessibilityTraitHeader;

	self.rateBar = [[SXRateBarView alloc] init];
	self.rateBar.translatesAutoresizingMaskIntoConstraints = NO;
	[self.rateBar.heightAnchor constraintEqualToConstant:10].active = YES;

	self.rateCaption = [SXUI footnoteLabel:@"Chưa có lượt nào được quyết định."];
	self.rateCaption.textColor = UIColor.secondaryLabelColor;

	self.rateHint = [SXUI footnoteLabel:
		@"Chỉ tính các lượt SiriX đã thay hoặc đã quyết định giữ Siri gốc; lượt hết giờ và lỗi nằm trong mục Sự cố."];
	self.rateHint.textColor = UIColor.tertiaryLabelColor;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
		@[overline, self.rateLabel, self.rateBar, self.rateCaption, self.rateHint]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentFill;
	stack.spacing = 6;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[header addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
		[stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
		[stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
		[stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
	]];
	self.header = header;
	self.table.tableHeaderView = header;
	[self sx_layoutHeader];
}

- (void)sx_layoutHeader {
	UIView *header = self.header;
	if (!header) return;
	CGFloat width = CGRectGetWidth(self.table.bounds);
	if (width <= 0) width = UIScreen.mainScreen.bounds.size.width;
	header.frame = CGRectMake(0, 0, width, CGRectGetHeight(header.frame));
	[header setNeedsLayout];
	[header layoutIfNeeded];
	CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
						withHorizontalFittingPriority:UILayoutPriorityRequired
							  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
	header.frame = CGRectMake(0, 0, width, ceil(size.height));
	self.table.tableHeaderView = header;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = CGRectGetWidth(self.table.bounds);
	if (fabs(CGRectGetWidth(self.header.frame) - width) > 0.5) [self sx_layoutHeader];
}

#pragma mark - Dữ liệu

- (void)sx_reload {
	NSUInteger generation = ++self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (generation != (NSUInteger)strongSelf.loadGeneration) return;
			[strongSelf.table.refreshControl endRefreshing];
			if (![snapshot isKindOfClass:[NSDictionary class]]) {
				strongSelf.table.backgroundView = [SXUI emptyStateWithSymbol:@"exclamationmark.triangle"
																		title:@"Không đọc được thống kê"
																	  message:@"Kiểm tra quyền ghi thư mục /var/mobile/Library/SiriX rồi kéo xuống để thử lại."];
				SXLogErr(@"pref", @"đọc thống kê thất bại");
				return;
			}
			[strongSelf sx_applySnapshot:snapshot];
		});
	});
}

- (void)sx_handleRefresh:(UIRefreshControl *)refresh {
	[self sx_reload];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[refresh endRefreshing];
	});
}

- (NSString *)sx_speedGradeForMilliseconds:(double)averageMs {
	if (averageMs <= 0) return nil;
	if (averageMs < 1200) return @"nhanh";
	if (averageMs < 3000) return @"vừa phải";
	if (averageMs < 6000) return @"chậm";
	return @"rất chậm";
}

- (void)sx_applySnapshot:(NSDictionary *)snapshot {
	NSDictionary *stats = [snapshot[@"stats"] isKindOfClass:[NSDictionary class]] ? snapshot[@"stats"] : @{};
	NSInteger replaced = [SXStatsNumber(stats[@"replaced"]) integerValue];
	NSInteger kept = [SXStatsNumber(stats[@"kept"]) integerValue];
	NSInteger timeout = [SXStatsNumber(stats[@"timeout"]) integerValue];
	NSInteger failures = [SXStatsNumber(stats[@"error"]) integerValue];
	double averageMs = [SXStatsNumber(stats[@"msAvg"]) doubleValue];
	NSInteger decided = replaced + kept;
	NSInteger incidents = timeout + failures;
	self.totalEvents = replaced + kept + incidents;

	double rate = decided > 0 ? (double)replaced / (double)decided : 0.0;
	self.rateLabel.text = decided > 0
		? [NSString stringWithFormat:@"%.0f%%", rate * 100.0]
		: @"—";
	self.rateBar.rate = rate;
	if (decided > 0) {
		self.rateCaption.text = [NSString stringWithFormat:@"%@ lượt thay trên %@ lượt đã quyết định",
								 [SXUI groupedNumber:replaced], [SXUI groupedNumber:decided]];
	} else {
		self.rateCaption.text = @"Chưa có lượt nào được quyết định.";
	}
	self.navigationItem.prompt = self.totalEvents
		? [NSString stringWithFormat:@"%@ sự kiện đã ghi", [SXUI groupedNumber:self.totalEvents]]
		: nil;
	self.navigationItem.rightBarButtonItem.enabled = self.totalEvents > 0;

	NSString *speed = averageMs > 0 ? [NSString stringWithFormat:@"%.0f ms", averageMs] : @"chưa có";
	NSString *grade = [self sx_speedGradeForMilliseconds:averageMs];
	NSInteger handled = decided + incidents;
	NSString *incidentRate = handled > 0
		? [NSString stringWithFormat:@"%.0f%% số lượt", (double)incidents / (double)handled * 100.0]
		: @"—";

	self.sections = @[
		@{@"title": @"Quyết định hiển thị", @"rows": @[
			@{@"label": @"Đã thay bằng AI", @"value": [SXUI groupedNumber:replaced]},
			@{@"label": @"Giữ Siri gốc", @"value": [SXUI groupedNumber:kept]},
		], @"footer": @"Lượt “giữ Siri gốc” là lúc SiriX chủ động không can thiệp: câu hỏi quá ngắn, trợ lý không kịp trả lời hoặc bạn tắt thay thế."},
		@{@"title": @"Sự cố", @"rows": @[
			@{@"label": @"Hết giờ chờ", @"value": [SXUI groupedNumber:timeout]},
			@{@"label": @"Lỗi AI", @"value": [SXUI groupedNumber:failures]},
			@{@"label": @"Tỉ lệ sự cố", @"value": incidentRate},
		], @"footer": @"Sự cố cao thường do mạng chậm, khoá API sai hoặc máy chủ không phản hồi — xem Hướng dẫn → Nhật ký để biết chi tiết."},
		@{@"title": @"Tốc độ", @"rows": @[
			@{@"label": @"Thời gian AI trung bình", @"value": speed},
			@{@"label": @"Đánh giá", @"value": grade ?: @"—"},
		], @"footer": @"Trung bình có trọng số (làm mượt theo thời gian), không phải chi phí API. Lượt không có phản hồi AI không được tính."},
	];

	[self.table reloadData];
	[self sx_updateEmptyState];
}

- (void)sx_updateEmptyState {
	self.table.backgroundView = self.totalEvents
		? nil
		: [SXUI emptyStateWithSymbol:@"chart.bar.xaxis"
							   title:@"Chưa có số liệu"
							 message:@"Hỏi Siri một câu để SiriX ghi nhận lượt đầu tiên. Thống kê chỉ đếm lượt SiriX đã quyết định can thiệp."];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return 0;
	NSDictionary *group = self.sections[(NSUInteger)section];
	NSArray *rows = [group[@"rows"] isKindOfClass:[NSArray class]] ? group[@"rows"] : @[];
	return (NSInteger)rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return nil;
	return self.sections[(NSUInteger)section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return nil;
	return self.sections[(NSUInteger)section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"stat";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.adjustsFontForContentSizeCategory = YES;
		cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
	}
	if (indexPath.section < 0 || (NSUInteger)indexPath.section >= self.sections.count) return cell;
	NSDictionary *group = self.sections[(NSUInteger)indexPath.section];
	NSArray *rows = [group[@"rows"] isKindOfClass:[NSArray class]] ? group[@"rows"] : @[];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= rows.count) return cell;
	NSDictionary *row = rows[(NSUInteger)indexPath.row];
	cell.textLabel.text = row[@"label"];
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.textLabel.textColor = UIColor.labelColor;
	cell.detailTextLabel.text = row[@"value"];
	cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.numberOfLines = 1;
	cell.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", row[@"label"], row[@"value"]];
	return cell;
}

#pragma mark - Xoá

- (void)sx_confirmClear {
	if (!self.totalEvents) {
		[SXUI alertOn:self title:@"Chưa có số liệu" message:nil];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá thống kê?"
			message:@"Đưa mọi bộ đếm về 0. Lịch sử hội thoại không bị ảnh hưởng."
		confirmText:@"Xoá"
			 action:^{
		NSUInteger generation = ++weakSelf.loadGeneration;
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] clearStats];
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				if (generation != (NSUInteger)strongSelf.loadGeneration) return;
				if (!ok) {
					[SXUI alertOn:strongSelf
							title:@"Không xoá được"
						  message:@"Kiểm tra quyền ghi thư mục lưu trữ."];
					return;
				}
				[SXUI tapFeedback];
				[strongSelf sx_reload];
			});
		});
	}];
}

@end
