#import "SXMemoryController.h"
#import "SXNavigationSupport.h"
#import "SXUISupport.h"
#import "SXToolCatalog.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>

#pragma mark - Ô ghi chú

/// Ô tự vẽ: nội dung có thể dài nhiều dòng, kèm ngày + nhãn ở dòng phụ.
/// Không dùng PSTableCell để chữ xuống dòng đúng thay vì bị cắt cụt.
@interface SXMemoryCell : UITableViewCell
@end

@implementation SXMemoryCell {
	UILabel *_textLabel;
	UILabel *_metaLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;
	self.selectionStyle = UITableViewCellSelectionStyleDefault;
	self.backgroundColor = [SXUI cardColor];

	_textLabel = [[UILabel alloc] init];
	_textLabel.numberOfLines = 0;
	_textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_textLabel.adjustsFontForContentSizeCategory = YES;

	_metaLabel = [[UILabel alloc] init];
	_metaLabel.numberOfLines = 1;
	_metaLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	_metaLabel.adjustsFontForContentSizeCategory = YES;
	_metaLabel.textColor = UIColor.secondaryLabelColor;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_textLabel, _metaLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 4;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];
	UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:4],
		[stack.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-4],
		[stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
	]];
	return self;
}

- (void)configureWithNote:(SXMemoryNote *)note {
	_textLabel.text = note.text;
	NSMutableArray<NSString *> *bits = [NSMutableArray array];
	if (note.date) [bits addObject:[SXUI relativeStringForDate:note.date]];
	if (note.tags.length) [bits addObject:[NSString stringWithFormat:@"#%@", note.tags]];
	[bits addObject:[NSString stringWithFormat:@"id %@", note.identifier]];
	_metaLabel.text = [bits componentsJoinedByString:@" · "];
	self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", note.text, _metaLabel.text ?: @""];
}

@end

#pragma mark - Màn hình

@interface SXMemoryController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) NSArray<SXMemoryNote *> *allNotes;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *loadError;
@property (nonatomic) NSUInteger loadGeneration;
@end

@implementation SXMemoryController

- (void)loadView {
	UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	table.dataSource = self;
	table.delegate = self;
	table.rowHeight = UITableViewAutomaticDimension;
	table.estimatedRowHeight = 64;
	table.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.view = table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Ghi nhớ";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	UISearchBar *search = [[UISearchBar alloc] init];
	search.placeholder = @"Tìm trong ghi nhớ";
	search.delegate = self;
	search.searchBarStyle = UISearchBarStyleMinimal;
	search.text = self.query;
	((UITableView *)self.view).tableHeaderView = search;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
							  target:self
							  action:@selector(sx_confirmClear)];
	[self sx_loadNotes];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Ghi nhớ");
	[self sx_loadNotes];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, @"Ghi nhớ", @"không đọc được danh sách ghi chú");
}

#pragma mark - Dữ liệu

/// Đọc trên hàng đợi riêng: tệp nằm ở /var/mobile và có thể chậm quyền truy cập.
/// Số thế hệ để kết quả đọc cũ không ghi đè danh sách mới hơn.
- (void)sx_loadNotes {
	NSUInteger generation = ++self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray<SXMemoryNote *> *notes = [[SXMemory shared] notes];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || generation != strongSelf.loadGeneration) return;
			strongSelf.allNotes = notes;
			[strongSelf sx_refresh];
		});
	});
}

- (NSArray<SXMemoryNote *> *)sx_visibleNotes {
	NSString *query = [self.query stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
	if (!query.length) return self.allNotes ?: @[];
	NSMutableArray<SXMemoryNote *> *matched = [NSMutableArray array];
	for (SXMemoryNote *note in self.allNotes) {
		BOOL hit = [note.text.lowercaseString containsString:query] ||
				   [note.tags.lowercaseString containsString:query] ||
				   [note.identifier.lowercaseString containsString:query];
		if (hit) [matched addObject:note];
	}
	return matched;
}

- (void)sx_refresh {
	UITableView *table = (UITableView *)self.view;
	[self sx_updateChrome];
	[table reloadData];
	[self sx_updateEmptyState];
}

/// Chân trang tiêu đề nói rõ dung lượng: người dùng cần biết AI đang giữ bao nhiêu.
- (void)sx_updateChrome {
	UITableView *table = (UITableView *)self.view;
	NSInteger total = (NSInteger)self.allNotes.count;
	if (!total) {
		self.navigationItem.prompt = nil;
		return;
	}
	NSInteger shown = (NSInteger)[self sx_visibleNotes].count;
	NSString *summary = self.query.length && (NSUInteger)shown != (NSUInteger)total
		? [NSString stringWithFormat:@"%ld/%ld ghi chú · trần %lu", (long)shown, (long)total,
			(unsigned long)[SXMemory capacity]]
		: [NSString stringWithFormat:@"%ld/%lu ghi chú", (long)total,
			(unsigned long)[SXMemory capacity]];
	self.navigationItem.prompt = summary;
	table.accessibilityLabel = summary;
}

- (void)sx_updateEmptyState {
	UITableView *table = (UITableView *)self.view;
	if (!self.allNotes.count) {
		table.backgroundView = [SXUI emptyStateWithSymbol:@"brain.head.profile"
													title:@"Chưa có ghi nhớ nào"
												  message:@"Khi bạn nói “nhớ giúp mình…”, AI ghi lại ở đây. "
														   @"Nội dung chỉ nằm trên máy này."];
	} else if (![self sx_visibleNotes].count) {
		table.backgroundView = [SXUI emptyStateWithSymbol:@"magnifyingglass"
													title:@"Không tìm thấy"
												  message:[NSString stringWithFormat:@"Không có ghi chú nào khớp “%@”.",
														   [SXUI truncate:self.query limit:40]]];
	} else {
		table.backgroundView = nil;
	}
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	return (NSInteger)[self sx_visibleNotes].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	if (self.loadError.length) return self.loadError;
	if (!self.allNotes.count) return nil;
	return @"AI chỉ đọc lại những ghi chú này khi bạn hỏi bằng giọng nói hoặc chữ. "
		   @"Chạm để xem đầy đủ, vuốt trái để xoá. Tắt công cụ “Ghi nhớ” nếu không muốn AI lưu thêm.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray<SXMemoryNote *> *notes = [self sx_visibleNotes];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= notes.count) {
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}
	static NSString *identifier = @"SXMemoryCell";
	SXMemoryCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[SXMemoryCell alloc] initWithStyle:UITableViewCellStyleDefault
											reuseIdentifier:identifier];
	[cell configureWithNote:notes[(NSUInteger)indexPath.row]];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSArray<SXMemoryNote *> *notes = [self sx_visibleNotes];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= notes.count) return;
	SXMemoryNote *note = notes[(NSUInteger)indexPath.row];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ghi nhớ"
																  message:[NSString stringWithFormat:@"%@\n\nid %@%@",
																		   note.text, note.identifier,
																		   note.date ? [NSString stringWithFormat:@"\n%@",
																				[SXUI relativeStringForDate:note.date]] : @""]
														   preferredStyle:UIAlertControllerStyleActionSheet];
	[alert addAction:[UIAlertAction actionWithTitle:@"Sao chép" style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[SXUI copyText:note.text];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Xoá ghi chú này" style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;
		[self sx_deleteNote:note];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
	alert.popoverPresentationController.sourceView = tableView;
	alert.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
	[self presentViewController:alert animated:YES completion:nil];
}

/// Vuốt trái để xoá nhanh, cùng một hành vi với trang Lịch sử.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray<SXMemoryNote *> *notes = [self sx_visibleNotes];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= notes.count) return nil;
	SXMemoryNote *note = notes[(NSUInteger)indexPath.row];
	UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
																		 title:@"Xoá"
																	   handler:^(UIContextualAction *action,
																				 UIView *view,
																				 void (^completion)(BOOL)) {
		(void)action; (void)view;
		completion([self sx_deleteNote:note]);
	}];
	delete.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

#pragma mark - Xoá

- (BOOL)sx_deleteNote:(SXMemoryNote *)note {
	BOOL ok = [[SXMemory shared] removeNoteWithIdentifier:note.identifier];
	if (!ok) {
		[SXUI alertOn:self title:@"Không xoá được" message:@"Kiểm tra quyền ghi thư mục /var/mobile/Library/SiriX."];
		return NO;
	}
	NSMutableArray *remaining = [self.allNotes mutableCopy] ?: [NSMutableArray array];
	[remaining removeObject:note];
	self.allNotes = remaining;
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"đã xoá ghi nhớ %@", note.identifier);
	[self sx_refresh];
	return YES;
}

- (void)sx_confirmClear {
	if (!self.allNotes.count) {
		[SXUI alertOn:self title:@"Chưa có ghi nhớ nào" message:nil];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá toàn bộ ghi nhớ?"
			message:[NSString stringWithFormat:@"Xoá %lu ghi chú AI đã lưu trên máy. Không thể hoàn tác.",
					 (unsigned long)self.allNotes.count]
		confirmText:@"Xoá tất cả"
			 action:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		NSUInteger removed = [[SXMemory shared] removeAllNotes];
		strongSelf.allNotes = @[];
		[SXUI tapFeedback];
		SXLogInf(@"pref", @"đã xoá toàn bộ %lu ghi nhớ", (unsigned long)removed);
		[strongSelf sx_refresh];
	}];
}

#pragma mark - Tìm kiếm

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	(void)searchBar;
	self.query = searchText;
	// Debounce: gõ nhanh không dựng lại bảng sau mỗi ký tự.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sx_applySearch) object:nil];
	[self performSelector:@selector(sx_applySearch) withObject:nil afterDelay:0.15];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
	[self sx_applySearch];
}

- (void)sx_applySearch {
	[self sx_refresh];
}

@end
