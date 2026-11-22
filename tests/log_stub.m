// Chỉ dùng cho các test macOS của những lớp có gọi SXLog* nhưng không kéo theo
// SXLog.m (SXLog.m cần tệp log thật của thiết bị). Ghi ra stderr để khi test
// hỏng vẫn thấy được dòng log ngay trước lỗi.
#import <Foundation/Foundation.h>
#import "SXLog.h"
#include <stdio.h>

void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	fprintf(stderr, "[stub] %s: %s\n", category.UTF8String ?: "?", message.UTF8String);
}

NSString *SXRedactLogLine(NSString *line) { return line; }
NSString *SXRedactKey(NSString *key) { return key ?: @""; }
NSString *SXLogFilePath(void) { return @"/dev/null"; }
