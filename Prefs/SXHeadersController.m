#import "SXHeadersController.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#pragma mark - Ô header trong danh sách

@interface SXHeaderRowCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISwitch *toggle;
@end

@implementation SXHeaderRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleDefault;

	_nameLabel = [[UILabel alloc] init];
	_nameLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
	_nameLabel.numberOfLines = 1;
	_nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

	_valueLabel = [[UILabel alloc] init];
	_valueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	_valueLabel.textColor = UIColor.secondaryLabelColor;
	_valueLabel.numberOfLines = 1;
	_valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _valueLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 2;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];

	_toggle = [[UISwitch alloc] init];
	_toggle.onTintColor = [SXUI accentColor];
	_toggle.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_toggle];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
		[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
		[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor constant:-10],
		[_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_toggle.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
}

@end

#pragma mark - Màn hình sửa một header

@interface SXHeaderEditController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic) SXHeaderPresetProvider presetProvider;
@property (nonatomic, copy) NSString *endpointHint;
@property (nonatomic, copy) NSArray<NSDictionary *> *existing;
@property (nonatomic, copy, nullable) NSDictionary *editing;
@property (nonatomic, copy) void (^onSave)(NSDictionary *header);
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, copy) NSArray<NSDictionary *> *suggestions;
@property (nonatomic, assign) SXHeaderIssue issue;
@end

@implementation SXHeaderEditController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.editing ? @"Sửa header" : @"Thêm header";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.suggestions = SXHeaderPresetsForEndpoint(self.presetProvider, self.endpointHint);

	self.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
													  target:self
													  action:@selector(sx_cancel)];
	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
													  target:self
													  action:@selector(sx_save)];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		// Bàn phím không che ô đang gõ (iOS 15+).
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
	]];
	[self sx_validate];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!self.editing) [self.nameField becomeFirstResponder];
}

- (UITextField *)sx_fieldWithPlaceholder:(NSString *)placeholder
									text:(NSString *)text
							   monospaced:(BOOL)monospaced {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.text = text ?: @"";
	field.font = monospaced ? [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular]
							: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.spellCheckingType = UITextSpellCheckingTypeNo;
	field.smartQuotesType = UITextSmartQuotesTypeNo;
	field.smartDashesType = UITextSmartDashesTypeNo;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.returnKeyType = UIReturnKeyNext;
	field.delegate = self;
	[field addTarget:self action:@selector(sx_fieldChanged) forControlEvents:UIControlEventEditingChanged];
	field.translatesAutoresizingMaskIntoConstraints = NO;
	return field;
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 3; // tên · giá trị · gợi ý
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	return section == 2 ? (NSInteger)self.suggestions.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return @"Tên header";
	if (section == 1) return @"Giá trị";
	return self.suggestions.count ? @"Gợi ý nhanh" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) {
		BOOL untouched = ![SXHeaderTrimmedName(self.nameField.text) length];
		NSString *message = untouched ? @"" : SXHeaderIssueMessage(self.issue, SXHeaderTrimmedName(self.nameField.text));
		if (message.length) return message;
		return @"Ví dụ: X-Title, HTTP-Referer, api-key. Header hệ thống (Host, Content-Type, Content-Length) bị bỏ qua vì sẽ làm hỏng request.";
	}
	if (section == 1) {
		NSString *warning = [self sx_insecureWarning];
		if (warning.length) return warning;
		return @"Giá trị không được hiện trong danh sách và không bao giờ được ghi vào log.";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2) {
		return [self sx_suggestionCellForTable:tableView indexPath:indexPath];
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"field"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"field"];
	}
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UITextField *field = indexPath.section == 0 ? self.nameField : self.valueField;
	if (!field) {
		if (indexPath.section == 0) {
			field = [self sx_fieldWithPlaceholder:@"X-Title" text:self.editing[@"name"] monospaced:YES];
			field.returnKeyType = UIReturnKeyNext;
			self.nameField = field;
		} else {
			field = [self sx_fieldWithPlaceholder:@"giá trị" text:self.editing[@"value"] monospaced:YES];
			field.returnKeyType = UIReturnKeyDone;
			// Token dán từ trang web hay dính xuống dòng — nút Dán cắt sạch giúp.
			UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
			[paste setTitle:@"Dán" forState:UIControlStateNormal];
			paste.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
			[paste sizeToFit];
			[paste addTarget:self action:@selector(sx_pasteValue) forControlEvents:UIControlEventTouchUpInside];
			field.rightView = paste;
			field.rightViewMode = UITextFieldViewModeAlways;
			self.valueField = field;
		}
	}
	if (field.superview != cell.contentView) {
		[field removeFromSuperview];
		[cell.contentView addSubview:field];
	}
	UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[field.topAnchor constraintEqualToAnchor:margins.topAnchor],
		[field.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
		[field.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[field.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[field.heightAnchor constraintGreaterThanOrEqualToConstant:32],
	]];
	return cell;
}

- (UITableViewCell *)sx_suggestionCellForTable:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"suggestion"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"suggestion"];
	}
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = UIColor.labelColor;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.numberOfLines = 0;

	NSDictionary *preset = indexPath.row < (NSInteger)self.suggestions.count ? self.suggestions[indexPath.row] : nil;
	NSString *value = preset[@"value"];
	cell.textLabel.text = preset ? (value.length ? [NSString stringWithFormat:@"%@: %@", preset[@"name"], value]
												  : [NSString stringWithFormat:@"%@: (tự điền)", preset[@"name"]]) : @"";
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	cell.detailTextLabel.text = preset[@"note"];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 2) return;
	if (indexPath.row >= (NSInteger)self.suggestions.count) return;
	NSDictionary *preset = self.suggestions[indexPath.row];
	self.nameField.text = preset[@"name"];
	self.valueField.text = preset[@"value"] ?: @"";
	[self sx_validate];
	[SXUI tapFeedback];
	// Điền xong thì đưa người dùng tới ô còn thiếu để sửa ngay.
	if (![(NSString *)self.valueField.text length]) [self.valueField becomeFirstResponder];
	else [self.valueField resignFirstResponder];
}

#pragma mark - Kiểm tra & lưu

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField == self.nameField) {
		[self.valueField becomeFirstResponder];
	} else {
		[self sx_save];
	}
	return YES;
}

/// Endpoint http:// (không phải https) thì header — kể cả token — đi trên mạng
/// không mã hoá. Cảnh báo ngay dưới ô nhập thay vì để người dùng tự phát hiện.
- (NSString *)sx_insecureWarning {
	if (self.presetProvider != SXHeaderPresetProviderOpenAI) return nil;
	NSString *base = [SXPrefs shared].openaiBase.lowercaseString;
	if (![base hasPrefix:@"http://"]) return nil;
	return @"⚠️ Endpoint đang dùng http:// nên giá trị header (kể cả token) đi trên mạng không mã hoá. "
			@"Hãy đổi sang https:// nếu máy chủ hỗ trợ.";
}

- (void)sx_pasteValue {
	NSString *clipboard = UIPasteboard.generalPasteboard.string;
	if (![clipboard isKindOfClass:[NSString class]] || !clipboard.length) {
		[SXUI alertOn:self title:@"Bộ nhớ tạm trống" message:@"Sao chép giá trị header trước rồi thử lại."];
		return;
	}
	NSString *firstLine = [[clipboard componentsSeparatedByCharactersInSet:
							[NSCharacterSet newlineCharacterSet]] firstObject];
	self.valueField.text = [firstLine stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[self sx_validate];
	[SXUI tapFeedback];
}

- (void)sx_fieldChanged {
	[self sx_validate];
}

- (void)sx_validate {
	self.issue = SXHeaderValidate(self.nameField.text, self.valueField.text, self.existing,
								  self.editing[@"name"]);
	self.navigationItem.rightBarButtonItem.enabled = (self.issue == SXHeaderIssueNone);
	if ([self.table numberOfSections] > 0) {
		@try {
			[self.table reloadSections:[NSIndexSet indexSetWithIndex:0]
					  withRowAnimation:UITableViewRowAnimationNone];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"reload footer header: %@", exception.reason);
		}
	}
}

- (void)sx_close {
	if (self.navigationController && self.navigationController.viewControllers.count > 1) {
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	if (self.navigationController) {
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sx_save {
	NSString *name = SXHeaderTrimmedName(self.nameField.text);
	NSString *value = [self.valueField.text stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	SXHeaderIssue issue = SXHeaderValidate(name, value, self.existing, self.editing[@"name"]);
	if (issue != SXHeaderIssueNone) {
		self.issue = issue;
		[self sx_validate];
		[SXUI alertOn:self title:@"Header chưa hợp lệ" message:SXHeaderIssueMessage(issue, name)];
		return;
	}
	NSDictionary *header = @{@"name": name, @"value": value,
							 @"enabled": self.editing[@"enabled"] ?: @YES};
	if (self.onSave) self.onSave(header);
	[SXUI tapFeedback];
	[self sx_close];
}

- (void)sx_cancel {
	[self sx_close];
}

@end

#pragma mark - Danh sách header

@interface SXHeadersController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) SXProvider provider;
@property (nonatomic) BOOL providerResolved;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSMutableArray<NSDictionary *> *headers;
@end

@implementation SXHeadersController

#pragma mark - Nhà cung cấp

- (SXProvider)provider {
	if (!self.providerResolved) {
		NSString *value = nil;
		@try {
			value = [[self specifier] propertyForKey:@"headersProvider"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc headersProvider: %@", exception.reason);
		}
		if (![value isKindOfClass:[NSString class]] || !value.length) {
			value = [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai";
		}
		_provider = [value isEqualToString:@"gemini"] ? SXProviderGemini : SXProviderOpenAI;
		_providerResolved = YES;
	}
	return _provider;
}

/// Endpoint đang cấu hình — dùng để xếp gợi ý khớp lên đầu (OpenRouter, Azure…).
- (NSString *)endpointHint {
	if (self.provider == SXProviderGemini) return @"generativelanguage.googleapis.com";
	NSString *base = [SXPrefs shared].openaiBase;
	return [base isKindOfClass:[NSString class]] ? base : @"";
}

- (SXHeaderPresetProvider)presetProvider {
	return self.provider == SXProviderGemini ? SXHeaderPresetProviderGemini : SXHeaderPresetProviderOpenAI;
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Header tuỳ chỉnh";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
													  target:self
													  action:@selector(sx_addHeader)];
	self.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:@"Sửa" style:UIBarButtonItemStylePlain
										target:self action:@selector(sx_toggleEditing)];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 64;
	[self.table registerClass:[SXHeaderRowCell class] forCellReuseIdentifier:@"header"];
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	[self sx_reloadFromPrefs];
	SXLogDbg(@"pref", @"mở header tuỳ chỉnh %@ (%lu mục)",
			 SXProviderDisplayName(self.provider), (unsigned long)self.headers.count);
}

#pragma mark - Dữ liệu

- (void)sx_reloadFromPrefs {
	self.headers = [[[SXPrefs shared] headersForProvider:self.provider] mutableCopy] ?: [NSMutableArray array];
	[self sx_refreshEmptyState];
	@try {
		[self.table reloadData];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload header: %@", exception.reason);
	}
}

- (void)sx_persist {
	[SXPrefs setHeaders:self.headers forProvider:self.provider];
	notify_post("com.sirix.tweak/prefs.changed");
	[self sx_refreshEmptyState];
}

- (void)sx_refreshEmptyState {
	if (self.headers.count) {
		self.table.backgroundView = nil;
		return;
	}
	self.table.backgroundView = [SXUI emptyStateWithSymbol:@"list.bullet.rectangle"
													 title:@"Chưa có header nào"
												   message:@"Hầu hết nhà cung cấp không cần header thêm. Chỉ thêm khi gateway hoặc proxy của bạn yêu cầu (OpenRouter, Azure, máy chủ nội bộ…)."];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)section;
	return (NSInteger)self.headers.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)section;
	return SXProviderDisplayName(self.provider);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)section;
	return [NSString stringWithFormat:
			@"%@. Header được gửi kèm mọi request tới %@ — kể cả Kiểm tra kết nối và Trò chuyện thử. "
			@"Giá trị chỉ lưu trên máy, không ghi vào log; tắt công tắc để ngừng gửi mà không phải xoá.",
			SXHeadersSummary(self.headers), SXProviderDisplayName(self.provider)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SXHeaderRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"header" forIndexPath:indexPath];
	NSDictionary *header = indexPath.row < (NSInteger)self.headers.count ? self.headers[indexPath.row] : nil;
	if (!header) return cell;
	cell.nameLabel.text = header[@"name"];
	cell.valueLabel.text = SXHeaderValueMasked(header[@"value"]);
	cell.toggle.on = header[@"enabled"] == nil || [header[@"enabled"] boolValue];
	cell.toggle.tag = indexPath.row;
	cell.toggle.accessibilityLabel = [NSString stringWithFormat:@"Gửi header %@", header[@"name"]];
	cell.nameLabel.accessibilityLabel = nil;
	[cell.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[cell.toggle addTarget:self action:@selector(sx_toggleChanged:) forControlEvents:UIControlEventValueChanged];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.headers.count) return;
	[self sx_editHeaderAtIndex:indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView; (void)indexPath;
	return YES;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;
	if (indexPath.row >= (NSInteger)self.headers.count) return;
	NSString *name = self.headers[indexPath.row][@"name"];
	[self.headers removeObjectAtIndex:indexPath.row];
	[self sx_persist];
	[self.table deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"xoá header %@ của %@", name, SXProviderDisplayName(self.provider));
	@try {
		[self.table reloadSections:[NSIndexSet indexSetWithIndex:0]
				  withRowAnimation:UITableViewRowAnimationNone];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload footer sau xoá: %@", exception.reason);
	}
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView; (void)indexPath;
	return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	if (from.row >= (NSInteger)self.headers.count || to.row >= (NSInteger)self.headers.count) return;
	NSDictionary *header = self.headers[from.row];
	[self.headers removeObjectAtIndex:from.row];
	[self.headers insertObject:header atIndex:to.row];
	[self sx_persist];
}

#pragma mark - Hành động

- (void)sx_toggleEditing {
	[self.table setEditing:!self.table.isEditing animated:YES];
	self.navigationItem.leftBarButtonItem.title = self.table.isEditing ? @"Xong" : @"Sửa";
}

- (void)sx_toggleChanged:(UISwitch *)sender {
	NSInteger index = sender.tag;
	if (index < 0 || index >= (NSInteger)self.headers.count) return;
	NSDictionary *header = self.headers[index];
	self.headers[index] = @{@"name": header[@"name"] ?: @"", @"value": header[@"value"] ?: @"",
							@"enabled": @(sender.isOn)};
	[self sx_persist];
	[SXUI tapFeedback];
	SXLogDbg(@"pref", @"header %@ → %@", header[@"name"], sender.isOn ? @"bật" : @"tắt");
	@try {
		[self.table reloadSections:[NSIndexSet indexSetWithIndex:0]
				  withRowAnimation:UITableViewRowAnimationNone];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload footer sau bật/tắt: %@", exception.reason);
	}
}

- (void)sx_addHeader {
	[self sx_presentEditorWithIndex:NSNotFound];
}

- (void)sx_editHeaderAtIndex:(NSInteger)index {
	[self sx_presentEditorWithIndex:index];
}

- (void)sx_presentEditorWithIndex:(NSInteger)index {
	SXHeaderEditController *editor = [[SXHeaderEditController alloc] init];
	editor.presetProvider = self.presetProvider;
	editor.endpointHint = [self endpointHint];
	editor.existing = [self.headers copy];
	editor.editing = (index != NSNotFound && index < (NSInteger)self.headers.count) ? self.headers[index] : nil;
	__weak typeof(self) weakSelf = self;
	editor.onSave = ^(NSDictionary *header) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (index != NSNotFound && index < (NSInteger)strongSelf.headers.count) {
			strongSelf.headers[index] = header;
		} else {
			[strongSelf.headers addObject:header];
		}
		[strongSelf sx_persist];
		[strongSelf.table reloadData];
		SXLogInf(@"pref", @"lưu header %@ cho %@ (%lu mục)",
				 header[@"name"], SXProviderDisplayName(strongSelf.provider),
				 (unsigned long)strongSelf.headers.count);
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	[self presentViewController:nav animated:YES completion:nil];
}

@end
