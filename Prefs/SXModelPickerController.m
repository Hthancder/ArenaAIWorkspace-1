#import "SXModelPickerController.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXUISupport.h"
#import <notify.h>
#import <UIKit/UIKit.h>

@interface SXModelPickerController ()
@property (nonatomic) SXProvider provider;
@property (nonatomic) BOOL providerResolved;
@end

@implementation SXModelPickerController

- (SXProvider)provider {
	if (!self.providerResolved) {
		NSString *value = nil;
		@try {
			value = [[self specifier] propertyForKey:@"providerPicker"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc providerPicker: %@", exception.reason);
		}
		_provider = [value isEqualToString:@"gemini"] ? SXProviderGemini : SXProviderOpenAI;
		_providerResolved = YES;
	}
	return _provider;
}

- (NSString *)modelKey {
	return self.provider == SXProviderGemini ? @"geminiModel" : @"openaiModel";
}

- (NSString *)currentModel {
	SXPrefs *prefs = [SXPrefs shared];
	NSString *model = self.provider == SXProviderGemini ? prefs.geminiModel : prefs.openaiModel;
	if (model.length) return model;
	return self.provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini";
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *list = [NSMutableArray array];

		PSSpecifier *group = [PSSpecifier groupSpecifierWithName:
							  [NSString stringWithFormat:@"Mô hình %@", SXProviderDisplayName(self.provider)]];
		[group setProperty:@"Chọn một mô hình có sẵn. Muốn dùng tên khác, quay lại và nhập tay vào ô “Mô hình tùy chỉnh”."
				  forKey:@"footerText"];
		[list addObject:group];

		for (NSDictionary *preset in SXModelPresets(self.provider)) {
			NSString *title = preset[@"title"];
			NSString *hint = preset[@"hint"];
			NSString *label = hint.length ? [NSString stringWithFormat:@"%@ — %@", title, hint] : title;
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:label
															 target:self
																set:NULL
																get:NULL
															 detail:Nil
															   cell:PSButtonCell
															   edit:Nil];
			row.buttonAction = @selector(sx_chooseModel:);
			[row setProperty:preset[@"model"] forKey:@"modelValue"];
			[list addObject:row];
		}

		_specifiers = list;
	}
	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Mô hình";
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	[super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
	NSString *model = nil;
	@try {
		model = [[self specifierAtIndexPath:indexPath] propertyForKey:@"modelValue"];
	} @catch (NSException *exception) {
		model = nil;
	}
	if (![model isKindOfClass:[NSString class]]) return;
	BOOL selected = [model isEqualToString:self.currentModel];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.tintColor = [SXUI accentColor];
}

- (void)sx_chooseModel:(PSSpecifier *)sender {
	NSString *model = [sender propertyForKey:@"modelValue"];
	if (![model isKindOfClass:[NSString class]] || !model.length) return;
	[SXPrefs setValue:model forKey:self.modelKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"chọn mô hình %@ = %@", SXProviderDisplayName(self.provider), model);
	[self.navigationController popViewControllerAnimated:YES];
}

@end
