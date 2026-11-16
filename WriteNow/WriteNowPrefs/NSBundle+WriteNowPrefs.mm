#import "NSBundle+WriteNowPrefs.h"

#import <libroot.h>

@implementation NSBundle (WriteNow)

+ (NSBundle *)wrti_supportBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSString *tweakBundlePath;
      tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"WriteNowPrefs" ofType:@"bundle"];
      NSString *aliasBundlePath;
      aliasBundlePath = JBROOT_PATH_NSSTRING(@"/Library/PreferenceBundles/WriteNowPrefs.bundle");
      bundle = [NSBundle bundleWithPath:tweakBundlePath ?: aliasBundlePath];
    });
    return bundle;
}

+ (NSString *)wrti_packageVersion {
    return @PACKAGE_VERSION;
}

@end