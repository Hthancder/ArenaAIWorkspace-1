#import "SXPromptController.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXUISupport.h"
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

static NSString *SXTemplateTutor(void) {
	return @"Bạn là SiriX, trợ lý học tập trong Siri. Trả lời cùng ngôn ngữ với câu hỏi, giọng kiên nhẫn, "
		   @"không phán xét. Giải thích bằng ví dụ đời thường trước, công thức sau; nêu 1 lỗi hiểu nhầm "
		   @"thường gặp nếu có. Không emoji, không lan man, không tự cho bài tập khi người dùng không hỏi.";
}

static NSArray<NSString *> *SXTemplateTitles(void) {
	return @[@"Ngắn gọn (mặc định)", @"Giải thích kỹ", @"Lập trình", @"Gia sư"];
}

static NSArray<NSString *> *SXTemplateSummaries(void) {
	return @[@"1–2 câu, đúng trọng tâm",
			 @"Trả lời trước, gạch đầu dòng lý do",
			 @"Code gọn kèm giải thích ngắn",
			 @"Ví dụ trước, công thức sau"];
}

static NSString *SXTemplateAtIndex(NSInteger index) {
	switch (index) {
		case 1: return SXTemplateDetailed();
		case 2: return SXTemplateCoding();
		case 3: return SXTemplateTutor();
		default: return SXTemplateShort();
	}
}

static NSString *SXPromptCountText(NSUInteger length) {
	return [NSString stringWithFormat:@"%@ ký tự · ~%@ token",
			[SXUI groupedNumber:(NSInteger)length],
			[SXUI groupedNumber:(NSInteger)MAX(1, (NSInteger)(length / 3))]];
}

#pragma mark - Màn hình

@interface SXPromptController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISegmentedControl *segmentControl;
@property (nonatomic, copy) NSString *rawEffective;   // prompt đang dùng (raw, chưa thay biến)
@property (nonatomic, copy) NSString *savedSnapshot;  // nội dung đã lưu — mốc tính “chưa lưu”
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIBarButtonItem *saveItem;
@property (nonatomic) NSInteger lastSegmentIndex;
@end

@implementation SXPromptController

#pragma mark - Khung hình

- (void)loadView {
	[super loadView];
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	self.rawEffective = prefs.customPrompt.length ? [prefs.customPrompt copy] : SXDefaultSystemPrompt();
	self.lastSegmentIndex = 0;

	self.segmentControl = [[UISegmentedControl alloc] initWithItems:@[@"Đang dùng", @"Mặc định"]];
	self.segmentControl.selectedSegmentIndex = 0;
	self.segmentControl.accessibilityLabel = @"Nguồn prompt";
	[self.segmentControl addTarget:self
							action:@selector(sx_segmentChanged:)
				  forControlEvents:UIControlEventValueChanged];
	self.navigationItem.titleView = self.segmentControl;

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"chevron.left"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_backTapped)];

	self.saveItem = [[UIBarButtonItem alloc] initWithTitle:@"Lưu"
													style:UIBarButtonItemStyleDone
												   target:self
												   action:@selector(sx_save)];
	self.saveItem.enabled = NO;
	self.navigationItem.rightBarButtonItem = self.saveItem;

	UILabel *hint = [SXUI footnoteLabel:
		@"Prompt là chỉ dẫn cố định gửi kèm mọi câu hỏi. Chèn {date}, {device}, {lang} để SiriX tự thay "
		 @"bằng ngày, tên máy và ngôn ngữ lúc chạy. Xoá trắng rồi Lưu = dùng lại prompt mặc định."];
	self.hintLabel = hint;

	UITextView *textView = [[UITextView alloc] init];
	textView.translatesAutoresizingMaskIntoConstraints = NO;
	textView.delegate = self;
	textView.text = self.rawEffective;
	textView.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
	textView.adjustsFontForContentSizeCategory = YES;
	textView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	textView.layer.cornerRadius = 12.0;
	textView.layer.cornerCurve = kCACornerCurveContinuous;
	textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
	textView.alwaysBounceVertical = YES;
	textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	textView.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	textView.autocorrectionType = UITextAutocorrectionTypeDefault;
	self.textView = textView;
	self.savedSnapshot = [self.rawEffective copy];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[hint, textView]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 10;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:stack];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
		[stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
		[stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
		[stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
	]];

	// Thanh công cụ trên bàn phím: Mẫu · biến · Khôi phục · Sao chép
	UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
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
		(void)stop;
		UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:token
																style:UIBarButtonItemStylePlain
															   target:self
															   action:@selector(sx_insertChip:)];
		item.tag = (NSInteger)idx;
		item.accessibilityLabel = [NSString stringWithFormat:@"Chèn %@", token];
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
	// Trạng thái phản ánh bản ĐANG DÙNG (rawEffective), không phải nội dung đang xem.
	NSString *buffer = self.textView.text ?: @"";
	BOOL dirty = [self isDirty];
	BOOL effectiveIsDefault = (self.rawEffective.length == 0 ||
							   [self.rawEffective isEqualToString:SXDefaultSystemPrompt()]);
	if (dirty) {
		self.navigationItem.prompt = [NSString stringWithFormat:@"Chưa lưu · %@", SXPromptCountText(buffer.length)];
	} else if (effectiveIsDefault) {
		self.navigationItem.prompt = @"Đang dùng prompt mặc định của SiriX";
	} else {
		self.navigationItem.prompt = [NSString stringWithFormat:@"Đang dùng prompt tuỳ chỉnh · %@",
									  SXPromptCountText(self.rawEffective.length)];
	}
	self.saveItem.enabled = dirty;
	self.saveItem.title = dirty ? @"Lưu" : @"Đã lưu";
}

- (void)loadContent:(NSString *)content {
	self.textView.text = content ?: @"";
	self.savedSnapshot = [self.textView.text copy];
	[self updateStatus];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
	(void)textView;
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
	[self.textView insertText:tokens[(NSUInteger)sender.tag]];
	[self updateStatus];
}

- (void)sx_segmentChanged:(UISegmentedControl *)sender {
	NSInteger newIndex = sender.selectedSegmentIndex;
	__weak typeof(self) weakSelf = self;
	if (![self isDirty]) {
		[self sx_applySegment:newIndex];
		return;
	}
	// Trả công tắc về tab cũ ngay; chỉ đổi khi người dùng xác nhận bỏ thay đổi.
	sender.selectedSegmentIndex = self.lastSegmentIndex;
	[SXUI confirmOn:self
			  title:@"Đã có thay đổi chưa lưu"
			message:@"Chuyển tab sẽ bỏ nội dung đang sửa."
		confirmText:@"Bỏ thay đổi"
			 action:^{
		[weakSelf sx_applySegment:newIndex];
	}];
}

- (void)sx_applySegment:(NSInteger)index {
	self.textView.text = (index == 0) ? self.rawEffective : SXDefaultSystemPrompt();
	self.savedSnapshot = [self.textView.text copy];
	self.lastSegmentIndex = index;
	self.segmentControl.selectedSegmentIndex = index;
	[self updateStatus];
	[self.textView becomeFirstResponder];
}

- (void)sx_save {
	NSString *trimmed = [(self.textView.text ?: @"") stringByTrimmingCharactersInSet:
						 NSCharacterSet.whitespaceAndNewlineCharacterSet];
	BOOL asDefault = (trimmed.length == 0 || [trimmed isEqualToString:SXDefaultSystemPrompt()]);
	[SXPrefs setString:(asDefault ? nil : trimmed) forKey:@"customPrompt"];
	notify_post("com.sirix.tweak/prefs.changed");
	SXLogInf(@"pref", @"Lưu prompt — %@", asDefault ? @"xóa bản riêng, dùng mặc định"
												   : [NSString stringWithFormat:@"%lu ký tự", (unsigned long)trimmed.length]);
	[[SXPrefs shared] reload];
	self.rawEffective = asDefault ? SXDefaultSystemPrompt() : trimmed;
	[self loadContent:self.rawEffective];
	[self.textView resignFirstResponder];
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)sx_resetToDefault {
	__weak typeof(self) weakSelf = self;
	if ([self isDirty]) {
		[SXUI confirmOn:self
				  title:@"Khôi phục prompt mặc định?"
				message:@"Nội dung đang sửa sẽ bị thay bằng prompt mặc định."
			confirmText:@"Khôi phục"
				 action:^{
			[weakSelf doResetToDefault];
		}];
		return;
	}
	[self doResetToDefault];
}

- (void)doResetToDefault {
	[SXPrefs setString:nil forKey:@"customPrompt"];
	notify_post("com.sirix.tweak/prefs.changed");
	SXLogInf(@"pref", @"Khôi phục prompt mặc định — xóa bản tuỳ chỉnh");
	[[SXPrefs shared] reload];
	self.rawEffective = SXDefaultSystemPrompt();
	self.lastSegmentIndex = 0;
	self.segmentControl.selectedSegmentIndex = 0;
	[self loadContent:SXDefaultSystemPrompt()];
	[self.textView becomeFirstResponder];
}

- (void)sx_copy {
	NSString *text = self.textView.text ?: @"";
	if (!text.length) {
		[SXUI alertOn:self title:@"Chưa có nội dung" message:@"Ô soạn thảo đang trống."];
		return;
	}
	UIPasteboard.generalPasteboard.string = text;
	[SXUI tapFeedback];
	SXLogDbg(@"pref", @"sao chép prompt (%lu ký tự)", (unsigned long)text.length);
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
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Thoát mà chưa lưu?"
			message:@"Nội dung đang sửa sẽ bị mất."
		confirmText:@"Thoát không lưu"
			 action:^{
		[weakSelf.textView resignFirstResponder];
		[weakSelf.navigationController popViewControllerAnimated:YES];
	}];
}

#pragma mark - Mẫu prompt

- (void)sx_showTemplates:(id)sender {
	(void)sender;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Chọn mẫu prompt"
																  message:@"Mẫu sẽ thay nội dung đang soạn (có hỏi lại nếu chưa lưu)."
														   preferredStyle:UIAlertControllerStyleActionSheet];
	NSArray<NSString *> *titles = SXTemplateTitles();
	NSArray<NSString *> *summaries = SXTemplateSummaries();
	__weak typeof(self) weakSelf = self;
	[titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
		(void)stop;
		UIAlertAction *action = [UIAlertAction actionWithTitle:title
														 style:UIAlertActionStyleDefault
													   handler:^(UIAlertAction *item) {
			(void)item;
			[weakSelf sx_applyTemplateAtIndex:(NSInteger)idx];
		}];
		if (idx < summaries.count) action.accessibilityHint = summaries[idx];
		[sheet addAction:action];
	}];
	[sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	UIPopoverPresentationController *popover = sheet.popoverPresentationController;
	if (popover) popover.barButtonItem = self.saveItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)sx_applyTemplateAtIndex:(NSInteger)index {
	NSString *text = SXTemplateAtIndex(index);
	if (!text.length) return;
	__weak typeof(self) weakSelf = self;
	void (^apply)(void) = ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if ([strongSelf.textView.text isEqualToString:text]) return;
		strongSelf.textView.text = text;
		[strongSelf.textView becomeFirstResponder];
		[strongSelf updateStatus];
	};
	if (![self isDirty]) {
		apply();
		return;
	}
	[SXUI confirmOn:self
			  title:@"Thay nội dung đang soạn?"
			message:@"Nội dung đã sửa nhưng chưa lưu sẽ bị thay bằng mẫu."
		confirmText:@"Thay bằng mẫu"
			 action:^{
		apply();
	}];
}

#pragma mark - Bàn phím

- (void)sx_keyboardWillChange:(NSNotification *)note {
	NSDictionary *userInfo = note.userInfo;
	CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationOptions curve = (UIViewAnimationOptions)([userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16);

	CGRect converted = [self.view convertRect:endFrame fromView:nil];
	CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
	UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);

	[UIView animateWithDuration:duration delay:0 options:curve animations:^{
		self.textView.contentInset = insets;
		self.textView.scrollIndicatorInsets = insets;
	} completion:nil];
}

@end
