#import "SBPaths.h"
#import <dlfcn.h>
#import <sys/stat.h>

static NSString *SBJBRoot = nil;
static BOOL SBJBRootResolved = NO;
static BOOL SBIsRootHideFlag = NO;

typedef const char *(*SBJBRootFunc)(const char *);

static void SBResolveJBRoot(void) {
    if (SBJBRootResolved) return;
    SBJBRootResolved = YES;

    // 1) roothide: jbroot() là nguồn chân lý duy nhất
    SBJBRootFunc fn = NULL;
    void *handle = dlopen("libroothide.dylib", RTLD_LAZY);
    if (!handle) handle = dlopen("/usr/lib/libroothide.dylib", RTLD_LAZY);
    if (handle) fn = (SBJBRootFunc)dlsym(handle, "jbroot");
    if (fn) {
        const char *root = fn("/");
        if (root && root[0]) {
            SBJBRoot = [NSString stringWithUTF8String:root];
            SBIsRootHideFlag = YES;
        }
    }

    // 2) rootless cổ điển
    if (!SBJBRoot) {
        struct stat st;
        if (stat("/var/jb/usr/lib", &st) == 0) SBJBRoot = @"/var/jb";
    }

    // 3) rootful / môi trường khác: coi như gốc là "/"
    if (!SBJBRoot) SBJBRoot = @"/";
    if ([SBJBRoot hasSuffix:@"/"] && SBJBRoot.length > 1)
        SBJBRoot = [SBJBRoot substringToIndex:SBJBRoot.length - 1];
}

NSString *SBJailbreakRoot(void) {
    SBResolveJBRoot();
    return SBJBRoot;
}

BOOL SBIsRootHide(void) {
    SBResolveJBRoot();
    return SBIsRootHideFlag;
}

NSArray<NSString *> *SBPathCandidates(NSString *logicalPath) {
    SBResolveJBRoot();
    NSMutableArray *out = [NSMutableArray array];
    NSString *rel = [logicalPath hasPrefix:@"/"] ? [logicalPath substringFromIndex:1] : logicalPath;
    if (![SBJBRoot isEqualToString:@"/"]) {
        [out addObject:[SBJBRoot stringByAppendingPathComponent:rel]];
    }
    if (![SBJBRoot isEqualToString:@"/var/jb"]) {
        [out addObject:[@"/var/jb" stringByAppendingPathComponent:rel]];
    }
    [out addObject:logicalPath];
    return out;
}

NSString *SBPrimaryPreferencesPath(void) {
    // Preferences của tweak nằm trong domain riêng, do cfprefsd quản lý ở
    // /var/mobile/Library/Preferences trên CẢ rootless lẫn roothide.
    return @"/var/mobile/Library/Preferences/com.hthancder.siribridge.plist";
}
