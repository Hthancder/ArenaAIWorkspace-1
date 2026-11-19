#import "SXAPIChoiceController.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import <notify.h>

@interface SXAPIChoiceController ()
@property (nonatomic, strong) NSArray *values;          // NSString hoặc NSNumber
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSArray<NSString *> *hints;
@property (nonatomic, copy) NSString *prefsKey;
@property (nonatomic, copy) NSString *screenTitle;
@end

@implementation SXAPIChoiceController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self sx_loadFromSpecifier];
	self.title = self.screenTitle.length ? self.screenTitle : @"Chọn giá trị";
	SXLogDbg(@"pref", @"bộ chọn giá trị mở: key=%@, %lu lựa chọn, specifier=%@",
			 self.prefsKey ?: @"(trống)", (unsigned long)self.values.count,
			 NSStringFromClass([self.specifier class]));
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, self.screenTitle ?: @"Chọn giá trị",
								  @"không đọc được danh sách lựa chọn");
}

/// `specifier` (hàng vừa bấm) có thể tới sau `viewDidLoad`; nếu lúc đó đang
/// dùng giá trị mặc định thì đọc lại. Không đọc lại thì trang hiện đúng số
/// hàng nhưng của SAI khoá — hoặc rỗng nếu plist không có `validValues`.
- (void)sx_refreshFromSpecifierIfNeeded {
	@try {
		PSSpecifier *specifier = self.specifier;
		if (!specifier) return;
		NSString *key = [specifier propertyForKey:@"configKey"];
		if (!key.length) key = [specifier propertyForKey:@"key"];
		if (!key.length) key = [specifier propertyForKey:PSKeyNameKey];
		if (![key isKindOfClass:[NSString class]] || !key.length) return;
		if ([key isEqualToString:self.prefsKey]) return;
		[self sx_loadFromSpecifier];
		self.title = self.screenTitle.length ? self.screenTitle : @"Chọn giá trị";
		_specifiers = nil;
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"đọc lại specifier: %@", exception.reason);
	}
}

/// Đọc `key`, `validValues`, `validTitles` (và `footerText` làm gợi ý) từ đúng
/// hàng gọi nó. Một controller phục vụ mọi câu “chọn một trong vài giá trị”,
/// nên không còn lớp Apple nào phải đoán dữ liệu nằm ở đâu.
- (void)sx_loadFromSpecifier {
	PSSpecifier *specifier = self.specifier;
	NSString *key = [specifier propertyForKey:@"configKey"];
	if (!key.length) key = [specifier propertyForKey:@"key"];
	if (!key.length) key = [specifier propertyForKey:PSKeyNameKey];
	// Không đoán bừa khi thiếu key: trước đây rơi về `openaiApi` nên mở nhầm
	// trang sẽ thấy 3 lựa chọn giao thức cho một khoá khác hẳn.
	self.prefsKey = ([key isKindOfClass:[NSString class]] && key.length) ? key : nil;
	self.screenTitle = [specifier propertyForKey:@"label"];
	NSArray *values = [specifier propertyForKey:@"validValues"];
	NSArray *titles = [specifier propertyForKey:@"validTitles"];
	if (![values isKindOfClass:[NSArray class]] || !values.count) {
		// Chỉ trang “Giao thức API” mới không khai báo validValues trong plist.
		if ([self.prefsKey isEqualToString:@"openaiApi"]) {
			values = @[@"auto", @"responses", @"chat"];
		} else {
			SXLogWrn(@"pref", @"bộ chọn %@ thiếu validValues trong plist (specifier=%@)",
					 self.prefsKey ?: @"(trống)", NSStringFromClass(specifier.class));
			values = @[];
		}
	}
	if (![titles isKindOfClass:[NSArray class]] || titles.count != values.count) {
		if ([self.prefsKey isEqualToString:@"openaiApi"]) {
			titles = @[@"Tự dò", @"Responses API", @"Chat completions"];
		} else {
			titles = values;
		}
	}
	self.values = values;
	self.titles = titles;
	NSString *footer = [specifier propertyForKey:@"footerText"];
	self.hints = footer.length ? @[] : @[];
	(void)footer;
}

/// Giá trị đang lưu, đọc lại từ đĩa mỗi lần vẽ để không hiện ✓ cũ.
- (id)sx_current {
	if (!self.prefsKey.length) return [self sx_defaultValue];
	[[SXPrefs shared] reload];
	if ([self.prefsKey isEqualToString:@"openaiApi"]) {
		return SXOpenAIApiStorageKey([SXPrefs shared].openaiApi);
	}
	NSString *value = [SXPrefs stringForKey:self.prefsKey];
	return value.length ? value : [self sx_defaultValue];
}

- (NSString *)sx_defaultValue {
	NSString *value = [self.specifier propertyForKey:@"default"];
	if ([value isKindOfClass:[NSString class]] && value.length) return value;
	if ([self.prefsKey isEqualToString:@"openaiApi"]) return @"auto";
	return [self.values.firstObject isKindOfClass:[NSString class]] ? self.values.firstObject : @"";
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		[self sx_refreshFromSpecifierIfNeeded];
		NSMutableArray *items = [NSMutableArray array];
		PSSpecifier *group = [PSSpecifier groupSpecifierWithName:self.screenTitle ?: @"Chọn giá trị"];
		NSString *footer = [self.specifier propertyForKey:@"footerText"];
		if (footer.length) [group setProperty:footer forKey:@"footerText"];
		[items addObject:group];

		id current = [self sx_current];
		for (NSUInteger i = 0; i < self.values.count; i++) {
			id candidate = self.values[i];
			NSString *value = [candidate isKindOfClass:[NSString class]]
				? candidate : [candidate description];
			BOOL active = [value isEqual:current] ||
				([candidate isKindOfClass:[NSNumber class]] && [current isKindOfClass:[NSNumber class]] &&
				 [candidate isEqual:current]);
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:self.titles[i]
															 target:self
																set:@selector(sx_pick:specifier:)
																get:nil
															 detail:nil
															   cell:PSListItemCell
															   edit:nil];
			[row setProperty:@(active) forKey:@"sxActive"];
			if (i < self.hints.count) [row setProperty:self.hints[i] forKey:@"sxHint"];
			[items addObject:row];
		}
		if (items.count <= 1) {
			SXLogErr(@"pref", @"bộ chọn %@ không có lựa chọn nào (validValues=? )",
					 self.prefsKey ?: @"(trống)");
			[items.firstObject setProperty:[NSString stringWithFormat:
					@"Chưa đọc được danh sách lựa chọn cho “%@”. Mở lại từ trang chính.",
					self.prefsKey.length ? self.prefsKey : @"(không rõ)"] forKey:@"footerText"];
		}
		_specifiers = items;
	}
	return _specifiers;
}

/// `PSListController` không tự hiện dấu "đang chọn" cho PSListItemCell — giá trị
/// trả về ở đây được cell vẽ ở phía phải (cùng chỗ với chữ "Giá trị" của hàng
/// số), nên chỉ cần trả "✓" cho hàng đang dùng.
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	return [[specifier propertyForKey:@"sxActive"] boolValue] ? @"✓" : @"";
}

- (void)sx_pick:(PSSpecifier *)specifier {
	if (!self.prefsKey.length) {
		[SXUI alertOn:self title:@"Chưa xác định được khoá cài đặt"
			  message:@"Mở lại trang này từ màn hình chính SiriX. Nếu vẫn lỗi, vào Gỡ lỗi → Xem log để gửi lại."];
		return;
	}
	NSInteger index = [self.specifiers indexOfObjectIdenticalTo:specifier];
	NSInteger valueIndex = index - 1;   // trừ hàng nhóm ở đầu
	if (valueIndex < 0 || (NSUInteger)valueIndex >= self.values.count) return;
	id chosen = self.values[(NSUInteger)valueIndex];
	NSString *stored = [chosen isKindOfClass:[NSString class]] ? chosen : [chosen description];
	if ([self.prefsKey isEqualToString:@"openaiApi"]) {
		stored = SXOpenAIApiStorageKey([chosen isKindOfClass:[NSNumber class]]
			? (SXOpenAIApi)[chosen integerValue] : SXOpenAIApiAuto);
	}
	[SXPrefs setString:stored forKey:self.prefsKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"chọn %@ = %@", self.prefsKey, stored);
	[self.navigationController popViewControllerAnimated:YES];
}

@end
