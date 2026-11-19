#import "SXModelPickerController.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import <notify.h>
#import <UIKit/UIKit.h>

/// Ô mô hình: tên thân thiện ở trên, mã mô hình (chữ đẳng khoảng) ở dưới, gợi ý
/// màu xám. Không dùng PSCell/PSSpecifier: bản trước dựng hàng bằng PSButtonCell
/// và gán `buttonAction` — Preferences thật không có setter đó nên Settings văng
/// ngay khi mở danh sách.
@interface SXModelCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation SXModelCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	_titleLabel = [[UILabel alloc] init];
	_titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_titleLabel.adjustsFontForContentSizeCategory = YES;
	_titleLabel.numberOfLines = 0;

	_modelLabel = [[UILabel alloc] init];
	_modelLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	_modelLabel.textColor = UIColor.secondaryLabelColor;

	_hintLabel = [[UILabel alloc] init];
	_hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	_hintLabel.adjustsFontForContentSizeCategory = YES;
	_hintLabel.textColor = UIColor.tertiaryLabelColor;
	_hintLabel.numberOfLines = 0;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _modelLabel, _hintLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 2;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
		[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
		[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
	]];
	return self;
}

@end

#pragma mark - Màn hình

@interface SXModelPickerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) SXProvider provider;
@property (nonatomic) BOOL providerResolved;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSDictionary *> *presets;
@property (nonatomic, copy) NSString *currentModel;
@end

@implementation SXModelPickerController

#pragma mark - Nhà cung cấp

- (SXProvider)provider {
	if (!self.providerResolved) {
		NSString *value = nil;
		@try {
			value = [[self specifier] propertyForKey:@"providerPicker"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc providerPicker: %@", exception.reason);
		}
		if (![value isKindOfClass:[NSString class]] || !value.length) {
			value = [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai";
		}
		_provider = [value isEqualToString:@"gemini"] ? SXProviderGemini : SXProviderOpenAI;
		_providerResolved = YES;
	}
	return _provider;
}

- (NSString *)modelKey {
	return self.provider == SXProviderGemini ? @"geminiModel" : @"openaiModel";
}

- (NSString *)preferredModel {
	SXPrefs *prefs = [SXPrefs shared];
	NSString *model = self.provider == SXProviderGemini ? prefs.geminiModel : prefs.openaiModel;
	model = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (model.length) return model;
	return self.provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini";
}

- (NSString *)presetTitleForModel:(NSString *)model {
	for (NSDictionary *preset in self.presets) {
		if ([preset[@"model"] isEqualToString:model]) return preset[@"title"];
	}
	return nil;
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [NSString stringWithFormat:@"Mô hình %@", SXProviderDisplayName(self.provider)];
	// Dòng ngữ cảnh dưới tiêu đề: đang cấu hình endpoint nào.
	NSString *endpoint = self.provider == SXProviderGemini
		? @"generativelanguage.googleapis.com"
		: ([SXPrefs normalizedBaseURL:[SXPrefs shared].openaiBase] ?: @"endpoint chưa hợp lệ");
	self.navigationItem.prompt = endpoint;
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.presets = SXModelPresets(self.provider) ?: @[];
	self.currentModel = [self preferredModel];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 78;
	[self.table registerClass:[SXModelCell class] forCellReuseIdentifier:@"model"];
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
	SXLogDbg(@"pref", @"mở danh sách mô hình %@ (%lu gợi ý, đang dùng %@)",
			 SXProviderDisplayName(self.provider), (unsigned long)self.presets.count, self.currentModel);
}

#pragma mark - Dữ liệu bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 3; // đang dùng · gợi ý · nhập tay
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return 1;
	if (section == 1) return (NSInteger)self.presets.count;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return @"Đang dùng";
	if (section == 1) return [NSString stringWithFormat:@"Gợi ý cho %@", SXProviderDisplayName(self.provider)];
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section == 2) {
		return @"Endpoint tương thích OpenAI dùng được mọi tên mô hình nó hỗ trợ (llama-3.3-70b, deepseek-chat…). "
				@"Mô hình suy luận (o4-mini, R1…) trả lời chậm hơn — SiriX vẫn chờ trong ngân sách đã đặt.";
	}
	if (section == 1 && !self.presets.count) return @"Nhà cung cấp này không có gợi ý sẵn.";
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SXModelCell *cell = [tableView dequeueReusableCellWithIdentifier:@"model" forIndexPath:indexPath];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.tintColor = [SXUI accentColor];

	if (indexPath.section == 2) {
		cell.titleLabel.text = @"Nhập mô hình khác…";
		cell.titleLabel.textColor = [SXUI accentColor];
		cell.modelLabel.text = nil;
		cell.hintLabel.text = @"Gõ đúng mã mô hình mà endpoint của bạn nhận.";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.accessibilityHint = @"Mở hộp thoại nhập mã mô hình.";
		return cell;
	}

	NSDictionary *preset = nil;
	if (indexPath.section == 0) {
		NSString *title = [self presetTitleForModel:self.currentModel];
		cell.titleLabel.text = title.length ? title : @"Mô hình nhập tay";
		cell.titleLabel.textColor = UIColor.labelColor;
		cell.modelLabel.text = self.currentModel;
		cell.hintLabel.text = title.length ? nil
			: @"Không nằm trong danh sách gợi ý — vẫn dùng bình thường nếu endpoint hỗ trợ.";
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
		cell.accessibilityValue = @"Đang dùng";
		return cell;
	}

	preset = indexPath.row < (NSInteger)self.presets.count ? self.presets[indexPath.row] : nil;
	if (!preset) return cell;
	cell.titleLabel.text = preset[@"title"];
	cell.titleLabel.textColor = UIColor.labelColor;
	cell.modelLabel.text = preset[@"model"];
	cell.hintLabel.text = preset[@"hint"];
	BOOL selected = [preset[@"model"] isEqualToString:self.currentModel];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.accessibilityValue = selected ? @"Đang dùng" : nil;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 2) {
		[self sx_promptForCustomModel];
		return;
	}
	NSString *model = nil;
	if (indexPath.section == 0) {
		model = self.currentModel;
	} else if (indexPath.row < (NSInteger)self.presets.count) {
		model = self.presets[indexPath.row][@"model"];
	}
	if (![model isKindOfClass:[NSString class]] || !model.length) return;
	[self sx_saveModel:model];
}

#pragma mark - Lưu

- (void)sx_saveModel:(NSString *)model {
	[SXPrefs setString:model forKey:self.modelKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"chọn mô hình %@ = %@", SXProviderDisplayName(self.provider), model);
	self.currentModel = model;
	@try {
		[self.table reloadData];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload bảng mô hình: %@", exception.reason);
	}
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)sx_promptForCustomModel {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mô hình khác"
																   message:@"Nhập đúng mã mô hình mà endpoint của bạn hỗ trợ."
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = @"ví dụ: llama-3.3-70b";
		field.text = self.currentModel;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Dùng" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		(void)action;
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
						  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!text.length) {
			[SXUI alertOn:strongSelf title:@"Chưa nhập gì" message:@"Mã mô hình không được để trống."];
			return;
		}
		[strongSelf sx_saveModel:text];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
