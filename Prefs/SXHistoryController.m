#import "SXHistoryController.h"
#import "SXNavigationSupport.h"
#import "SXStore.h"
#import "SXUISupport.h"
#import "SXLog.h"
#import <notify.h>
#import <UIKit/UIKit.h>

static NSString *SXHistoryText(id value) {
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSString *SXHistoryTimeText(NSDate *date) {
	if (![date isKindOfClass:[NSDate class]]) return @"";
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterNoStyle;
	formatter.timeStyle = NSDateFormatterShortStyle;
	if ([NSCalendar.currentCalendar isDateInToday:date]) return [formatter stringFromDate:date];
	formatter.dateStyle = NSDateFormatterShortStyle;
	return [formatter stringFromDate:date];
}

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

	NSString *question = SXHistoryText(self.item[@"q"]);
	NSString *answer = SXHistoryText(self.item[@"a"]);
	NSDate *date = [self.item[@"date"] isKindOfClass:[NSDate class]] ? self.item[@"date"] : nil;
	self.navigationItem.prompt = [SXUI relativeStringForDate:date];

	UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
	text.translatesAutoresizingMaskIntoConstraints = NO;
	text.editable = NO;
	text.selectable = YES;
	text.alwaysBounceVertical = YES;
	text.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	text.layer.cornerRadius = 12;
	text.layer.cornerCurve = kCACornerCurveContinuous;
	text.textContainerInset = UIEdgeInsetsMake(16, 14, 16, 14);
	text.adjustsFontForContentSizeCategory = YES;

	NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];
	NSDictionary *roleAttrs = @{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
								NSForegroundColorAttributeName: UIColor.secondaryLabelColor};
	NSDictionary *bodyAttrs = @{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
								NSForegroundColorAttributeName: UIColor.labelColor};
	NSString *questionBody = question.length ? question : @"(không có nội dung)";
	NSString *answerBody = answer.length ? answer : @"(SiriX không trả lời)";
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:@"BẠN HỎI\n" attributes:roleAttrs]];
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:[questionBody stringByAppendingString:@"\n\n"]
																   attributes:bodyAttrs]];
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:@"SIRIX TRẢ LỜI\n" attributes:roleAttrs]];
	[content appendAttributedString:[[NSAttributedString alloc] initWithString:answerBody attributes:bodyAttrs]];
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
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
										style:UIBarButtonItemStylePlain
									   target:self
									   action:@selector(sx_copy)],
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"]
										style:UIBarButtonItemStylePlain
									   target:self
									   action:@selector(sx_confirmDelete)],
	];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, @"Chi tiết lượt", @"không đọc được nội dung lượt này");
}

- (NSString *)sx_plainText {
	return [NSString stringWithFormat:@"Bạn: %@\n\nSiriX: %@",
			SXHistoryText(self.item[@"q"]), SXHistoryText(self.item[@"a"])];
}

- (void)sx_share {
	UIActivityViewController *activity =
		[[UIActivityViewController alloc] initWithActivityItems:@[[self sx_plainText]]
										 applicationActivities:nil];
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
	[self presentViewController:activity animated:YES completion:nil];
}

- (void)sx_copy {
	if (![NSThread isMainThread]) return;
	UIPasteboard.generalPasteboard.string = [self sx_plainText];
	[SXUI tapFeedback];
	UIBarButtonItem *item = self.navigationItem.rightBarButtonItems.count > 1
		? self.navigationItem.rightBarButtonItems[1] : nil;
	if (!item) return;
	UIImage *original = item.image;
	item.image = [UIImage systemImageNamed:@"checkmark"];
	__weak typeof(item) weakItem = item;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		weakItem.image = original;
	});
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

#pragma mark - Ô trong danh sách

@interface SXHistoryCell : UITableViewCell
@property (nonatomic, strong) UILabel *questionLabel;
@property (nonatomic, strong) UILabel *answerLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@end

@implementation SXHistoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	self.selectionStyle = UITableViewCellSelectionStyleDefault;

	_questionLabel = [[UILabel alloc] init];
	_questionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_questionLabel.adjustsFontForContentSizeCategory = YES;
	_questionLabel.numberOfLines = 2;
	_questionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	_questionLabel.textColor = UIColor.labelColor;
	[_questionLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
												   forAxis:UILayoutConstraintAxisHorizontal];

	_timeLabel = [[UILabel alloc] init];
	_timeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	_timeLabel.adjustsFontForContentSizeCategory = YES;
	_timeLabel.textColor = UIColor.tertiaryLabelColor;
	_timeLabel.textAlignment = NSTextAlignmentRight;
	_timeLabel.numberOfLines = 1;
	[_timeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
												forAxis:UILayoutConstraintAxisHorizontal];

	_answerLabel = [[UILabel alloc] init];
	_answerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	_answerLabel.adjustsFontForContentSizeCategory = YES;
	_answerLabel.numberOfLines = 2;
	_answerLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	_answerLabel.textColor = UIColor.secondaryLabelColor;

	UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[_questionLabel, _timeLabel]];
	topRow.axis = UILayoutConstraintAxisHorizontal;
	topRow.alignment = UIStackViewAlignmentFirstBaseline;
	topRow.spacing = 8;

	UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, _answerLabel]];
	column.axis = UILayoutConstraintAxisVertical;
	column.spacing = 4;
	column.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:column];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[column.topAnchor constraintEqualToAnchor:margins.topAnchor],
		[column.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
		[column.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[column.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
	]];
	return self;
}

- (void)configureWithItem:(NSDictionary *)item {
	NSString *question = SXHistoryText(item[@"q"]);
	NSString *answer = SXHistoryText(item[@"a"]);
	self.questionLabel.text = question.length ? question : @"(câu hỏi trống)";
	self.answerLabel.text = answer.length ? answer : @"(không có câu trả lời)";
	self.answerLabel.hidden = !answer.length;
	self.timeLabel.text = SXHistoryTimeText(item[@"date"]);

	self.accessibilityLabel = self.questionLabel.text;
	self.accessibilityValue = [NSString stringWithFormat:@"%@ · %@", self.timeLabel.text ?: @"", self.answerLabel.text ?: @""];
	self.accessibilityHint = @"Mở chi tiết";
}

@end

#pragma mark - Danh sách

@interface SXHistoryController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSArray<NSDictionary *> *allItems;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections; // @{@"title", @"items"}
@property (nonatomic, copy) NSString *query;
/// Chỉ hiện kết quả của lần đọc kho mới nhất.
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) BOOL loadedOnce;
@end

@implementation SXHistoryController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Lịch sử";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.allItems = @[];
	self.sections = @[];

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
	self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.searchBar.placeholder = @"Tìm trong lịch sử";
	self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
	self.searchBar.delegate = self;
	self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
	self.searchBar.returnKeyType = UIReturnKeyDone;
	[self.searchBar setImage:[UIImage systemImageNamed:@"magnifyingglass"]
			forSearchBarIcon:UISearchBarIconSearch
					   state:UIControlStateNormal];
	[self.view addSubview:self.searchBar];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 68;
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.table registerClass:[SXHistoryCell class] forCellReuseIdentifier:@"turn"];
	[self.view addSubview:self.table];

	UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
	[refresh addTarget:self action:@selector(sx_handleRefresh:) forControlEvents:UIControlEventValueChanged];
	self.table.refreshControl = refresh;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"trash"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_confirmClear)];
	self.navigationItem.rightBarButtonItem.enabled = NO;

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
		[self.searchBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
		[self.searchBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
		[self.table.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Lịch sử");
	// Lần đầu: đọc kho ngay để không thấy chớp màn hình trống.
	if (!self.loadedOnce) [self sx_showLoadingState];
	[self sx_reloadHistory];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, @"Lịch sử hội thoại", @"chưa có lượt nào hoặc không đọc được kho");
}

#pragma mark - Dữ liệu

- (void)sx_showLoadingState {
	UIActivityIndicatorView *spinner =
		[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	[spinner startAnimating];
	self.table.backgroundView = spinner;
}

- (NSString *)sx_dayTitleForDate:(NSDate *)date {
	if (![date isKindOfClass:[NSDate class]]) return @"Không rõ ngày";
	NSCalendar *calendar = NSCalendar.currentCalendar;
	if ([calendar isDateInToday:date]) return @"Hôm nay";
	if ([calendar isDateInYesterday:date]) return @"Hôm qua";
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateStyle = NSDateFormatterLongStyle;
	formatter.timeStyle = NSDateFormatterNoStyle;
	return [formatter stringFromDate:date] ?: @"Không rõ ngày";
}

- (void)sx_rebuildSections {
	NSString *query = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *lowerQuery = query.lowercaseString;

	NSMutableArray<NSDictionary *> *flat = [NSMutableArray array];
	for (NSDictionary *item in self.allItems) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		if (!lowerQuery.length) {
			[flat addObject:item];
			continue;
		}
		NSString *question = SXHistoryText(item[@"q"]);
		NSString *answer = SXHistoryText(item[@"a"]);
		if ([question.lowercaseString containsString:lowerQuery] ||
			[answer.lowercaseString containsString:lowerQuery]) {
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

	// Đếm số lượt trong từng nhóm để tiêu đề mục có ngữ cảnh.
	NSMutableArray<NSDictionary *> *titled = [NSMutableArray array];
	for (NSDictionary *section in sections) {
		NSArray *items = section[@"items"];
		[titled addObject:@{@"title": [NSString stringWithFormat:@"%@ · %lu lượt",
									  section[@"title"], (unsigned long)items.count],
							@"items": items}];
	}

	self.sections = titled;
	if (!query.length) {
		self.navigationItem.prompt = flat.count
			? [NSString stringWithFormat:@"%@ lượt · lưu trên thiết bị", [SXUI groupedNumber:(NSInteger)flat.count]]
			: nil;
	} else {
		self.navigationItem.prompt = [NSString stringWithFormat:@"%@/%@ lượt khớp “%@”",
									  [SXUI groupedNumber:(NSInteger)flat.count],
									  [SXUI groupedNumber:(NSInteger)self.allItems.count],
									  [SXUI truncate:query limit:24]];
	}
	self.navigationItem.rightBarButtonItem.enabled = self.allItems.count > 0;
	[self.table reloadData];
	[self sx_updateEmptyState];
}

- (void)sx_updateEmptyState {
	if (!self.allItems.count) {
		self.table.backgroundView = [SXUI emptyStateWithSymbol:@"clock.arrow.circlepath"
														 title:@"Chưa có lịch sử"
													   message:@"Lịch sử chỉ lưu khi SiriX thay được phản hồi bằng câu trả lời AI, và tắt ở chế độ “Không lưu lịch sử”."];
		return;
	}
	if (!self.sections.count) {
		self.table.backgroundView = [SXUI emptyStateWithSymbol:@"magnifyingglass"
														 title:@"Không tìm thấy"
													   message:@"Thử từ khoá khác hoặc xoá ô tìm kiếm."];
		return;
	}
	self.table.backgroundView = nil;
}

- (void)sx_reloadHistory {
	NSUInteger generation = ++self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (generation != strongSelf.loadGeneration) return; // đã có lượt đọc mới hơn
			strongSelf.loadedOnce = YES;
			if (![snapshot isKindOfClass:[NSDictionary class]]) {
				strongSelf.table.backgroundView = [SXUI emptyStateWithSymbol:@"exclamationmark.triangle"
																		title:@"Không đọc được lịch sử"
																	  message:@"Kiểm tra quyền ghi thư mục /var/mobile/Library/SiriX rồi kéo xuống để thử lại."];
				SXLogErr(@"pref", @"đọc lịch sử thất bại");
				return;
			}
			id raw = snapshot[@"history"];
			NSArray *history = [raw isKindOfClass:[NSArray class]] ? raw : @[];
			// Kho lưu cũ → mới; danh sách hiển thị mới nhất trước.
			strongSelf.allItems = [[history reverseObjectEnumerator] allObjects];
			[strongSelf sx_rebuildSections];
		});
	});
}

- (void)sx_handleRefresh:(UIRefreshControl *)refresh {
	[self sx_reloadHistory];
	// Kết thúc sau một nhịp ngắn để người dùng thấy phản hồi dù kho đọc rất nhanh.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[refresh endRefreshing];
	});
}

- (NSDictionary *)sx_itemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || (NSUInteger)indexPath.section >= self.sections.count) return nil;
	NSArray *items = self.sections[(NSUInteger)indexPath.section][@"items"];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= items.count) return nil;
	return items[(NSUInteger)indexPath.row];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return 0;
	return (NSInteger)[self.sections[(NSUInteger)section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section < 0 || (NSUInteger)section >= self.sections.count) return nil;
	return self.sections[(NSUInteger)section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SXHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"turn" forIndexPath:indexPath];
	NSDictionary *item = [self sx_itemAtIndexPath:indexPath];
	if (item) [cell configureWithItem:item];
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

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
	leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *item = [self sx_itemAtIndexPath:indexPath];
	if (!item) return nil;
	UIContextualAction *copy = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
																	  title:@"Chép"
																	handler:^(UIContextualAction *action,
																			  UIView *sourceView,
																			  void (^completionHandler)(BOOL)) {
		(void)action; (void)sourceView;
		UIPasteboard.generalPasteboard.string =
			[NSString stringWithFormat:@"Bạn: %@\n\nSiriX: %@",
			 SXHistoryText(item[@"q"]), SXHistoryText(item[@"a"])];
		[SXUI tapFeedback];
		completionHandler(YES);
	}];
	copy.image = [UIImage systemImageNamed:@"doc.on.doc"];
	copy.backgroundColor = [SXUI accentColor];
	return [UISwipeActionsConfiguration configurationWithActions:@[copy]];
}

#pragma mark - Xoá

- (void)sx_deleteItem:(NSDictionary *)item {
	NSString *identifier = [item[@"id"] isKindOfClass:[NSString class]] ? item[@"id"] : nil;
	if (!identifier.length) {
		[SXUI alertOn:self title:@"Không xoá được" message:@"Lượt này thiếu mã định danh — hãy xoá toàn bộ lịch sử."];
		return;
	}
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		BOOL ok = [[SXStore shared] deleteHistoryID:identifier];
		if (ok) notify_post("com.sirix.tweak/resetHistory");
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!ok) {
				[SXUI alertOn:strongSelf
						title:@"Không xoá được"
					  message:@"Kiểm tra quyền ghi thư mục lưu trữ rồi thử lại."];
				return;
			}
			[SXUI tapFeedback];
			// Gỡ ngay khỏi danh sách đang hiển thị để không phải chờ đọc lại kho.
			NSMutableArray *remaining = [NSMutableArray arrayWithCapacity:strongSelf.allItems.count];
			for (NSDictionary *existing in strongSelf.allItems) {
				if ([existing[@"id"] isEqual:identifier]) continue;
				[remaining addObject:existing];
			}
			strongSelf.allItems = remaining;
			[strongSelf sx_rebuildSections];
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
			message:[NSString stringWithFormat:@"Xoá %@ lượt đã lưu và cả ngữ cảnh SiriX đang ghi nhớ. Không thể hoàn tác.",
					 [SXUI groupedNumber:(NSInteger)self.allItems.count]]
		confirmText:@"Xoá tất cả"
			 action:^{
		__block BOOL ok = NO;
		NSUInteger generation = ++weakSelf.loadGeneration;
		dispatch_sync([SXStore queue], ^{ ok = [[SXStore shared] clearHistory]; });
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || generation != strongSelf.loadGeneration) return;
			if (!ok) {
				[SXUI alertOn:strongSelf title:@"Không xoá được" message:@"Kiểm tra quyền ghi thư mục lưu trữ."];
				return;
			}
			notify_post("com.sirix.tweak/resetHistory");
			strongSelf.allItems = @[];
			strongSelf.searchBar.text = @"";
			strongSelf.query = nil;
			[strongSelf sx_rebuildSections];
			[SXUI tapFeedback];
			SXLogInf(@"pref", @"đã xoá toàn bộ lịch sử trên thiết bị");
		});
	}];
}

#pragma mark - Tìm kiếm

- (void)sx_scheduleSearch {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sx_applySearch) object:nil];
	[self performSelector:@selector(sx_applySearch) withObject:nil afterDelay:0.15];
}

- (void)sx_applySearch {
	self.query = self.searchBar.text;
	[self sx_rebuildSections];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	(void)searchBar; (void)searchText;
	[self sx_scheduleSearch];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sx_applySearch) object:nil];
	searchBar.text = @"";
	self.query = nil;
	[searchBar resignFirstResponder];
	[self sx_rebuildSections];
}

@end
