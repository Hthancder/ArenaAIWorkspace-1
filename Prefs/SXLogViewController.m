#import "SXLogViewController.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>

@interface SXLogViewController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSDate *lastMTime;
@end

@implementation SXLogViewController

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Log SiriX";
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:@"Sao chép"
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(copyLog:)],
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(showMore:)],
	];

	self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
	self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.textView.editable = NO;
	self.textView.selectable = YES;
	self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
	self.textView.textColor = UIColor.labelColor;
	self.textView.backgroundColor = UIColor.clearColor;
	self.textView.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
	[self.view addSubview:self.textView];

	self.emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
	self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.emptyLabel.text = @"Chưa có log nào.\n\nHãy hỏi Siri một câu rồi quay lại đây.";
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];

	[self reloadLogAnimated:NO];
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

#pragma mark - Đọc log

- (NSString *)logContent {
	NSData *data = [NSData dataWithContentsOfFile:SXLogFilePath()];
	if (!data) return @"";
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	return text ?: @"";
}

- (void)reloadLogAnimated:(BOOL)animated {
	NSString *content = [self logContent];
	BOOL isEmpty = content.length == 0;
	self.emptyLabel.hidden = !isEmpty;
	self.textView.hidden = isEmpty;
	if (isEmpty) {
		self.textView.text = @"";
		return;
	}
	if ([content isEqualToString:self.textView.text]) return;

	CGFloat offset = self.textView.contentOffset.y;
	self.textView.text = content;
	[self.textView layoutIfNeeded];
	if (self.lastMTime == nil || !animated) {
		[self scrollToEnd];
	} else {
		self.textView.contentOffset = CGPointMake(0, offset);
	}
	self.lastMTime = [NSDate date];
}

- (void)scrollToEnd {
	if (self.textView.text.length == 0) return;
	[self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length - 1, 1)];
}

#pragma mark - Hành động

- (void)copyLog:(id)sender {
	NSString *content = [self logContent];
	if (!content.length) {
		[self flashButtonTitle:@"Trống"];
		return;
	}
	UIPasteboard.generalPasteboard.string = content;
	UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] init];
	[feedback impactOccurred];
	[self flashButtonTitle:@"Đã sao chép ✓"];
	SXLogInf(@"pref", @"người dùng sao chép log (%lu ký tự)", (unsigned long)content.length);
}

- (void)flashButtonTitle:(NSString *)title {
	self.navigationItem.rightBarButtonItems.firstObject.title = title;
	__weak SXLogViewController *weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[weakSelf flashButtonTitleDone:@"Sao chép"];
	});
}

- (void)flashButtonTitleDone:(NSString *)original {
	self.navigationItem.rightBarButtonItems.firstObject.title = original;
}

- (void)showMore:(id)sender {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Log SiriX"
																   message:@"/var/mobile/Library/Logs/SiriX.log"
															preferredStyle:UIAlertControllerStyleActionSheet];
	__weak SXLogViewController *weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:@"Chia sẻ tệp log"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		[weakSelf shareLog];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Xóa log"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		[weakSelf confirmClearLog];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Làm mới"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		[weakSelf reloadLogAnimated:NO];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Hủy"
											  style:UIAlertActionStyleCancel
											handler:nil]];

	UIPopoverPresentationController *popover = sheet.popoverPresentationController;
	if (popover) {
		popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareLog {
	NSString *content = [self logContent];
	if (!content.length) return;
	NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SiriX.log"];
	[content writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
	UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
																		   applicationActivities:nil];
	UIPopoverPresentationController *popover = activity.popoverPresentationController;
	if (popover) {
		popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	}
	[self presentViewController:activity animated:YES completion:nil];
}

- (void)confirmClearLog {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa toàn bộ log?"
																   message:@"Hành động này không hoàn tác được."
															preferredStyle:UIAlertControllerStyleAlert];
	__weak SXLogViewController *weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Xóa"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		[[NSFileManager defaultManager] removeItemAtPath:SXLogFilePath() error:NULL];
		[weakSelf reloadLogAnimated:NO];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
											  style:UIAlertActionStyleCancel
											handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
