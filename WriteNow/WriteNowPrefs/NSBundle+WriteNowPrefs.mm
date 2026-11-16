#import "NSBundle+WriteNowPrefs.h"

#import <libroot.h>

@implementation NSBundle (WriteNow)

+ (NSBundle *)wrti_supportBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      Class rootClass = NSClassFromString(@"WriteNowRootListController");
      if (rootClass) {
          bundle = [NSBundle bundleForClass:rootClass];
      }
      if (!bundle) {
          NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"WriteNowPrefs" ofType:@"bundle"];
          if (tweakBundlePath) {
              bundle = [NSBundle bundleWithPath:tweakBundlePath];
          }
      }
      if (!bundle) {
          NSString *aliasBundlePath = JBROOT_PATH_NSSTRING(@"/Library/PreferenceBundles/WriteNowPrefs.bundle");
          if (aliasBundlePath) {
              bundle = [NSBundle bundleWithPath:aliasBundlePath];
          }
      }
      if (!bundle) {
          bundle = [NSBundle mainBundle];
      }
    });
    return bundle;
}

+ (NSString *)wrti_packageVersion {
    return @PACKAGE_VERSION;
}

@end
