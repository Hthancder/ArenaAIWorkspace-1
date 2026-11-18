#import "SXLog.h"
#import "SXLogFile.h"
#import <os/log.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>
#include <string.h>
#include <stdio.h>

static volatile BOOL gVerbose = YES;
static os_log_t gOsLog = nil;
static NSString *gProc = @"unknown";

NSString *SXLogFilePath(void) {
	return @"/var/mobile/Library/Logs/SiriX.log";
}

void SXLogSetVerbose(BOOL verbose) {
	gVerbose = verbose;
}

static const char *SXLevelName(SXLogLevel level) {
	switch (level) {
		case SXLogLevelDebug: return "DEBUG";
		case SXLogLevelInfo:  return "INFO ";
		case SXLogLevelWarn:  return "WARN ";
		case SXLogLevelError: return "ERROR";
	}
	return "INFO ";
}

static os_log_type_t SXOsLogLevel(SXLogLevel level) {
	switch (level) {
		case SXLogLevelDebug: return OS_LOG_TYPE_DEBUG;
		case SXLogLevelInfo:  return OS_LOG_TYPE_INFO;
		case SXLogLevelWarn:  return OS_LOG_TYPE_DEFAULT;
		case SXLogLevelError: return OS_LOG_TYPE_ERROR;
	}
	return OS_LOG_TYPE_INFO;
}

static void SXPrepareLogFile(void) {
	NSString *dir = @"/var/mobile/Library/Logs";
	[[NSFileManager defaultManager] createDirectoryAtPath:dir
						  withIntermediateDirectories:YES
									   attributes:nil
												error:NULL];
	NSString *path = SXLogFilePath();
	struct stat st;
	if (stat(path.fileSystemRepresentation, &st) == 0 && st.st_size > 512 * 1024) {
		NSString *old = [path stringByAppendingString:@".old"];
		[[NSFileManager defaultManager] removeItemAtPath:old error:NULL];
		[[NSFileManager defaultManager] moveItemAtPath:path toPath:old error:NULL];
	}
}

void SXLogInit(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SXPrepareLogFile();
		gOsLog = os_log_create("com.sirix.tweak", "sirix");
		const char *pn = getprogname();
		gProc = pn ? [NSString stringWithUTF8String:pn] : @"unknown";
#ifndef SX_SCHEME
#define SX_SCHEME "unknown"
#endif
		SXLogWrite(SXLogLevelInfo, @"boot",
				   @"===== SiriX %@ khởi động — process=%@ scheme=%s build=%s =====",
				   SX_VERSION, gProc, SX_SCHEME, __DATE__ " " __TIME__);
	});
}

void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) {
	if (level == SXLogLevelDebug && !gVerbose) return;

	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	struct tm tmv;
	localtime_r(&ts.tv_sec, &tmv);
	char stamp[40];
	snprintf(stamp, sizeof(stamp), "%04d-%02d-%02d %02d:%02d:%02d.%03d",
			 tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
			 tmv.tm_hour, tmv.tm_min, tmv.tm_sec,
			 (int)(ts.tv_nsec / 1000000));

	NSString *line = [NSString stringWithFormat:@"%s [%s] [%s] [%s] %@\n",
					  stamp, SXLevelName(level),
					  category.UTF8String ?: "?",
					  gProc.UTF8String ?: "?",
					  msg];

	// Mở theo đường dẫn cho từng dòng: xóa/đổi tên/xoay vòng trong process khác
	// không khiến descriptor tiếp tục ghi vào inode đã bị tách khỏi SiriX.log.
	const char *bytes = line.UTF8String;
	if (bytes) (void)SXLogFileAppend(SXLogFilePath().fileSystemRepresentation, bytes, strlen(bytes));

	if (gOsLog) {
		os_log_with_type(gOsLog, SXOsLogLevel(level), "%{public}@", line);
	}
}

NSString *SXRedactKey(NSString *key) {
	NSUInteger len = key.length;
	if (len == 0) return @"(chưa đặt)";
	if (len <= 8) return [NSString stringWithFormat:@"(đã đặt, %lu ký tự)", (unsigned long)len];
	return [NSString stringWithFormat:@"%@…%@ (%lu ký tự)",
			[key substringToIndex:4], [key substringFromIndex:len - 4], (unsigned long)len];
}
