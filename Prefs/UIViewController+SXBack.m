#import "UIViewController+SXBack.h"

@implementation UIViewController (SXBack)

- (void)sx_goBack:(id)sender {
	(void)sender;
	UINavigationController *navigation = self.navigationController;
	if (navigation && navigation.viewControllers.count > 1) {
		[navigation popViewControllerAnimated:YES];
		return;
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
