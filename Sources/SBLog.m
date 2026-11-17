#import "SBLog.h"
#import "SBPaths.h"

static NSString *gTag = nil;
static NSLock *gLock = nil;
static NSDateFormatter *gFmt = nil;

static NSLock *SBLogLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gLock = [NSLock new]; });
    return gLock;
}

void SBLogSetTag(NSString *tag) { gTag = [tag copy]; }

static NSString *SBLogPath(void) {
    // /var/mobile nằm ngoài jbroot ở cả rootless lẫn roothide → dùng trực tiếp,
    // nhưng vẫn thử danh sách ứng viên trước cho chắc.
    for (NSString *p in SBPathCandidates(@"/var/mobile/Library/Logs/SiriBridge.log")) {
        NSString *dir = [p stringByDeletingLastPathComponent];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dir]) return p;
    }
    NSArray *dirs = SBPathCandidates(@"/var/mobile/Library/Logs");
    return [[dirs lastObject] stringByAppendingPathComponent:@"SiriBridge.log"];
}

void SBLogMsg(NSString *tag, NSString *fmt, ...) {
    if (!fmt) return;
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSString *prefix = tag ?: (gTag ?: @"?");
    // NSLog luôn có, an toàn trong mọi process
    NSLog(@"[SiriBridge/%@] %@", prefix, msg);

    // Ghi file: cố tình KHÔNG @try/không throw; mọi lỗi bị bỏ qua.
    @autoreleasepool {
        if (!gFmt) {
            gFmt = [NSDateFormatter new];
            gFmt.dateFormat = @"HH:mm:ss.SSS";
        }
        NSString *path = SBLogPath();
        NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n",
                          [gFmt stringFromDate:[NSDate date]], prefix, msg];

        [SBLogLock() lock];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        if (attrs && [attrs fileSize] > 300 * 1024) {
            [fm removeItemAtPath:path error:NULL];   // log cũ quá lớn → xoá
        }
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            // để Filza/SSH đọc được
            [fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:path error:NULL];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            @try {
                [fh seekToEndOfFile];
                [fh writeData:data];
                [fh closeFile];
            } @catch (__unused NSException *e) {
                [fh closeFile];
            }
        }
        [SBLogLock() unlock];
    }
}
