#import "SXHistoryController.h"
#import "SXStore.h"
#import "SXUISupport.h"
#import "SXLog.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#pragma mark - Chi tiết một lượt

@interface SXHistoryDetailController : PSViewController
@property (nonatomic, copy) NSDictionary *item;
@property (nonatomic, copy) void (^onDelete)(NSDictionary *item);
@end

@implementation SXHistoryDetailController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Chi tiết";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.navigationItem.prompt = [SXUI relativeStringForDate:self.item[@"date"]];

	NSString *question = [self.item[@"q"] isKindOfClass:[NSString class]] ? self.item[@"q"] : @"";
	NSString *answer = [self.item[@"a"] isKindOfClass:[NSString class]] ? self.item[@"a"] : @"";

	UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
	text.translatesAutoresizingMaskIntoConstraints = NO;
	text.editable = NO;
	text.selectable = YES;
	text.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	text.layer.cornerRadius = 12;
	if (@available(iOS 13.0, *)) text.layer.cornerCurve = kCACornerCurveContinuous;
	text.textContainerInset = UIEdgeInsetsMake(16, 14, 16, 14);

	NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];
	NSDictionary *roleAttrs = @{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
								NSForegroundColorAttributeName: UIColor.secondaryLabelColor};
	NSDictionary *bodyAttrs = @{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
								NSForegroundColorAttributeName: UIColor.labelColor};
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:@"BẠN HỎI\n" attributes:roleAttrs]];
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:[question stringByAppendingString:@"\n\n"] attributes:bodyAttrs]];
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:@"SIRIX TRẢ LỜI\n" attributes:roleAttrs]];
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:answer attributes:bodyAttrs]];
	text.attributedText = content;

	[self.view addSubview:text];
	[NSLayoutConstraint activateConstraints:@[
		[text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
		[text.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[text.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
	]];

	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(sx_share)],
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(sx_confirmDelete)],
	];
}

- (NSString *)sx_plainText {
	return [NSString stringWithFormat:@"Bạn: %@\n\nSiriX: %@", self.item[@"q"] ?: @"", self.item[@"a"] ?: @""];
}

- (void)sx_share {
	UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[self sx_plainText]]
																		 applicationActivities:nil];
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
	[self presentViewController:activity animated:YES completion:nil];
}

- (void)sx_confirmDelete {
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá lượt này?"
			message:@"Không thể hoàn tác."
		confirmText:@"Xoá"
			 action:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (strongSelf.onDelete) strongSelf.onDelete(strongSelf.item);
		[strongSelf.navigationController popViewControllerAnimated:YES];
	}];
}

@end

#pragma mark - Danh sách

@interface SXHistoryController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSArray<NSDictionary *> *allItems;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections; // @{@"title", @"items"}
@property (nonatomic, copy) NSString *query;
@end

@implementation SXHistoryController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Lịch sử";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.allItems = @[];
	self.sections = @[];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 64;
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
	self.searchBar.placeholder = @"Tìm trong lịch sử";
	self.searchBar.delegate = self;
	self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.table.tableHeaderView = self.searchBar;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"trash"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_confirmClear)];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self sx_reloadHistory];
}

#pragma mark - Dữ liệu

- (NSString *)sx_dayTitleForDate:(NSDate *)date {
	if (![date isKindOfClass:[NSDate class]]) return @"Không rõ ngày";
	NSCalendar *calendar = [NSCalendar currentCalendar];
	if ([calendar isDateInToday:date]) return @"Hôm nay";
	if ([calendar isDateInYesterday:date]) return @"Hôm qua";
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterLongStyle;
	formatter.timeStyle = NSDateFormatterNoStyle;
	return [formatter stringFromDate:date] ?: @"Không rõ ngày";
}

- (void)sx_rebuildSections {
	NSString *query = [self.query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *lowerQuery = query.lowercaseString;

	NSMutableArray<NSDictionary *> *flat = [NSMutableArray array];
	for (NSDictionary *item in self.allItems) {
		if (!lowerQuery.length) {
			[flat addObject:item];
			continue;
		}
		NSString *q = [item[@"q"] isKindOfClass:[NSString class]] ? item[@"q"] : @"";
		NSString *a = [item[@"a"] isKindOfClass:[NSString class]] ? item[@"a"] : @"";
		if ([q.lowercaseString containsString:lowerQuery] || [a.lowercaseString containsString:lowerQuery]) {
			[flat addObject:item];
		}
	}

	NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
	NSMutableArray<NSDictionary *> *current = nil;
	NSString *currentTitle = nil;
	for (NSDictionary *item in flat) {
		NSString *title = [self sx_dayTitleForDate:item[@"date"]];
		if (!current || ![title isEqualToString:currentTitle]) {
			current = [NSMutableArray array];
			currentTitle = title;
			[sections addObject:@{@"title": title, @"items": current}];
		}
		[current addObject:item];
	}

	self.sections = sections;
	self.navigationItem.prompt = flat.count
		? [NSString stringWithFormat:@"%@ lượt · lưu trên thiết bị", [SXUI groupedNumber:(NSInteger)flat.count]]
		: nil;
	[self.table reloadData];
	[self sx_updateEmptyState];
}

- (void)sx_updateEmptyState {
	if (self.allItems.count == 0) {
		self.table.backgroundView = [SXUI emptyStateWithSymbol:@"clock.arrow.circlepath"
														 title:@"Chưa có lịch sử"
													   message:@"Lịch sử chỉ lưu khi SiriX thay được phản hồi bằng câu trả lời AI, và tắt ở chế độ “Không lưu lịch sử”."];
		return;
	}
	if (self.sections.count == 0) {
		self.table.backgroundView = [SXUI emptyStateWithSymbol:@"magnifyingglass"
														 title:@"Không tìm thấy"
													   message:@"Thử từ khoá khác hoặc xoá ô tìm kiếm."];
		return;
	}
	self.table.backgroundView = nil;
}

- (void)sx_reloadHistory {
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!snapshot) {
				[SXUI alertOn:strongSelf
						title:@"Không đọc được lịch sử"
					  message:@"Kiểm tra quyền ghi thư mục /var/mobile/Library/SiriX rồi thử lại."];
				return;
			}
			NSArray *history = [snapshot[@"history"] isKindOfClass:[NSArray class]] ? snapshot[@"history"] : @[];
			strongSelf.allItems = [[history reverseObjectEnumerator] allObjects];
			[strongSelf sx_rebuildSections];
		});
	});
}

- (NSDictionary *)sx_itemAtIndexPath:(NSIndexPath *)indexPath {
	if ((NSUInteger)indexPath.section >= self.sections.count) return nil;
	NSArray *items = self.sections[(NSUInteger)indexPath.section][@"items"];
	if ((NSUInteger)indexPath.row >= items.count) return nil;
	return items[(NSUInteger)indexPath.row];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if ((NSUInteger)section >= self.sections.count) return 0;
	return (NSInteger)[self.sections[(NSUInteger)section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if ((NSUInteger)section >= self.sections.count) return nil;
	return self.sections[(NSUInteger)section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"turn"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"turn"];
	}
	NSDictionary *item = [self sx_itemAtIndexPath:indexPath];
	NSString *question = [item[@"q"] isKindOfClass:[NSString class]] ? item[@"q"] : @"";
	NSString *answer = [item[@"a"] isKindOfClass:[NSString class]] ? item[@"a"] : @"";
	cell.textLabel.text = [SXUI truncate:question limit:140];
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.detailTextLabel.text = answer;
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *item = [self sx_itemAtIndexPath:indexPath];
	if (!item) return;
	SXHistoryDetailController *detail = [[SXHistoryDetailController alloc] init];
	detail.item = item;
	__weak typeof(self) weakSelf = self;
	detail.onDelete = ^(NSDictionary *deleted) {
		[weakSelf sx_deleteItem:deleted];
	};
	[self.navigationController pushViewController:detail animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
	trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *item = [self sx_itemAtIndexPath:indexPath];
	if (!item) return nil;
	__weak typeof(self) weakSelf = self;
	UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																		 title:@"Xoá"
																	   handler:^(UIContextualAction *action,
																				 UIView *sourceView,
																				 void (^completionHandler)(BOOL)) {
		(void)action; (void)sourceView;
		[weakSelf sx_deleteItem:item];
		completionHandler(YES);
	}];
	delete.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

#pragma mark - Xoá

- (void)sx_deleteItem:(NSDictionary *)item {
	NSString *identifier = [item[@"id"] isKindOfClass:[NSString class]] ? item[@"id"] : nil;
	if (!identifier.length) return;
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		BOOL ok = [[SXStore shared] deleteHistoryID:identifier];
		if (ok) notify_post("com.sirix.tweak/resetHistory");
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (ok) {
				[SXUI tapFeedback];
				[strongSelf sx_reloadHistory];
			} else {
				[SXUI alertOn:strongSelf title:@"Không xoá được" message:@"Kiểm tra quyền ghi thư mục lưu trữ rồi thử lại."];
			}
		});
	});
}

- (void)sx_confirmClear {
	if (!self.allItems.count) {
		[SXUI alertOn:self title:@"Lịch sử trống" message:nil];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá toàn bộ lịch sử?"
			message:@"Không thể hoàn tác. Các câu đang chờ sẽ không được thêm lại."
		confirmText:@"Xoá tất cả"
			 action:^{
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] clearHistory];
			if (ok) notify_post("com.sirix.tweak/resetHistory");
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				if (ok) [strongSelf sx_reloadHistory];
				else [SXUI alertOn:strongSelf title:@"Không xoá được" message:@"Kiểm tra quyền ghi thư mục lưu trữ."];
			});
		});
	}];
}

#pragma mark - Tìm kiếm

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	(void)searchBar;
	self.query = searchText;
	[self sx_rebuildSections];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.query = nil;
	[searchBar resignFirstResponder];
	[self sx_rebuildSections];
}

@end
