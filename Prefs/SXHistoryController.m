#import "SXHistoryController.h"
#import "SXStore.h"
#import "SXPrefs.h"
#import <notify.h>
#import <UIKit/UIKit.h>

@interface SXHistoryDetailController : PSViewController
@property (nonatomic, copy) NSDictionary *item;
@property (nonatomic, copy) void (^onDelete)(NSDictionary *);
@end
@implementation SXHistoryDetailController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Chi tiết hội thoại";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
	text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	text.editable = NO;
	text.selectable = YES;
	text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	text.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
	text.text = [NSString stringWithFormat:@"Bạn: %@\n\nSiriX: %@", self.item[@"q"] ?: @"", self.item[@"a"] ?: @""];
	[self.view addSubview:text];
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:@"Sao chép" style:UIBarButtonItemStylePlain target:self action:@selector(copyTurn)],
		[[UIBarButtonItem alloc] initWithTitle:@"Xóa" style:UIBarButtonItemStylePlain target:self action:@selector(confirmDelete)],
	];
}
- (void)copyTurn {
	UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"Bạn: %@\n\nSiriX: %@", self.item[@"q"] ?: @"", self.item[@"a"] ?: @""];
}
- (void)confirmDelete {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa mục này?" message:@"Không thể hoàn tác." preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		(void)action;
		typeof(self) self = weakSelf;
		if (!self) return;
		if (self.onDelete) self.onDelete(self.item);
		[self.navigationController popViewControllerAnimated:YES];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end

@interface SXHistoryController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSDictionary *> *items;
@end

@implementation SXHistoryController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Lịch sử hội thoại";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.items = @[];
	self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.table.dataSource = self;
	self.table.delegate = self;
	[self.view addSubview:self.table];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Xóa tất cả" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadHistory]; }
- (void)showError {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Không thể truy cập lịch sử" message:@"Kiểm tra quyền ghi kho SiriX rồi thử lại." preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	if (self.view.window && !self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}
- (void)reloadHistory {
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) self = weakSelf;
			if (!self) return;
			if (!snapshot) { [self showError]; return; }
			self.items = [[[snapshot[@"history"] reverseObjectEnumerator] allObjects] copy];
			[self.table reloadData];
		});
	});
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return section == 0 ? 1 : (NSInteger)self.items.count; }
- (void)toggleHistory:(UISwitch *)sender {
	if (![SXPrefs writeValues:@{@"incognito": @(sender.on)} removing:@[]]) {
		[sender setOn:[SXPrefs shared].incognito animated:YES]; [self showError]; return;
	}
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return @"Không ghi lượt mới, không chạy công cụ hay báo đáp án đến muộn. Giọng đọc dùng hệ thống; câu hỏi vẫn gửi đến nhà cung cấp AI.";
	return self.items.count ? @"Chọn một mục để xem, sao chép hoặc xóa. Lịch sử được lưu trên thiết bị." : @"Chưa có câu trả lời AI được lưu.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = @"Không lưu lịch sử";
		cell.textLabel.adjustsFontForContentSizeCategory = YES;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *control = [UISwitch new]; control.on = [SXPrefs shared].incognito;
		control.accessibilityLabel = cell.textLabel.text;
		[control addTarget:self action:@selector(toggleHistory:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = control;
		return cell;
	}
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"turn"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"turn"];
	NSDictionary *item = self.items[indexPath.row];
	cell.textLabel.text = item[@"q"];
	NSDate *date = item[@"date"];
	NSString *when = [date isKindOfClass:NSDate.class] ? [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"";
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", when, item[@"a"] ?: @""];
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0 || (NSUInteger)indexPath.row >= self.items.count) return;
	SXHistoryDetailController *detail = [SXHistoryDetailController new];
	detail.item = self.items[indexPath.row];
	__weak typeof(self) weakSelf = self;
	detail.onDelete = ^(NSDictionary *item) { [weakSelf deleteItem:item]; };
	[self.navigationController pushViewController:detail animated:YES];
}

- (void)deleteItem:(NSDictionary *)item {
	NSString *identifier = item[@"id"];
	if (![identifier isKindOfClass:NSString.class]) { [self showError]; return; }
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		BOOL ok = [[SXStore shared] deleteHistoryID:identifier];
		if (ok) notify_post("com.sirix.tweak/resetHistory");
		dispatch_async(dispatch_get_main_queue(), ^{ if (ok) [weakSelf reloadHistory]; else [weakSelf showError]; });
	});
}
- (void)confirmClear {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa toàn bộ lịch sử?" message:@"Không thể hoàn tác; các câu đang chờ sẽ không được thêm lại." preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		(void)action;
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] clearHistory];
			if (ok) notify_post("com.sirix.tweak/resetHistory");
			dispatch_async(dispatch_get_main_queue(), ^{ if (ok) [weakSelf reloadHistory]; else [weakSelf showError]; });
		});
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end
