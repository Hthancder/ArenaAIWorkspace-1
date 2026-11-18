#import "PSListController.h"

/// Shared validation and conditional rows for the SiriX preference panes.
@interface SXPreferenceListController : PSListController
- (NSMutableArray *)sx_visibleSpecifiers:(NSArray *)loaded settings:(NSDictionary *)settings;
- (void)sx_refreshLayout;
@end
