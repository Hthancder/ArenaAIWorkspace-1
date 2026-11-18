#import "SXMediaController.h"
#import "PSSpecifier.h"
#import "SXPrefs.h"
#import "SXTTS.h"
#import <notify.h>

@implementation SXMediaController
- (NSArray *)specifiers {
	if (!_specifiers) {
		BOOL stt = [[self.specifier propertyForKey:@"configPlist"] isEqual:@"STTConfig"];
		NSDictionary *settings = [SXPrefs shared].settings;
		NSDictionary *config = stt ? SXSTTConfiguration(settings) : SXTTSConfiguration(settings);
		NSString *source = config[@"source"];
		NSDictionary *fields = stt ? SXSTTFields(settings) : SXMediaProfiles(@"tts")[source];
		NSArray *loaded = [self loadSpecifiersFromPlistName:stt ? @"STTConfig" : @"TTSConfig" target:self];
		NSMutableArray *mapped = [NSMutableArray array];
		for (PSSpecifier *specifier in loaded) {
			NSString *field = [specifier propertyForKey:@"sxField"];
			if (field) {
				NSString *key = fields[field];
				if (!key) continue;
				[specifier setProperty:key forKey:@"key"];
			}
			if ([field isEqual:@"model"]) [specifier setProperty:config[@"defaultModel"] forKey:@"placeholder"];
			if ([specifier.identifier isEqual:@"sx-stt-about"]) {
				NSString *name = SXProviderName(SXProviderFromID(source));
				BOOL automatic = [settings[@"sttSource"] isEqual:@"auto"];
				NSString *note = automatic ? [NSString stringWithFormat:@"Theo cấu hình AI: dùng địa chỉ và khóa của %@. Mô hình nhận diện khác mô hình chat.", name] :
					([source isEqual:@"custom"] ? @"Nhập địa chỉ HTTPS hỗ trợ /audio/transcriptions. Chỉ nhập khóa nếu máy chủ yêu cầu." :
						[NSString stringWithFormat:@"Dùng địa chỉ chính thức của %@. Bỏ trống khóa STT để dùng khóa AI của cùng nhà cung cấp.", name]);
				if ([settings[@"sttTranslate"] isEqual:@"en"] && ![source isEqual:@"gemini"]) {
					NSString *hint = SXSTTUsesFixedEnglishModel(settings) ?
						[NSString stringWithFormat:@"Dịch sang tiếng Anh dùng %@ và tự nhận ngôn ngữ.", config[@"model"]] : @"Dịch sang tiếng Anh cần /audio/translations và tự nhận ngôn ngữ.";
					note = [note stringByAppendingFormat:@"\n%@", hint];
				}
				[specifier setProperty:note forKey:@"footerText"];
			}
			if ([specifier.identifier isEqual:@"sx-tts-about"]) {
				NSString *note = [source isEqual:@"google"] ? @"Google Cloud dùng địa chỉ cố định và cần khóa đã bật Text-to-Speech API." :
					([source isEqual:@"gemini"] ? @"Dùng địa chỉ chính thức của Gemini. Bỏ trống khóa TTS để dùng khóa API Gemini đã lưu." :
						@"Nhập địa chỉ HTTPS hỗ trợ /audio/speech. Mô hình, giọng và ngôn ngữ phụ thuộc máy chủ; chỉ nhập khóa nếu máy chủ yêu cầu.");
				[specifier setProperty:note forKey:@"footerText"];
			}
			[mapped addObject:specifier];
		}
		_specifiers = [self sx_visibleSpecifiers:mapped settings:settings];
	}
	return _specifiers;
}
@end

@interface SXVoicePickerController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSDictionary *> *choices, *visible;
@property (nonatomic, copy) NSString *selected, *voiceKey;
@end
@implementation SXVoicePickerController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Giọng nói";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	self.voiceKey = SXMediaProfiles(@"tts")[prefs.ttsSource][@"voice"];
	NSArray *voices = SXTTSVoices(prefs);
	NSString *selected = self.voiceKey ? prefs.settings[self.voiceKey] : nil;
	self.selected = selected && [[voices valueForKey:@"id"] containsObject:selected] ? selected : @"";
	NSString *title = [prefs.ttsSource isEqual:@"gemini"] ? @"Giọng mặc định (Kore)" : @"Mặc định theo ngôn ngữ";
	self.choices = [@[@{@"id": @"", @"name": title}] arrayByAddingObjectsFromArray:voices];
	self.visible = self.choices;
	self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.table.dataSource = self; self.table.delegate = self;
	[self.view addSubview:self.table];
	UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
	search.searchResultsUpdater = self;
	search.obscuresBackgroundDuringPresentation = NO;
	search.searchBar.placeholder = @"Tìm giọng";
	self.navigationItem.searchController = search;
	self.definesPresentationContext = YES;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *query = searchController.searchBar.text;
	self.visible = query.length ? [self.choices filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *voice, NSDictionary *bindings) {
		(void)bindings; return [voice[@"name"] localizedCaseInsensitiveContainsString:query];
	}]] : self.choices;
	[self.table reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return (NSInteger)self.visible.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"voice"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"voice"];
	NSDictionary *voice = self.visible[indexPath.row];
	cell.textLabel.text = voice[@"name"];
	cell.textLabel.adjustsFontForContentSizeCategory = YES;
	cell.accessoryType = [voice[@"id"] isEqual:self.selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *voice = self.visible[indexPath.row][@"id"];
	[[SXPrefs shared] reload];
	NSString *source = [SXPrefs shared].ttsSource;
	if (!self.voiceKey || [source isEqual:@"custom"] || ![self.voiceKey isEqual:SXMediaProfiles(@"tts")[source][@"voice"]]) return;
	if (![SXPrefs writeValues:@{self.voiceKey: voice} removing:@[]]) return;
	[[SXPrefs shared] reload];
	self.selected = voice; [tableView reloadData];
	notify_post("com.sirix.tweak/prefs.changed");
}
@end
