#import "SXLogViewController.h"
#import "SXNavigationSupport.h"
#import "SXLog.h"
#import "SXLogFile.h"
#import "SXUISupport.h"
#import <UIKit/UIKit.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

typedef NS_ENUM(NSInteger, SXLogFilter) {
	SXLogFilterAll = 0,
	SXLogFilterProblems, // WARN + ERROR
	SXLogFilterErrors,   // ERROR
};

// ── Giới hạn hiển thị ────────────────────────────────────────────────────────
// Trước đây màn hình nạp TOÀN BỘ file (tới 512 KB) rồi dựng lại UITextView mỗi
// 2 giây trên luồng chính. Khi log lớn, mỗi nhịp layout tốn hàng trăm ms → giao
// diện đơ, không bấm được nút Back. Nay: chỉ đọc đuôi file, chỉ vẽ lại khi nội
// dung đổi, và nối thêm phần mới thay vì dựng lại cả khối văn bản.
static const NSUInteger kSXLogTailBytes = 160 * 1024;   // đọc tối đa 160 KB cuối file
static const NSUInteger kSXLogMaxLines = 1200;          // hiển thị tối đa 1200 dòng
static const NSUInteger kSXLogMaxChars = 180 * 1024;    // trần ký tự trong UITextView
static const NSTimeInterval kSXLogRefreshInterval = 2.5;
static const NSTimeInterval kSXLogSearchDebounce = 0.25;

#pragma mark - Lọc (thuần, chạy trên luồng nền)

static BOOL SXLogLineMatches(NSString *line, SXLogFilter filter, NSString *lowerQuery) {
	switch (filter) {
		case SXLogFilterAll:
			break;
		case SXLogFilterProblems:
			if ([line rangeOfString:@"[WARN ]"].location == NSNotFound &&
				[line rangeOfString:@"[ERROR]"].location == NSNotFound) return NO;
			break;
		case SXLogFilterErrors:
			if ([line rangeOfString:@"[ERROR]"].location == NSNotFound) return NO;
			break;
	}
	if (lowerQuery.length && [line.lowercaseString rangeOfString:lowerQuery].location == NSNotFound) return NO;
	return YES;
}

/// Lọc + giới hạn số dòng. Trả về mảng dòng (đã cắt phần đầu nếu quá dài) để
/// màn hình tự tô màu theo mức log và nối thêm dòng mới một cách chính xác —
/// so chuỗi con trên cả khối văn bản từng sai khi log bị xoay vòng.
static NSArray<NSString *> *SXLogFilteredLines(NSString *raw, SXLogFilter filter, NSString *query,
									  NSUInteger *outLines, BOOL *outCapped) {
	if (outLines) *outLines = 0;
	if (outCapped) *outCapped = NO;
	if (!raw.length) return @[];

	NSString *lowerQuery = query.lowercaseString;
	NSArray<NSString *> *all = [raw componentsSeparatedByString:@"\n"];
	NSMutableArray<NSString *> *kept = [NSMutableArray arrayWithCapacity:MIN(all.count, kSXLogMaxLines)];
	for (NSString *line in all) {
		if (!line.length) continue;
		if (!SXLogLineMatches(line, filter, lowerQuery)) continue;
		[kept addObject:line];
	}
	if (kept.count > kSXLogMaxLines) {
		[kept removeObjectsInRange:NSMakeRange(0, kept.count - kSXLogMaxLines)];
		if (outCapped) *outCapped = YES;
	}
	if (outLines) *outLines = kept.count;
	return kept;
}

/// Màu theo mức: ERROR đỏ, WARN cam, còn lại màu chữ thường. Giữ chữ đơn cách
/// nên vẫn đọc được cột thời gian, và không phá vùng chọn khi người dùng bôi đen.
static UIColor *SXLogColorForLine(NSString *line) {
	if ([line rangeOfString:@"[ERROR]"].location != NSNotFound) return UIColor.systemRedColor;
	if ([line rangeOfString:@"[WARN ]"].location != NSNotFound) return UIColor.systemOrangeColor;
	return UIColor.labelColor;
}

#pragma mark - Màn hình

@interface SXLogViewController () <UISearchBarDelegate, UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) dispatch_queue_t workQueue;

@property (nonatomic, copy) NSString *visibleText;   // nội dung dùng để sao chép
@property (nonatomic, copy) NSArray<NSString *> *appliedLines; // dòng đang hiển thị
@property (nonatomic, copy) NSString *pendingSearch;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) BOOL wasAtBottom;
@property (nonatomic) BOOL paused;                   // người dùng tạm dừng tự làm mới
@property (nonatomic) BOOL reading;                  // đang đọc file ở luồng nền
@property (nonatomic) BOOL reloadPending;             // có yêu cầu làm mới bị hoãn
@property (nonatomic) NSUInteger renderedRequest;    // chống kết quả cũ ghi đè
@property (nonatomic) unsigned long long fileSize;
@property (nonatomic) BOOL tailTruncated;
@property (nonatomic) BOOL linesCapped;
@property (nonatomic) NSUInteger renderedLines;
@property (nonatomic) BOOL readFailed;
@property (nonatomic) unsigned long long lastRenderedFileSize;
@end

@implementation SXLogViewController

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Log";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.workQueue = dispatch_queue_create("com.sirix.prefs.log", DISPATCH_QUEUE_SERIAL);
	self.wasAtBottom = YES;

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
	self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	self.textView.textColor = UIColor.labelColor;
	self.textView.backgroundColor = UIColor.clearColor;
	self.textView.textContainerInset = UIEdgeInsetsMake(10, 12, 20, 12);
	self.textView.alwaysBounceVertical = YES;
	self.textView.delegate = self;
	self.textView.hidden = YES; // hiện sau khi đọc xong, tránh nhấp nháy

	self.emptyLabel = [SXUI footnoteLabel:@"Đang đọc log…"];
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

	[self sx_requestReloadAnimated:NO force:YES];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Nhật ký");
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(sx_appDidBecomeActive:)
				   name:UIApplicationDidBecomeActiveNotification object:nil];
	[center addObserver:self selector:@selector(sx_appWillResignActive:)
				   name:UIApplicationWillResignActiveNotification object:nil];
	[self sx_startTimer];
	[self sx_requestReloadAnimated:NO force:YES];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, @"Nhật ký", @"không đọc được tệp log");
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self sx_stopTimer];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc {
	[self sx_stopTimer];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Hẹn giờ làm mới

- (void)sx_startTimer {
	[self sx_stopTimer];
	if (self.paused) return;
	__weak typeof(self) weakSelf = self;
	NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:kSXLogRefreshInterval
													 repeats:YES
													   block:^(NSTimer *tick) {
		(void)tick;
		[weakSelf sx_requestReloadAnimated:YES force:NO];
	}];
	// Dung sai giúp hệ thống gộp nhịp, giảm hao pin và giật khi đang cuộn.
	timer.tolerance = 0.6;
	self.refreshTimer = timer;
}

- (void)sx_stopTimer {
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;
}

- (void)sx_appDidBecomeActive:(NSNotification *)note {
	(void)note;
	[self sx_startTimer];
	[self sx_requestReloadAnimated:NO force:YES];
}

- (void)sx_appWillResignActive:(NSNotification *)note {
	(void)note;
	[self sx_stopTimer];
}

#pragma mark - Đọc & hiển thị

/// Đọc phần đuôi file log. Chạy trên luồng nền — không bao giờ chặn luồng chính.
- (NSString *)readTailWithSize:(unsigned long long *)outSize truncated:(BOOL *)outTruncated {
	if (outSize) *outSize = 0;
	if (outTruncated) *outTruncated = NO;

	char *buffer = malloc(kSXLogTailBytes + 1);
	if (!buffer) return nil;

	off_t size = 0;
	int truncated = 0;
	ssize_t got = SXLogFileReadTail(SXLogFilePath().fileSystemRepresentation,
									buffer, kSXLogTailBytes, &size, &truncated);

	NSString *text = nil;
	if (got >= 0) {
		text = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)got encoding:NSUTF8StringEncoding];
		if (!text) {
			text = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)got
										  encoding:NSISOLatin1StringEncoding];
		}
	}
	free(buffer);

	if (outSize) *outSize = size > 0 ? (unsigned long long)size : 0;
	if (outTruncated) *outTruncated = (truncated != 0);

	if (got < 0) {
		// Chưa từng có log (máy mới cài) không phải là lỗi — chỉ là rỗng.
		if (![[NSFileManager defaultManager] fileExistsAtPath:SXLogFilePath()]) return @"";
		return nil;
	}
	return text ?: @"";
}

- (void)sx_requestReloadAnimated:(BOOL)animated force:(BOOL)force {
	if (!self.viewLoaded) return;
	if (self.reading) {
		// Đang đọc dở: ghi nhớ để chạy lại ngay khi xong (không bỏ yêu cầu của người dùng).
		if (force) self.reloadPending = YES;
		return;
	}
	// Đang bôi đen để sao chép: hoãn cập nhật để không cướp vùng chọn.
	if (animated && !force && self.textView.selectedRange.length > 0) return;

	self.reading = YES;
	NSUInteger request = ++self.renderedRequest;
	SXLogFilter filter = (SXLogFilter)self.filterControl.selectedSegmentIndex;
	NSString *query = [self.query copy];

	__weak typeof(self) weakSelf = self;
	dispatch_async(self.workQueue, ^{
		typeof(self) worker = weakSelf;
		if (!worker) return;

		unsigned long long size = 0;
		BOOL truncated = NO;
		NSString *raw = [worker readTailWithSize:&size truncated:&truncated];

		NSUInteger lines = 0;
		BOOL capped = NO;
		NSArray<NSString *> *kept = raw ? SXLogFilteredLines(raw, filter, query, &lines, &capped) : nil;

		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.reading = NO;
			// Có yêu cầu mới hơn trong lúc đọc → bỏ kết quả này.
			if (request != strongSelf.renderedRequest) return;
			[strongSelf sx_applyLines:kept
							   failed:(raw == nil)
								 size:size
							truncated:truncated
								lines:lines
							   capped:capped
							 animated:animated];
			if (strongSelf.reloadPending) {
				strongSelf.reloadPending = NO;
				[strongSelf sx_requestReloadAnimated:NO force:YES];
			}
		});
	});
}

- (NSAttributedString *)sx_attributedStringForLines:(NSArray<NSString *> *)lines {
	UIFont *font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
	for (NSString *line in lines) {
		NSString *text = [line stringByAppendingString:@"\n"];
		NSDictionary *attrs = @{NSFontAttributeName: font,
								NSForegroundColorAttributeName: SXLogColorForLine(line)};
		[result appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attrs]];
	}
	return result;
}

- (void)sx_applyLines:(NSArray<NSString *> *)lines
			   failed:(BOOL)failed
				 size:(unsigned long long)size
			truncated:(BOOL)truncated
				lines:(NSUInteger)lineCount
			   capped:(BOOL)capped
			 animated:(BOOL)animated {
	self.readFailed = failed;
	self.fileSize = size;
	self.tailTruncated = truncated;
	self.linesCapped = capped;
	self.renderedLines = lineCount;

	BOOL empty = (lines.count == 0);
	self.visibleText = empty ? @"" : [lines componentsJoinedByString:@"\n"];
	self.emptyLabel.hidden = !empty;
	self.textView.hidden = empty;

	if (empty) {
		self.appliedLines = @[];
		if (self.textView.text.length) self.textView.text = @"";
		if (failed) {
			self.emptyLabel.text = [NSString stringWithFormat:@"Không đọc được tệp log.\n\n%@", SXLogFilePath()];
		} else if (size > 0) {
			self.emptyLabel.text = @"Không có dòng nào khớp bộ lọc hoặc từ khoá.";
		} else {
			self.emptyLabel.text = @"Chưa có log nào.\n\nHãy hỏi Siri một câu rồi quay lại đây.";
		}
		[self sx_updatePrompt];
		return;
	}

	if ([lines isEqualToArray:self.appliedLines]) {
		[self sx_updatePrompt];
		return;
	}

	BOOL stayAtBottom = self.wasAtBottom || self.appliedLines.count == 0;
	CGFloat offset = self.textView.contentOffset.y;

	// Nối thêm chỉ khi phần đang hiển thị vẫn là đoạn đầu của danh sách mới và
	// phần thêm vào nhỏ — nhờ vậy không phải dựng lại cả khối văn bản mỗi nhịp.
	BOOL fileGrew = size >= self.lastRenderedFileSize;
	BOOL canAppend = animated
		&& fileGrew
		&& self.appliedLines.count > 0
		&& lines.count >= self.appliedLines.count
		&& (lines.count - self.appliedLines.count) <= 400
		&& [[lines subarrayWithRange:NSMakeRange(lines.count - self.appliedLines.count, self.appliedLines.count)]
			isEqualToArray:self.appliedLines];

	if (canAppend) {
		NSArray<NSString *> *deltaLines = [lines subarrayWithRange:
			NSMakeRange(self.appliedLines.count, lines.count - self.appliedLines.count)];
		NSTextStorage *storage = self.textView.textStorage;
		[storage beginEditing];
		[storage appendAttributedString:[self sx_attributedStringForLines:deltaLines]];
		[self sx_trimTextView];
		[storage endEditing];
		self.appliedLines = lines;
	} else {
		self.textView.attributedText = [self sx_attributedStringForLines:lines];
		self.appliedLines = lines;
	}

	self.lastRenderedFileSize = size;
	[self sx_updatePrompt];

	if (stayAtBottom) {
		[self sx_scrollToBottom];
	} else {
		CGFloat maxOffset = MAX(0.0, self.textView.contentSize.height - self.textView.bounds.size.height);
		self.textView.contentOffset = CGPointMake(0, MIN(offset, maxOffset));
	}
}

/// Giữ UITextView trong hạn mức ký tự: cắt từ đầu tới ranh giới dòng.
- (void)sx_trimTextView {
	NSTextStorage *storage = self.textView.textStorage;
	if (storage.length <= kSXLogMaxChars) return;
	NSUInteger excess = storage.length - kSXLogMaxChars;
	NSString *plain = storage.string;
	if (excess >= plain.length) return;
	NSRange window = NSMakeRange(excess, MIN(plain.length - excess, (NSUInteger)8192));
	NSRange newline = [plain rangeOfString:@"\n" options:0 range:window];
	NSUInteger cut = newline.location != NSNotFound ? NSMaxRange(newline) : excess;
	if (cut > 0) [storage deleteCharactersInRange:NSMakeRange(0, cut)];
}

- (void)sx_scrollToBottom {
	[self.textView layoutIfNeeded];
	CGFloat inset = self.textView.adjustedContentInset.bottom;
	CGFloat maxOffset = MAX(0.0, self.textView.contentSize.height + inset - self.textView.bounds.size.height);
	if (fabs(self.textView.contentOffset.y - maxOffset) < 1.0) return;
	[self.textView setContentOffset:CGPointMake(0, maxOffset) animated:NO];
}

- (void)sx_updatePrompt {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	if (self.readFailed) {
		[parts addObject:@"không đọc được tệp"];
	} else {
		[parts addObject:[NSString stringWithFormat:@"%@ dòng",
						  [SXUI groupedNumber:(NSInteger)self.renderedLines]]];
		[parts addObject:[NSString stringWithFormat:@"%@ KB",
						  [SXUI groupedNumber:(NSInteger)(self.fileSize / 1024)]]];
		if (self.linesCapped || self.tailTruncated) [parts addObject:@"đã cắt phần đầu"];
	}
	if (self.paused) [parts addObject:@"tạm dừng"];
	self.navigationItem.prompt = [parts componentsJoinedByString:@" · "];
}

#pragma mark - Cuộn

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	CGFloat maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom -
		scrollView.bounds.size.height;
	if (maxOffset <= 0) {
		self.wasAtBottom = YES;   // nội dung ngắn hơn khung: luôn coi là ở cuối
		return;
	}
	self.wasAtBottom = scrollView.contentOffset.y >= maxOffset - 80.0;
}

#pragma mark - Bộ lọc & tìm kiếm

- (void)sx_filterChanged:(UISegmentedControl *)sender {
	(void)sender;
	self.appliedLines = @[]; // đổi bộ lọc → vẽ lại toàn bộ
	[self sx_requestReloadAnimated:NO force:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	(void)searchBar;
	// Gõ nhanh không đọc lại file 6 lần: gộp thành một lượt sau khi ngừng gõ.
	self.pendingSearch = searchText;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sx_applySearch) object:nil];
	[self performSelector:@selector(sx_applySearch) withObject:nil afterDelay:kSXLogSearchDebounce];
}

- (void)sx_applySearch {
	NSString *text = self.pendingSearch;
	if (![text isKindOfClass:[NSString class]]) return;
	if ((self.query == nil && text.length == 0) || [self.query isEqualToString:text]) return;
	self.query = text;
	self.appliedLines = @[];
	[self sx_requestReloadAnimated:NO force:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sx_applySearch) object:nil];
	self.pendingSearch = @"";
	searchBar.text = @"";
	self.query = nil;
	self.appliedLines = @[];
	[searchBar resignFirstResponder];
	[self sx_requestReloadAnimated:NO force:YES];
}

#pragma mark - Hành động

- (void)copyLog:(id)sender {
	(void)sender;
	NSString *content = self.visibleText;
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
		[weakSelf sx_updatePrompt];
	});
}

- (void)showMore:(id)sender {
	(void)sender;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Log SiriX"
																  message:SXLogFilePath()
														   preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:@"Chia sẻ tệp log"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[weakSelf shareLog];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:(self.paused ? @"Tiếp tục tự làm mới" : @"Tạm dừng tự làm mới")
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		(void)action;
		[weakSelf togglePause];
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
		[weakSelf sx_requestReloadAnimated:NO force:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

	UIPopoverPresentationController *popover = sheet.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)togglePause {
	self.paused = !self.paused;
	if (self.paused) {
		[self sx_stopTimer];
	} else {
		[self sx_startTimer];
		[self sx_requestReloadAnimated:NO force:YES];
	}
	[self sx_updatePrompt];
}

- (void)shareLog {
	NSData *data = [NSData dataWithContentsOfFile:SXLogFilePath() options:0 error:NULL];
	if (!data.length) return;
	NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SiriX.log"];
	if (![data writeToFile:tempPath atomically:YES]) return;
	UIActivityViewController *activity = [[UIActivityViewController alloc]
		initWithActivityItems:@[[NSURL fileURLWithPath:tempPath]] applicationActivities:nil];
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
		weakSelf.appliedLines = @[];
		[weakSelf sx_requestReloadAnimated:NO force:YES];
	}];
}

@end
