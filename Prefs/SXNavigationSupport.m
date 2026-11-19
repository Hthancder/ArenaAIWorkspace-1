#import "SXNavigationSupport.h"
#import "UIViewController+SXBack.h"
#import "SXLog.h"

/// Target giữ lâu dài cho nút "Quay lại".
///
/// 1.1.11 và 1.1.12 đều dựng nút với `target:controller`. Nếu Preferences dựng
/// lại controller (điều nó làm mỗi lần hiện trang) thì target của nút đã chết
/// theo, cú bấm rơi vào khoảng không — đúng hiện tượng "nút hiện mà bấm không
/// có hiệu lực". Đối tượng dưới đây sống theo vòng đời app; lúc bấm nó mới đi
/// tìm trang đang hiển thị rồi gọi `sx_goBack:`.
@interface SXBackButtonProxy : NSObject
+ (instancetype)shared;
@property (nonatomic, weak) UIViewController *hint;
@end

@implementation SXBackButtonProxy

+ (instancetype)shared {
	static SXBackButtonProxy *proxy;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ proxy = [SXBackButtonProxy new]; });
	return proxy;
}

/// Trang đang hiện: ưu tiên trang gợi ý còn sống, rồi ngăn xếp thật, rồi modal.
static UIViewController *SXVisibleController(UIViewController *hint) {
	if (hint && hint.view.window) return hint;
	UIWindow *window = UIApplication.sharedApplication.keyWindow;
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	if ([top isKindOfClass:[UINavigationController class]]) {
		UIViewController *visible = ((UINavigationController *)top).topViewController;
		if (visible) return visible;
	}
	return top ?: hint;
}

- (void)goBack:(UIBarButtonItem *)sender {
	(void)sender;
	UIViewController *target = SXVisibleController(self.hint);
	SXLogInf(@"pref", @"nút Quay lại được bấm → đóng %@", NSStringFromClass(target.class));
	if ([target respondsToSelector:@selector(sx_goBack:)]) [target sx_goBack:sender];
}

@end

/// Gắn nút của mình nếu nút hệ thống chắc chắn không dùng được.
static void SXInstallBackButton(UIViewController *controller, NSString *title) {
	UINavigationItem *item = controller.navigationItem;
	if (!item) return;
	if ([item.leftBarButtonItem.target isKindOfClass:[SXBackButtonProxy class]]) return;

	UINavigationController *navigation = controller.navigationController;
	BOOL stackHasPrevious = navigation && navigation.viewControllers.count > 1;
	// Nút trái do người khác đặt và ngăn xếp có trang trước → tin được, để yên.
	if (item.leftBarButtonItem && stackHasPrevious) return;

	UIBarButtonItem *back = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
				style:UIBarButtonItemStylePlain
			   target:[SXBackButtonProxy shared]
			   action:@selector(goBack:)];
	back.accessibilityLabel = @"Quay lại";
	item.leftBarButtonItem = back;
	[SXBackButtonProxy shared].hint = controller;
	SXLogInf(@"pref", @"tự thêm nút Quay lại cho %@ (nav=%@, %lu trang)",
			 NSStringFromClass(controller.class),
			 navigation ? @"có" : @"không",
			 (unsigned long)navigation.viewControllers.count);
}

void SXEnsureBackButton(UIViewController *controller, NSString *title) {
	if (!controller) return;
	UINavigationItem *item = controller.navigationItem;
	if (!item) return;

	// Tên trang trước: hệ thống dùng nó cho nút Back. Đặt sớm để iOS tự dựng
	// nút với đúng nhãn thay vì để trống.
	if (title.length && !item.backButtonTitle.length) item.backButtonTitle = title;

	// Trang gốc không có gì để quay lại.
	BOOL isRoot = controller.navigationController
		? controller.navigationController.viewControllers.count <= 1
		: controller.presentingViewController == nil;
	if (isRoot) return;

	// Cài ngay, rồi cài lại sau vài nhịp vẽ: Preferences đặt lại thanh điều
	// hướng sau khi controller đã hiện, có thể ghi đè nút vừa gắn.
	__weak UIViewController *weakController = controller;
	SXInstallBackButton(controller, title);
	dispatch_async(dispatch_get_main_queue(), ^{
		SXInstallBackButton(weakController, title);
	});
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		SXInstallBackButton(weakController, title);
	});
}
