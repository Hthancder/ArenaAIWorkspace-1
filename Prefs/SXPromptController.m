#import "SXPromptController.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#pragma mark - Mẫu prompt

static NSString *SXTemplateShort(void) {
	return @"Bạn là SiriX, trợ lý AI tích hợp trong Siri. Trả lời ngắn nhất có thể (thường 1–2 câu), "
		   @"đúng trọng tâm, cùng ngôn ngữ với câu hỏi. Không emoji. Chỉ dùng **đậm** hoặc gạch đầu dòng "
		   @"khi thật sự cần. Nếu người dùng yêu cầu thao tác trên máy (báo thức, gọi điện, mở app…), "
		   @"hệ thống tự thực hiện — chỉ xác nhận ngắn gọn.";
}

static NSString *SXTemplateDetailed(void) {
	return @"Bạn là SiriX, trợ lý AI trong Siri trên iPhone, hôm nay {date}, thiết bị {device}. "
		   @"Trả lời bằng ngôn ngữ của người dùng. Với câu hỏi cần giải thích: mở đầu bằng câu trả lời "
		   @"trực tiếp, sau đó 2–4 gạch đầu dòng ngắn nêu lý do hoặc ví dụ, kết thúc bằng một câu chốt. "
		   @"Không lan man, không emoji, không nhắc lại câu hỏi. Tác vụ hệ thống do iOS xử lý — chỉ xác nhận.";
}

static NSString *SXTemplateCoding(void) {
	return @"Bạn là SiriX — trợ lý lập trình tích hợp trong Siri. Trả lời cùng ngôn ngữ với câu hỏi. "
		   @"Khi đưa code: dùng khối ```ngôn_ngữ``` gọn, chỉ phần cần thiết, kèm 1–3 câu giải thích ngay "
		   @"dưới. Khi câu trả lời dài, chia mục ngắn. Không emoji, không xin lỗi thừa.";
}

static NSArray<NSString *> *SXTemplateTitles(void) {
	return @[@"Ngắn gọn (mặc định)", @"Giải thích kỹ", @"Lập trình"];
}

static NSString *SXTemplateAtIndex(NSInteger index) {
	switch (index) {
		case 1: return SXTemplateDetailed();
		case 2: return SXTemplateCoding();
		default: return SXTemplateShort();
	}
}

@interface SXPromptController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, copy) NSString *rawEffective;  // prompt đang dùng (raw, chưa thay biến)
@property (nonatomic, copy) NSString *savedSnapshot; // nội dung đã lưu — mốc tính “chưa lưu”
@end

@implementation SXPromptController {
	NSInteger _lastSegmentIndex; // để phục hồi segmented khi hủy chuyển tab
}

#pragma mark - Khung hình

- (void)loadView {
	[super loadView];
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	self.rawEffective = prefs.customPrompt.length
		? [prefs.customPrompt copy]
		: SXDefaultSystemPrompt();
	_lastSegmentIndex = 0;

	// Ô tiêu đề: [Đang dùng | Mặc định]
	self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"Đang dùng", @"Mặc định"]];
	self.segmentControl.selectedSegmentIndex = 0;
	[self.segmentControl addTarget:self
							action:@selector(sx_segmentChanged:)
				  forControlEvents:UIControlEventValueChanged];
	self.navigationItem.titleView = self.segmentControl;

	// Quay lại: chevron trái, có cảnh báo khi nội dung chưa lưu (DESIGN-UI §4.2)
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"chevron.left"]
				 style:UIBarButtonItemStylePlain
				target:self
				action:@selector(sx_backTapped)];

	// Lưu: chỉ bật khi có chỉnh sửa
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithTitle:@"Lưu"
				style:UIBarButtonItemStyleDone
			   target:self
			   action:@selector(sx_save)];
	self.navigationItem.rightBarButtonItem.enabled = NO;

	// Ô soạn thảo
	UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
	textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	textView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
	textView.delegate = self;
	textView.text = self.rawEffective;
	textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
	textView.layer.cornerRadius = 12.0;
	textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
	[self.view addSubview:textView];
	self.textView = textView;
	self.savedSnapshot = [self.rawEffective copy];

	// Thanh công cụ trên bàn phím: chips + Khôi phục + Sao chép
	UIToolbar *toolbar = [[UIToolbar alloc]
		initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
	toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
	[items addObject:[[UIBarButtonItem alloc] initWithTitle:@"Mẫu"
													  style:UIBarButtonItemStylePlain
													 target:self
													 action:@selector(sx_showTemplates:)]];
	[items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																   target:nil
																   action:nil]];
	NSArray<NSString *> *tokens = @[@"{date}", @"{device}", @"{lang}"];
	[tokens enumerateObjectsUsingBlock:^(NSString *token, NSUInteger idx, BOOL *stop) {
		UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:token
																 style:UIBarButtonItemStylePlain
																target:self
																action:@selector(sx_insertChip:)];
		item.tag = (NSInteger)idx;
		[items addObject:item];
	}];
	[items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																  target:nil action:nil]];
	[items addObject:[[UIBarButtonItem alloc] initWithTitle:@"Khôi phục"
													 style:UIBarButtonItemStylePlain
													target:self
													action:@selector(sx_resetToDefault)]];
	[items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																  target:nil action:nil]];
	[items addObject:[[UIBarButtonItem alloc] initWithTitle:@"Sao chép"
													 style:UIBarButtonItemStylePlain
													target:self
													action:@selector(sx_copy)]];
	toolbar.items = items;
	textView.inputAccessoryView = toolbar;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self updateStatus];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(sx_keyboardWillChange:)
												 name:UIKeyboardWillChangeFrameNotification
											   object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.textView becomeFirstResponder];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Trạng thái

- (BOOL)isDirty {
	return ![self.textView.text isEqualToString:self.savedSnapshot];
}

- (void)updateStatus {
	// Trạng thái phản ánh bản ĐANG DÙNG (rawEffective), không phải nội dung đang xem —
	// đang ở tab “Mặc định” nhưng custom vẫn được lưu thì vẫn ghi “prompt tùy chỉnh”.
	NSString *buffer = self.textView.text ?: @"";
	BOOL dirty = [self isDirty];
	BOOL effectiveIsDefault = (self.rawEffective.length == 0 ||
							   [self.rawEffective isEqualToString:SXDefaultSystemPrompt()]);
	if (dirty) {
		self.navigationItem.prompt = [NSString stringWithFormat:
			@"Đã sửa · chưa lưu (%lu ký tự)", (unsigned long)buffer.length];
	} else if (effectiveIsDefault) {
		self.navigationItem.prompt = @"Đang dùng: prompt mặc định của SiriX";
	} else {
		self.navigationItem.prompt = [NSString stringWithFormat:
			@"Đang dùng: prompt tùy chỉnh (%lu ký tự)", (unsigned long)self.rawEffective.length];
	}
	self.navigationItem.rightBarButtonItem.enabled = dirty;
}

- (void)loadContent:(NSString *)content {
	self.textView.text = content ?: @"";
	self.savedSnapshot = [self.textView.text copy];
	[self updateStatus];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
	[self updateStatus];
}

#pragma mark - Hành động

- (void)sx_insertChip:(UIBarButtonItem *)sender {
	static NSArray<NSString *> *tokens;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		tokens = @[@"{date}", @"{device}", @"{lang}"];
	});
	if (sender.tag < 0 || sender.tag >= (NSInteger)tokens.count) return;
	[self.textView insertText:tokens[sender.tag]];
	[self updateStatus];
}

- (void)sx_segmentChanged:(UISegmentedControl *)sender {
	NSInteger newIndex = sender.selectedSegmentIndex;
	NSString *target = (newIndex == 0) ? self.rawEffective : SXDefaultSystemPrompt();

	__weak typeof(self) weakSelf = self;
	void (^apply)(void) = ^{
		typeof(self) self_ = weakSelf;
		if (!self_) return;
		[self_ loadContent:target];
		self_->_lastSegmentIndex = newIndex;
	};

	if ([self isDirty]) {
		UIAlertController *alert = [UIAlertController
			alertControllerWithTitle:@"Đã có thay đổi chưa lưu"
							 message:@"Chuyển tab sẽ bỏ nội dung đang sửa."
					  preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"Bỏ thay đổi & chuyển"
												 style:UIAlertActionStyleDestructive
											   handler:^(UIAlertAction *action) { apply(); }]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Ở lại"
												 style:UIAlertActionStyleCancel
											   handler:^(UIAlertAction *action) {
			typeof(self) self_ = weakSelf;
			if (self_) self_.segmentControl.selectedSegmentIndex = self_->_lastSegmentIndex;
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	} else {
		apply();
	}
}

- (void)sx_save {
	NSString *trimmed = [(self.textView.text ?: @"") stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	BOOL asDefault = (trimmed.length == 0 ||
					  [trimmed isEqualToString:SXDefaultSystemPrompt()]);
	[SXPrefs setString:(asDefault ? nil : trimmed) forKey:@"customPrompt"];
	notify_post("com.sirix.tweak/prefs.changed");
	SXLogInf(@"pref", @"Lưu prompt — %@",
			 asDefault ? @"xóa bản riêng, dùng mặc định"
					   : [NSString stringWithFormat:@"%lu ký tự", (unsigned long)trimmed.length]);
	[[SXPrefs shared] reload];
	self.rawEffective = asDefault ? SXDefaultSystemPrompt() : trimmed;
	[self loadContent:self.rawEffective];
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)sx_resetToDefault {
	// Đang sửa dở mà bấm Khôi phục → xác nhận trước (nút nằm sát Sao chép trên bàn phím).
	if ([self isDirty]) {
		UIAlertController *alert = [UIAlertController
			alertControllerWithTitle:@"Khôi phục prompt mặc định?"
							 message:@"Nội dung đang sửa sẽ bị thay bằng prompt mặc định."
					  preferredStyle:UIAlertControllerStyleAlert];
		__weak typeof(self) weakSelf = self;
		[alert addAction:[UIAlertAction actionWithTitle:@"Khôi phục"
												 style:UIAlertActionStyleDestructive
											   handler:^(UIAlertAction *action) {
			[weakSelf doResetToDefault];
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
												 style:UIAlertActionStyleCancel
											   handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	[self doResetToDefault];
}

- (void)doResetToDefault {
	// Hành động xây dựng (đã xác nhận nếu cần) — không cần hỏi thêm.
	[SXPrefs setString:nil forKey:@"customPrompt"];
	notify_post("com.sirix.tweak/prefs.changed");
	SXLogInf(@"pref", @"Khôi phục prompt mặc định — xóa bản tùy chỉnh");
	[[SXPrefs shared] reload];
	self.rawEffective = SXDefaultSystemPrompt();
	self.segmentControl.selectedSegmentIndex = 0;
	_lastSegmentIndex = 0;
	[self loadContent:SXDefaultSystemPrompt()];
	[self.textView becomeFirstResponder];
}

- (void)sx_copy {
	[UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
	SXLogDbg(@"pref", @"sao chép prompt (%lu ký tự)",
			 (unsigned long)(self.textView.text.length));
	self.navigationItem.prompt = @"Đã sao chép ✓";
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[weakSelf updateStatus];
	});
}

- (void)sx_backTapped {
	if (![self isDirty]) {
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	UIAlertController *alert = [UIAlertController
		alertControllerWithTitle:@"Thoát mà chưa lưu?"
						 message:@"Nội dung đang sửa sẽ bị mất."
				  preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Thoát không lưu"
											 style:UIAlertActionStyleDestructive
										   handler:^(UIAlertAction *action) {
		[weakSelf.navigationController popViewControllerAnimated:YES];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Tiếp tục sửa"
											 style:UIAlertActionStyleCancel
										   handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Bàn phím

#pragma mark - Mẫu prompt

- (void)sx_showTemplates:(id)sender {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Chọn mẫu prompt"
																   message:@"Mẫu sẽ thay nội dung đang soạn (có hỏi lại nếu chưa lưu)."
															preferredStyle:UIAlertControllerStyleActionSheet];
	NSArray<NSString *> *titles = SXTemplateTitles();
	__weak typeof(self) weakSelf = self;
	[titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
		[sheet addAction:[UIAlertAction actionWithTitle:title
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *action) {
			(void)action;
			[weakSelf sx_applyTemplateAtIndex:(NSInteger)idx];
		}]];
	}];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

	UIPopoverPresentationController *popover = sheet.popoverPresentationController;
	if (popover) popover.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)sx_applyTemplateAtIndex:(NSInteger)index {
	NSString *text = SXTemplateAtIndex(index);
	if (!text.length) return;
	void (^apply)(void) = ^{
		self.textView.text = text;
		[self updateStatus];
		[self.textView becomeFirstResponder];
	};
	if (![self isDirty]) {
		apply();
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thay nội dung đang soạn?"
																   message:@"Nội dung đã sửa nhưng chưa lưu sẽ bị thay bằng mẫu."
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Thay bằng mẫu"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		(void)action;
		apply();
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)sx_keyboardWillChange:(NSNotification *)note {
	NSDictionary *userInfo = note.userInfo;
	CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationOptions curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

	CGRect converted = [self.view convertRect:endFrame fromView:nil];
	CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
	UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);

	[UIView animateWithDuration:duration delay:0 options:curve animations:^{
		self.textView.contentInset = insets;
		self.textView.scrollIndicatorInsets = insets;
	} completion:nil];
}

@end
