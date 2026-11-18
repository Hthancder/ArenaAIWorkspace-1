#import "SXPromptController.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import <notify.h>
#import <UIKit/UIKit.h>

@interface SXPromptController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@end

@implementation SXPromptController

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Prompt tùy chỉnh";
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:@"Lưu"
										 style:UIBarButtonItemStyleDone
										target:self
										action:@selector(save:)],
		[[UIBarButtonItem alloc] initWithTitle:@"Mặc định"
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(resetToDefault:)],
	];

	self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
	self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.textView.font = [UIFont systemFontOfSize:15];
	self.textView.textColor = UIColor.labelColor;
	self.textView.backgroundColor = UIColor.clearColor;
	self.textView.delegate = self;
	self.textView.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
	[self.view addSubview:self.textView];

	self.placeholderLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 14, self.view.bounds.size.width - 28, 40)];
	self.placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.placeholderLabel.numberOfLines = 2;
	self.placeholderLabel.font = [UIFont systemFontOfSize:15];
	self.placeholderLabel.textColor = UIColor.placeholderTextColor;
	self.placeholderLabel.text = @"Để trống để dùng prompt mặc định của SiriX.\nPrompt hiện tại sẽ áp dụng cho mọi câu hỏi.";
	[self.view addSubview:self.placeholderLabel];

	NSString *current = [SXPrefs shared].customPrompt;
	self.textView.text = current;
	[self updatePlaceholder];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(keyboardWillChange:)
												 name:UIKeyboardWillChangeFrameNotification
											   object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.textView becomeFirstResponder];
}

#pragma mark - Placeholder

- (void)updatePlaceholder {
	self.placeholderLabel.hidden = self.textView.text.length > 0;
}

- (void)textViewDidChange:(UITextView *)textView {
	[self updatePlaceholder];
}

#pragma mark - Bàn phím

- (void)keyboardWillChange:(NSNotification *)notification {
	CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGFloat overlap = MAX(0, self.view.bounds.size.height - endFrame.origin.y);
	self.textView.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
	self.textView.scrollIndicatorInsets = self.textView.contentInset;
}

#pragma mark - Lưu / đặt lại

- (void)save:(id)sender {
	NSString *text = [self.textView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (text.length) {
		CFPreferencesSetAppValue((__bridge CFStringRef)@"customPrompt",
								 (__bridge CFStringRef)text,
								 CFSTR("com.sirix.tweak"));
	} else {
		CFPreferencesSetAppValue((__bridge CFStringRef)@"customPrompt", NULL, CFSTR("com.sirix.tweak"));
	}
	CFPreferencesAppSynchronize(CFSTR("com.sirix.tweak"));
	notify_post("com.sirix.tweak/prefs.changed");
	SXLogInf(@"pref", @"đã lưu prompt tùy chỉnh (%lu ký tự)", (unsigned long)text.length);
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)resetToDefault:(id)sender {
	self.textView.text = @"";
	[self updatePlaceholder];
	[self.textView becomeFirstResponder];
}

@end
