#import <Foundation/Foundation.h>
#import "SXUpdate.h"
#import "SXLog.h"
#include <assert.h>

// Không cần mạng: chỉ kiểm tra phần so sánh phiên bản và tách tag CI.
// SXLog.m thật được liên kết nên không khai báo bản thay thế ở đây.

int main(void) {
	@autoreleasepool {
		assert([SXUpdate isVersion:@"1.2.0" newerThan:@"1.1.9"]);
		assert([SXUpdate isVersion:@"1.1.10" newerThan:@"1.1.9"]);
		assert(![SXUpdate isVersion:@"1.1.9" newerThan:@"1.1.9"]);
		assert(![SXUpdate isVersion:@"1.1.8" newerThan:@"1.1.9"]);
		assert([SXUpdate isVersion:@"v2.0" newerThan:@"1.9.9"]);
		assert([SXUpdate isVersion:@"1.2.0-build.140" newerThan:@"1.2.0"]);
		// `-build.N` là hậu tố build, không phải bản mới hơn cùng số phiên bản.
		assert(![SXUpdate isVersion:@"1.2.0-build.140" newerThan:@"1.2.0"]);
		assert([SXUpdate isVersion:@"1.2.0-build.140" newerThan:@"1.1.9"]);
		assert(![SXUpdate isVersion:@"" newerThan:@"1.1.9"]);
		assert(![SXUpdate isVersion:@"rác" newerThan:@"1.1.9"]);
		assert([[SXUpdate repository] containsString:@"/"]);
		puts("update regression tests: OK");
	}
	return 0;
}
