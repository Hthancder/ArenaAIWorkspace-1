#import "SXDiagnosticsController.h"
#import "SXNavigationSupport.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXStore.h"
#import "SXUISupport.h"
#import <UIKit/UIKit.h>

/// Một mục kiểm tra: tiêu đề, mô tả ngắn, mức độ và (nếu sửa được trong
/// Settings) nơi cần sửa. Màn Chẩn đoán gom mọi thứ “vì sao Siri không trả lời”
/// vào một danh sách thay vì để người dùng tự ghép từ 4 màn hình và log.
typedef NS_ENUM(NSInteger, SXDiagnosticLevel) {
	SXDiagnosticLevelOK = 0,
	SXDiagnosticLevelWarn,
	SXDiagnosticLevelProblem,
};

@interface SXDiagnosticItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic) SXDiagnosticLevel level;
@end

@implementation SXDiagnosticItem
@end

@interface SXDiagnosticsController () <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSArray<SXDiagnosticItem *> *> *sections;
@property (nonatomic, copy) NSArray<NSString *> *sectionTitles;
@property (nonatomic) NSInteger loadGeneration;
@end

@implementation SXDiagnosticsController

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Chẩn đoán";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 76;
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
		initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_shareReport)];

	[self sx_reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Chẩn đoán");
	[self sx_reload];
}

#pragma mark - Dữ liệu

- (void)sx_handleRefresh:(UIRefreshControl *)refresh {
	[self sx_reload];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{ [refresh endRefreshing]; });
}

- (void)sx_reload {
	NSUInteger generation = ++self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || generation != (NSUInteger)strongSelf.loadGeneration) return;
			[strongSelf sx_buildWithSnapshot:snapshot];
		});
	});
}

- (SXDiagnosticItem *)itemWithTitle:(NSString *)title
							 detail:(NSString *)detail
							  level:(SXDiagnosticLevel)level {
	SXDiagnosticItem *item = [SXDiagnosticItem new];
	item.title = title;
	item.detail = detail;
	item.level = level;
	return item;
}

- (NSArray<SXDiagnosticItem *> *)sx_setupItems:(SXPrefs *)prefs {
	NSMutableArray<SXDiagnosticItem *> *items = [NSMutableArray array];

	if (!prefs.enabled) {
		[items addObject:[self itemWithTitle:@"SiriX đang tắt"
									  detail:@"Bật ở màn hình chính để SiriX thay câu trả lời của Siri."
									   level:SXDiagnosticLevelProblem]];
		return items;
	}
	[items addObject:[self itemWithTitle:@"SiriX đang bật"
								  detail:[NSString stringWithFormat:@"%@ · %@",
										  prefs.mode == SXReplyModeFull ? @"Thay thế mọi câu" : @"Thông minh",
										  [prefs.triggerMode isEqualToString:@"prefix"] ? @"chỉ khi gõ @ai" : @"tự động"]
								   level:SXDiagnosticLevelOK]];

	NSString *key = prefs.activeAPIKey;
	if (!key.length) {
		[items addObject:[self itemWithTitle:@"Thiếu khoá API"
									  detail:[NSString stringWithFormat:
											  @"Mở “Cấu hình %@” và dán khoá. Không có khoá thì SiriX luôn giữ câu trả lời gốc.",
											  prefs.activeProviderName]
									   level:SXDiagnosticLevelProblem]];
	} else {
		[items addObject:[self itemWithTitle:@"Đã có khoá API"
									  detail:[NSString stringWithFormat:@"%@ (%lu ký tự)", [SXPrefs maskedKey:key],
											  (unsigned long)key.length]
									   level:SXDiagnosticLevelOK]];
	}

	NSString *model = prefs.activeModel;
	BOOL modelLooksEmpty = ![model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
	[items addObject:[self itemWithTitle:modelLooksEmpty ? @"Chưa đặt tên model" : @"Model"
								  detail:modelLooksEmpty
									   ? @"Đang dùng model mặc định của nhà cung cấp."
									   : model
								   level:modelLooksEmpty ? SXDiagnosticLevelWarn : SXDiagnosticLevelOK]];

	if (prefs.provider == SXProviderOpenAI) {
		NSString *base = prefs.openaiBase;
		BOOL valid = [SXPrefs isValidBaseURL:base];
		[items addObject:[self itemWithTitle:valid ? @"Endpoint hợp lệ" : @"Endpoint không hợp lệ"
									  detail:valid ? base
										   : [NSString stringWithFormat:@"“%@” — cần http(s):// và tên miền.", base ?: @""]
									   level:valid ? SXDiagnosticLevelOK : SXDiagnosticLevelProblem]];
		if (valid && [base.lowercaseString hasPrefix:@"http://"]) {
			[items addObject:[self itemWithTitle:@"Endpoint dùng http://"
										  detail:@"Dữ liệu (kể cả khoá API) đi trên mạng không mã hoá. Đổi sang https:// nếu máy chủ hỗ trợ."
										   level:SXDiagnosticLevelWarn]];
		}
	} else {
		[items addObject:[self itemWithTitle:@"Endpoint Gemini"
									  detail:@"generativelanguage.googleapis.com (cố định)"
									   level:SXDiagnosticLevelOK]];
	}
	return items;
}

- (NSArray<SXDiagnosticItem *> *)sx_timingItems:(SXPrefs *)prefs {
	NSMutableArray<SXDiagnosticItem *> *items = [NSMutableArray array];
	[items addObject:[self itemWithTitle:@"Ngân sách trả lời"
								  detail:[NSString stringWithFormat:@"%.0f giây cho toàn bộ một câu hỏi",
										  prefs.responseTimeout]
								   level:SXDiagnosticLevelOK]];
	SXDiagnosticLevel deadlineLevel = SXDiagnosticLevelOK;
	NSString *deadlineDetail = [NSString stringWithFormat:@"%.0f giây", prefs.replyDeadline];
	if (prefs.replyDeadline + 0.5 < prefs.responseTimeout) {
		deadlineLevel = SXDiagnosticLevelWarn;
		deadlineDetail = [deadlineDetail stringByAppendingString:
			@" — ngắn hơn ngân sách, nên model chậm sẽ bị cắt dù còn thời gian."];
	} else if (prefs.replyDeadline > 12) {
		deadlineLevel = SXDiagnosticLevelWarn;
		deadlineDetail = [deadlineDetail stringByAppendingString:
			@" — Siri gốc có thể tự đóng giao diện trước khi câu trả lời hiện ra."];
	}
	[items addObject:[self itemWithTitle:@"Trần chờ Siri" detail:deadlineDetail level:deadlineLevel]];

	NSString *action = @"Khi hết giờ: hiện bubble “chưa kịp trả lời”";
	SXDiagnosticLevel actionLevel = SXDiagnosticLevelOK;
	if ([prefs.timeoutAction isEqualToString:@"keep"]) {
		action = @"Khi hết giờ: giữ câu trả lời Siri gốc";
	} else if ([prefs.timeoutAction isEqualToString:@"retry"]) {
		action = @"Khi hết giờ: thử lại một lần bằng model dự phòng";
		if (![prefs fallbackModelForProvider:prefs.provider].length) {
			action = [action stringByAppendingString:
				@" — chưa đặt model dự phòng, sẽ dùng mặc định của nhà cung cấp."];
			actionLevel = SXDiagnosticLevelWarn;
		}
	}
	[items addObject:[self itemWithTitle:@"Khi hết giờ" detail:action level:actionLevel]];

	if (prefs.streaming) {
		[items addObject:[self itemWithTitle:@"Streaming bật"
									  detail:@"Chữ về tới đâu hiện tới đó; hợp với model nhanh."
									   level:SXDiagnosticLevelOK]];
	}
	return items;
}

- (NSArray<SXDiagnosticItem *> *)sx_dataItems:(NSDictionary *)snapshot {
	NSMutableArray<SXDiagnosticItem *> *items = [NSMutableArray array];
	if (![snapshot isKindOfClass:[NSDictionary class]]) {
		[items addObject:[self itemWithTitle:@"Không đọc được kho dữ liệu"
									  detail:@"Kiểm tra quyền ghi /var/mobile/Library/SiriX."
									   level:SXDiagnosticLevelProblem]];
		return items;
	}
	NSArray *history = [snapshot[@"history"] isKindOfClass:[NSArray class]] ? snapshot[@"history"] : @[];
	[items addObject:[self itemWithTitle:@"Lịch sử đã lưu"
								  detail:[NSString stringWithFormat:@"%lu lượt trên máy (giữ tối đa 40)",
										  (unsigned long)history.count]
								   level:SXDiagnosticLevelOK]];

	NSDictionary *stats = [snapshot[@"stats"] isKindOfClass:[NSDictionary class]] ? snapshot[@"stats"] : @{};
	NSInteger replaced = [stats[@"replaced"] integerValue];
	NSInteger kept = [stats[@"kept"] integerValue];
	NSInteger timeout = [stats[@"timeout"] integerValue];
	NSInteger failures = [stats[@"error"] integerValue];
	if (replaced + kept + timeout + failures == 0) {
		[items addObject:[self itemWithTitle:@"Chưa có lượt nào"
									  detail:@"Hỏi Siri một câu để có số liệu. Chưa có dữ liệu không có nghĩa là lỗi."
									   level:SXDiagnosticLevelOK]];
		return items;
	}
	[items addObject:[self itemWithTitle:@"Lượt đã thay bằng AI"
								  detail:[NSString stringWithFormat:@"%ld thay · %ld giữ Siri gốc",
										  (long)replaced, (long)kept]
								   level:replaced ? SXDiagnosticLevelOK : SXDiagnosticLevelWarn]];

	if (timeout > 0) {
		[items addObject:[self itemWithTitle:@"Có lượt hết giờ chờ"
									  detail:[NSString stringWithFormat:
											  @"%ld lượt không kịp trong ngân sách đã đặt. Tăng “Trần chờ Siri” hoặc dùng model nhanh hơn.",
											  (long)timeout]
									   level:SXDiagnosticLevelWarn]];
	}
	if (failures > 0) {
		[items addObject:[self itemWithTitle:@"Có lượt lỗi AI"
									  detail:[NSString stringWithFormat:
											  @"%ld lượt. Nhật ký có mã lỗi HTTP và thông báo của máy chủ — dùng nút chia sẻ ở màn Nhật ký nếu cần hỏi.",
											  (long)failures]
									   level:SXDiagnosticLevelWarn]];
	}
	return items;
}

- (void)sx_buildWithSnapshot:(NSDictionary *)snapshot {
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	self.sections = @[[self sx_setupItems:prefs], [self sx_timingItems:prefs], [self sx_dataItems:snapshot]];
	self.sectionTitles = @[@"Thiết lập", @"Thời gian", @"Dữ liệu"];

	NSInteger problems = 0, warnings = 0;
	for (NSArray<SXDiagnosticItem *> *section in self.sections) {
		for (SXDiagnosticItem *item in section) {
			if (item.level == SXDiagnosticLevelProblem) problems++;
			else if (item.level == SXDiagnosticLevelWarn) warnings++;
		}
	}
	if (problems) {
		self.navigationItem.prompt = [NSString stringWithFormat:@"%ld vấn đề cần sửa · %ld lưu ý", (long)problems, (long)warnings];
	} else if (warnings) {
		self.navigationItem.prompt = [NSString stringWithFormat:@"Không có vấn đề · %ld lưu ý", (long)warnings];
	} else {
		self.navigationItem.prompt = @"Mọi thứ đã sẵn sàng";
	}
	[self.table reloadData];
	self.table.backgroundView = nil;
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return 0;
	return (NSInteger)self.sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return nil;
	return self.sectionTitles[(NSUInteger)section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	// Bảng rỗng (chưa có dữ liệu) vẫn gọi hàm này với section 0 — -1 sẽ khớp
	// nhầm và đặt footer dưới một section không tồn tại.
	NSInteger count = (NSInteger)self.sections.count;
	if (count <= 0 || section != count - 1) return nil;
	return @"Chẩn đoán chỉ đọc cấu hình và số liệu trên máy — không gửi câu hỏi nào tới nhà cung cấp AI.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"diagnostic";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.adjustsFontForContentSizeCategory = YES;
		cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
		cell.detailTextLabel.numberOfLines = 0;
	}
	if (indexPath.section < 0 || (NSUInteger)indexPath.section >= self.sections.count) return cell;
	NSArray<SXDiagnosticItem *> *items = self.sections[(NSUInteger)indexPath.section];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= items.count) return cell;
	SXDiagnosticItem *item = items[(NSUInteger)indexPath.row];

	cell.textLabel.text = item.title;
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.detailTextLabel.text = item.detail;

	switch (item.level) {
		case SXDiagnosticLevelOK:
			cell.textLabel.textColor = UIColor.labelColor;
			cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			cell.imageView.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
			cell.imageView.tintColor = [SXUI successColor];
			break;
		case SXDiagnosticLevelWarn:
			cell.textLabel.textColor = UIColor.labelColor;
			cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.circle.fill"];
			cell.imageView.tintColor = [SXUI warningColor];
			break;
		case SXDiagnosticLevelProblem:
			cell.textLabel.textColor = [SXUI dangerColor];
			cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle.fill"];
			cell.imageView.tintColor = [SXUI dangerColor];
			break;
	}
	cell.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", item.title, item.detail];
	return cell;
}

#pragma mark - Báo cáo

- (NSString *)sx_reportText {
	NSMutableString *report = [[NSMutableString alloc] init];
	[report appendFormat:@"SiriX %@ — chẩn đoán\n\n", SX_VERSION];
	for (NSUInteger i = 0; i < self.sections.count; i++) {
		[report appendFormat:@"%@\n", i < self.sectionTitles.count ? self.sectionTitles[i] : @""];
		for (SXDiagnosticItem *item in self.sections[i]) {
			NSString *mark = item.level == SXDiagnosticLevelOK ? @"[OK]"
				: item.level == SXDiagnosticLevelWarn ? @"[!]" : @"[X]";
			[report appendFormat:@"%@ %@ — %@\n", mark, item.title, item.detail ?: @""];
		}
		[report appendString:@"\n"];
	}
	return report;
}

- (void)sx_shareReport {
	NSString *text = [self sx_reportText];
	UIActivityViewController *activity =
		[[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:activity animated:YES completion:nil];
}

@end
