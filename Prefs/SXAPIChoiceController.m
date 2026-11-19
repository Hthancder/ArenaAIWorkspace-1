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
}

/// Đọc `key`, `validValues`, `validTitles` (và `footerText` làm gợi ý) từ đúng
/// hàng gọi nó. Một controller phục vụ mọi câu “chọn một trong vài giá trị”,
/// nên không còn lớp Apple nào phải đoán dữ liệu nằm ở đâu.
- (void)sx_loadFromSpecifier {
	PSSpecifier *specifier = self.specifier;
	NSString *key = [specifier propertyForKey:@"key"];
	if (!key.length) key = [specifier propertyForKey:PSKeyNameKey];
	self.prefsKey = key.length ? key : @"openaiApi";
	self.screenTitle = [specifier propertyForKey:@"label"];
	NSArray *values = [specifier propertyForKey:@"validValues"];
	NSArray *titles = [specifier propertyForKey:@"validTitles"];
	if (![values isKindOfClass:[NSArray class]] || !values.count) {
		values = @[@"auto", @"responses", @"chat"];
	}
	if (![titles isKindOfClass:[NSArray class]] || titles.count != values.count) {
		titles = values;
	}
	self.values = values;
	self.titles = titles;
	NSString *footer = [specifier propertyForKey:@"footerText"];
	self.hints = footer.length ? @[] : @[];
	(void)footer;
}

/// Giá trị đang lưu, đọc lại từ đĩa mỗi lần vẽ để không hiện ✓ cũ.
- (id)sx_current {
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
