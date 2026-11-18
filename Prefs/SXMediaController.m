#import "SXMediaController.h"
#import "PSSpecifier.h"
#import "SXPrefs.h"
#import "SXTTS.h"
#import <notify.h>

@implementation SXMediaController
- (NSArray *)specifiers {
	if (!_specifiers) {
		NSString *name = [[self specifier] propertyForKey:@"configPlist"];
		_specifiers = [self loadSpecifiersFromPlistName:[name isEqual:@"STTConfig"] ? @"STTConfig" : @"TTSConfig" target:self];
	}
	return _specifiers;
}
@end

@interface SXVoicePickerController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSDictionary *> *choices, *visible;
@property (nonatomic, copy) NSString *selected;
@end
@implementation SXVoicePickerController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Giọng nói";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	self.selected = prefs.ttsVoice;
	self.choices = [@[@{@"id": @"", @"name": @"Mặc định theo ngôn ngữ"}] arrayByAddingObjectsFromArray:SXTTSVoices(prefs)];
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
	if (![SXPrefs writeValues:@{@"ttsVoice": voice} removing:@[]]) return;
	self.selected = voice; [tableView reloadData];
	notify_post("com.sirix.tweak/prefs.changed");
}
@end
