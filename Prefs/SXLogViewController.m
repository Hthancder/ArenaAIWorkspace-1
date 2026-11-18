#import "SXLogViewController.h"
#import "SXLog.h"
#import "SXLogFile.h"
#import "SXUISupport.h"
#import <UIKit/UIKit.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

typedef NS_ENUM(NSInteger, SXLogFilter) {
	SXLogFilterAll = 0,
	SXLogFilterProblems, // WARN + ERROR
	SXLogFilterErrors,   // ERROR
};

@interface SXLogViewController () <UISearchBarDelegate, UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, copy) NSString *rawLog;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *visibleText;
@property (nonatomic) BOOL wasAtBottom;
@end

@implementation SXLogViewController

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Log";
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(copyLog:)],
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(showMore:)],
	];

	self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"Tất cả", @"Vấn đề", @"Lỗi"]];
	self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
	self.filterControl.selectedSegmentIndex = SXLogFilterAll;
	[self.filterControl addTarget:self action:@selector(sx_filterChanged:)
				 forControlEvents:UIControlEventValueChanged];

	self.searchBar = [[UISearchBar alloc] init];
	self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
	self.searchBar.placeholder = @"Tìm trong log";
	self.searchBar.delegate = self;
	self.searchBar.searchBarStyle = UISearchBarStyleMinimal;

	self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
	self.textView.translatesAutoresizingMaskIntoConstraints = NO;
	self.textView.editable = NO;
	self.textView.selectable = YES;
	self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
	self.textView.textColor = UIColor.labelColor;
	self.textView.backgroundColor = UIColor.clearColor;
	self.textView.textContainerInset = UIEdgeInsetsMake(10, 12, 20, 12);
	self.textView.alwaysBounceVertical = YES;
	self.textView.delegate = self;

	self.emptyLabel = [SXUI footnoteLabel:@"Chưa có log nào.\n\nHãy hỏi Siri một câu rồi quay lại đây."];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;

	[self.view addSubview:self.filterControl];
	[self.view addSubview:self.searchBar];
	[self.view addSubview:self.textView];
	[self.view addSubview:self.emptyLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.filterControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
		[self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],

		[self.searchBar.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:2],
		[self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
		[self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],

		[self.textView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:2],
		[self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
		[self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
	]];

	self.wasAtBottom = YES;
	[self reloadLogAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadLogAnimated:NO];
	[self.refreshTimer invalidate];
	self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
														target:self
													  selector:@selector(timerTick)
													  userInfo:nil
													   repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;
}

- (void)timerTick {
	[self reloadLogAnimated:YES];
}

#pragma mark - Đọc & lọc

- (NSString *)readLogFile {
	NSData *data = [NSData dataWithContentsOfFile:SXLogFilePath()];
	if (!data.length) return @"";
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	return text ?: @"";
}

- (BOOL)line:(NSString *)line matchesFilter:(SXLogFilter)filter {
	switch (filter) {
		case SXLogFilterAll: return YES;
		case SXLogFilterProblems:
			return [line containsString:@"[WARN ]"] || [line containsString:@"[ERROR]"];
		case SXLogFilterErrors: return [line containsString:@"[ERROR]"];
	}
	return YES;
}

- (NSString *)filteredLogFrom:(NSString *)raw count:(NSUInteger *)outCount {
	SXLogFilter filter = (SXLogFilter)self.filterControl.selectedSegmentIndex;
	NSString *query = self.query.lowercaseString;
	NSArray<NSString *> *lines = [raw componentsSeparatedByString:@"\n"];
	NSMutableString *output = [NSMutableString string];
	NSUInteger kept = 0;

	for (NSString *line in lines) {
		if (!line.length) continue;
		if (![self line:line matchesFilter:filter]) continue;
		if (query.length && [line.lowercaseString rangeOfString:query].location == NSNotFound) continue;
		[output appendString:line];
		[output appendString:@"\n"];
		kept++;
	}
	if (outCount) *outCount = kept;
	return output;
}

- (void)reloadLogAnimated:(BOOL)animated {
	NSString *raw = [self readLogFile];
	BOOL rawChanged = ![raw isEqualToString:self.rawLog ?: @""];
	if (animated && !rawChanged) return;

	self.rawLog = raw;
	NSUInteger count = 0;
	NSString *filtered = [self filteredLogFrom:raw count:&count];
	self.visibleText = filtered;

	BOOL empty = filtered.length == 0;
	self.emptyLabel.hidden = !empty;
	self.textView.hidden = empty;
	if (empty) {
		self.textView.text = @"";
		self.emptyLabel.text = raw.length
			? @"Không có dòng nào khớp bộ lọc hoặc từ khoá."
			: @"Chưa có log nào.\n\nHãy hỏi Siri một câu rồi quay lại đây.";
		self.navigationItem.prompt = raw.length ? @"0 dòng khớp" : nil;
		return;
	}

	self.emptyLabel.hidden = YES;
	unsigned long long bytes = (unsigned long long)raw.length;
	self.navigationItem.prompt = [NSString stringWithFormat:@"%@ dòng · %@ ký tự",
								  [SXUI groupedNumber:(NSInteger)count],
								  [SXUI groupedNumber:(NSInteger)bytes]];

	CGFloat offset = self.textView.contentOffset.y;
	BOOL stayAtBottom = self.wasAtBottom;
	self.textView.text = filtered;
	[self.textView layoutIfNeeded];

	if (!animated || stayAtBottom) {
		[self scrollToEnd];
	} else {
		CGFloat maxOffset = MAX(0.0, self.textView.contentSize.height - self.textView.bounds.size.height);
		self.textView.contentOffset = CGPointMake(0, MIN(offset, maxOffset));
	}
}

- (void)scrollToEnd {
	if (self.textView.text.length == 0) return;
	[self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length - 1, 1)];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	CGFloat maxOffset = scrollView.contentSize.height - scrollView.bounds.size.height;
	self.wasAtBottom = scrollView.contentOffset.y >= maxOffset - 80.0;
}

#pragma mark - Bộ lọc

- (void)sx_filterChanged:(UISegmentedControl *)sender {
	(void)sender;
	[self reloadLogAnimated:NO];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	(void)searchBar;
	self.query = searchText;
	[self reloadLogAnimated:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.query = nil;
	[searchBar resignFirstResponder];
	[self reloadLogAnimated:NO];
}

#pragma mark - Hành động

- (void)copyLog:(id)sender {
	(void)sender;
	NSString *content = self.visibleText.length ? self.visibleText : [self readLogFile];
	if (!content.length) {
		[SXUI alertOn:self title:@"Log trống" message:nil];
		return;
	}
	UIPasteboard.generalPasteboard.string = content;
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"người dùng sao chép log (%lu ký tự)", (unsigned long)content.length);
	self.navigationItem.prompt = @"Đã sao chép ✓";
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[weakSelf reloadLogAnimated:NO];
	});
}

- (void)showMore:(id)sender {
	(void)sender;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Log SiriX"
																   message:@"/var/mobile/Library/Logs/SiriX.log"
															preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:@"Chia sẻ tệp log"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[weakSelf shareLog];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Xoá log"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;
		[weakSelf confirmClearLog];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Làm mới"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[weakSelf reloadLogAnimated:NO];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

	UIPopoverPresentationController *popover = sheet.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareLog {
	NSString *content = [self readLogFile];
	if (!content.length) return;
	NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SiriX.log"];
	[content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:tempPath]]
																		 applicationActivities:nil];
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	[self presentViewController:activity animated:YES completion:nil];
}

- (void)confirmClearLog {
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá toàn bộ log?"
			message:@"Hành động này không hoàn tác được. Log cũ (.old) cũng bị xoá."
		confirmText:@"Xoá log"
			 action:^{
		// Truncate tại chỗ, không unlink: process đang ghi không mất đường dẫn.
		if (SXLogFileClear(SXLogFilePath().fileSystemRepresentation) < 0) {
			NSString *reason = [NSString stringWithUTF8String:strerror(errno)] ?: @"lỗi không rõ";
			[SXUI alertOn:weakSelf title:@"Không thể xoá log" message:reason];
			return;
		}
		NSString *oldPath = [SXLogFilePath() stringByAppendingString:@".old"];
		if ([[NSFileManager defaultManager] fileExistsAtPath:oldPath]) {
			[[NSFileManager defaultManager] removeItemAtPath:oldPath error:NULL];
		}
		[weakSelf reloadLogAnimated:NO];
	}];
}

@end
