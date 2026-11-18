#import "SXMediaFormat.h"
#include <stdint.h>

static void SXAppendLE(NSMutableData *data, uint32_t value, NSUInteger size) {
	uint8_t bytes[] = {value, value >> 8, value >> 16, value >> 24};
	[data appendBytes:bytes length:size];
}
NSData *SXPCM16WAV(NSData *pcm, uint32_t rate) {
	if (!pcm.length || pcm.length % 2 || pcm.length > UINT32_MAX - 36 || rate < 8000 || rate > 96000) return nil;
	NSMutableData *data = [NSMutableData dataWithCapacity:44 + pcm.length];
	[data appendBytes:"RIFF" length:4]; SXAppendLE(data, (uint32_t)pcm.length + 36, 4);
	[data appendBytes:"WAVEfmt " length:8]; SXAppendLE(data, 16, 4); SXAppendLE(data, 1, 2); SXAppendLE(data, 1, 2);
	SXAppendLE(data, rate, 4); SXAppendLE(data, rate * 2, 4); SXAppendLE(data, 2, 2); SXAppendLE(data, 16, 2);
	[data appendBytes:"data" length:4]; SXAppendLE(data, (uint32_t)pcm.length, 4); [data appendData:pcm];
	return data;
}
NSString *SXDetectedLanguage(NSString *text, NSString *fallback) {
	NSString *lower = [text.precomposedStringWithCanonicalMapping lowercaseString];
	static NSCharacterSet *marks;
	static NSSet *vi, *en;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		marks = [NSCharacterSet characterSetWithCharactersInString:@"ăâđêôơưàảãáạằẳẵắặầẩẫấậèẻẽéẹềểễếệìỉĩíịòỏõóọồổỗốộờởỡớợùủũúụừửữứựỳỷỹýỵ"];
		vi = [NSSet setWithArray:@[@"xin", @"chao", @"cam", @"on", @"ban", @"toi", @"khong", @"la", @"mot", @"nhung", @"cua", @"duoc", @"nay", @"viet"]];
		en = [NSSet setWithArray:@[@"a", @"the", @"an", @"hello", @"you", @"is", @"for", @"are", @"how", @"this", @"what", @"your", @"and", @"to", @"in"]];
	});
	if ([lower rangeOfCharacterFromSet:marks].location != NSNotFound) return @"vi";
	NSUInteger v = 0, e = 0;
	for (NSString *word in [lower componentsSeparatedByCharactersInSet:NSCharacterSet.letterCharacterSet.invertedSet]) {
		if ([vi containsObject:word]) v++;
		if ([en containsObject:word]) e++;
	}
	if (v >= 2 && v > e) return @"vi";
	if (e > v) return @"en";
	return fallback.length ? fallback : @"vi";
}
