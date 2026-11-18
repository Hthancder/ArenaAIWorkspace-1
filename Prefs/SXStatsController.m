#import "SXStatsController.h"
#import "SXStore.h"
#import "SXUISupport.h"
#import <UIKit/UIKit.h>

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

	_track = [[UIView alloc] initWithFrame:self.bounds];
	_track.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_track.backgroundColor = UIColor.tertiarySystemFillColor;
	_track.layer.cornerRadius = 4;
	_track.clipsToBounds = YES;
	[self addSubview:_track];

	_fill = [[UIView alloc] initWithFrame:CGRectZero];
	_fill.backgroundColor = [SXUI accentColor];
	_fill.layer.cornerRadius = 4;
	[_track addSubview:_fill];
	return self;
}

- (void)setRate:(double)rate {
	_rate = MAX(0.0, MIN(1.0, rate));
	[self setNeedsLayout];
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
@property (nonatomic, strong) SXRateBarView *rateBar;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic) NSInteger totalEvents;
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
	[refresh addTarget:self action:@selector(sx_reload) forControlEvents:UIControlEventValueChanged];
	self.table.refreshControl = refresh;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"trash"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_confirmClear)];

	[self sx_buildHeader];
	[self sx_reload];
}

#pragma mark - Header

- (void)sx_buildHeader {
	CGFloat width = UIScreen.mainScreen.bounds.size.width;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 132)];

	self.rateLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 12, width - 40, 44)];
	self.rateLabel.font = [UIFont systemFontOfSize:38 weight:UIFontWeightBold];
	self.rateLabel.textColor = [SXUI accentColor];
	self.rateLabel.text = @"—";
	self.rateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:self.rateLabel];

	self.rateCaption = [[UILabel alloc] initWithFrame:CGRectMake(20, 56, width - 40, 18)];
	self.rateCaption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	self.rateCaption.textColor = UIColor.secondaryLabelColor;
	self.rateCaption.text = @"tỉ lệ thay phản hồi Siri";
	self.rateCaption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:self.rateCaption];

	self.rateBar = [[SXRateBarView alloc] initWithFrame:CGRectMake(20, 86, width - 40, 8)];
	self.rateBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:self.rateBar];

	UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(20, 102, width - 40, 16)];
	hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	hint.textColor = UIColor.tertiaryLabelColor;
	hint.text = @"Tính trên các lượt đã thay và đã giữ; tác vụ hệ thống không tính.";
	hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:hint];

	self.table.tableHeaderView = header;
}

#pragma mark - Dữ liệu

- (void)sx_reload {
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			[strongSelf.table.refreshControl endRefreshing];
			if (!snapshot) {
				[SXUI alertOn:strongSelf
						title:@"Không đọc được thống kê"
					  message:@"Kiểm tra quyền ghi thư mục /var/mobile/Library/SiriX rồi thử lại."];
				return;
			}
			[strongSelf sx_applySnapshot:snapshot];
		});
	});
}

- (void)sx_applySnapshot:(NSDictionary *)snapshot {
	NSDictionary *stats = [snapshot[@"stats"] isKindOfClass:[NSDictionary class]] ? snapshot[@"stats"] : @{};
	NSInteger replaced = [stats[@"replaced"] integerValue];
	NSInteger kept = [stats[@"kept"] integerValue];
	NSInteger timeout = [stats[@"timeout"] integerValue];
	NSInteger error = [stats[@"error"] integerValue];
	double averageMs = [stats[@"msAvg"] doubleValue];
	NSInteger decided = replaced + kept;
	self.totalEvents = replaced + kept + timeout + error;

	double rate = decided > 0 ? (double)replaced / (double)decided : 0.0;
	self.rateLabel.text = decided > 0 ? [NSString stringWithFormat:@"%.0f%%", rate * 100.0] : @"—";
	self.rateBar.rate = rate;
	self.rateCaption.text = decided > 0
		? [NSString stringWithFormat:@"%@ lượt thay trên %@ lượt đã quyết định",
		   [SXUI groupedNumber:replaced], [SXUI groupedNumber:decided]]
		: @"tỉ lệ thay phản hồi Siri";
	self.navigationItem.prompt = self.totalEvents
		? [NSString stringWithFormat:@"%@ sự kiện đã ghi", [SXUI groupedNumber:self.totalEvents]]
		: nil;

	NSString *speed = averageMs > 0
		? [NSString stringWithFormat:@"%.0f ms", averageMs]
		: @"chưa có";

	self.sections = @[
		@{@"title": @"Quyết định hiển thị", @"rows": @[
			@{@"label": @"Đã thay bằng AI", @"value": [SXUI groupedNumber:replaced]},
			@{@"label": @"Giữ Siri gốc", @"value": [SXUI groupedNumber:kept]},
		]},
		@{@"title": @"Sự cố", @"rows": @[
			@{@"label": @"Hết giờ chờ", @"value": [SXUI groupedNumber:timeout]},
			@{@"label": @"Lỗi AI", @"value": [SXUI groupedNumber:error]},
		]},
		@{@"title": @"Tốc độ", @"rows": @[
			@{@"label": @"Thời gian AI trung bình", @"value": speed},
		], @"footer": @"Trung bình có trọng số (làm mượt theo thời gian), không phải chi phí API."},
	];

	[self.table reloadData];
	[self sx_updateEmptyState];
}

- (void)sx_updateEmptyState {
	self.table.backgroundView = self.totalEvents
		? nil
		: [SXUI emptyStateWithSymbol:@"chart.bar.xaxis"
							   title:@"Chưa có số liệu"
							 message:@"Hỏi Siri một câu để SiriX ghi nhận lượt đầu tiên."];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if ((NSUInteger)section >= self.sections.count) return 0;
	NSDictionary *group = self.sections[(NSUInteger)section];
	NSArray *rows = [group[@"rows"] isKindOfClass:[NSArray class]] ? group[@"rows"] : @[];
	return (NSInteger)rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if ((NSUInteger)section >= self.sections.count) return nil;
	return self.sections[(NSUInteger)section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if ((NSUInteger)section >= self.sections.count) return nil;
	return self.sections[(NSUInteger)section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stat"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"stat"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	NSDictionary *group = self.sections[(NSUInteger)indexPath.section];
	NSArray *rows = [group[@"rows"] isKindOfClass:[NSArray class]] ? group[@"rows"] : @[];
	if ((NSUInteger)indexPath.row >= rows.count) return cell;
	NSDictionary *row = rows[(NSUInteger)indexPath.row];
	cell.textLabel.text = row[@"label"];
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.textLabel.textColor = UIColor.labelColor;
	cell.detailTextLabel.text = row[@"value"];
	cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	return cell;
}

#pragma mark - Xoá

- (void)sx_confirmClear {
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá thống kê?"
			message:@"Không thể hoàn tác. Lịch sử hội thoại không bị ảnh hưởng."
		confirmText:@"Xoá"
			 action:^{
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] clearStats];
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				if (ok) [strongSelf sx_reload];
				else [SXUI alertOn:strongSelf title:@"Không xoá được" message:@"Kiểm tra quyền ghi thư mục lưu trữ."];
			});
		});
	}];
}

@end
