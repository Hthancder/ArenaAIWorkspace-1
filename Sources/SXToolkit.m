#import "SXToolkit.h"
#import "SXLog.h"

NSString *const SXToolErrorDomain = @"com.sirix.tools";

static NSError *SXToolError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:SXToolErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey: message ?: @"Công cụ gặp lỗi."}];
}

NSString *SXToolCategoryTitle(SXToolCategory category) {
	switch (category) {
		case SXToolCategoryDevice: return @"Thiết bị";
		case SXToolCategoryClipboard: return @"Bảng nhớ tạm";
		case SXToolCategoryWeb: return @"Web";
		case SXToolCategorySystem: return @"Ứng dụng & phím tắt";
		case SXToolCategoryMemory: return @"Ghi nhớ";
		case SXToolCategoryMath: return @"Tính toán";
	}
	return @"Khác";
}

#pragma mark - SXTool

@interface SXTool ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *prompt;
@property (nonatomic) SXToolCategory category;
@property (nonatomic, copy) NSDictionary *parameters;
@property (nonatomic, copy) SXToolHandler handler;
@end

@implementation SXTool

+ (instancetype)toolWithName:(NSString *)name
					   title:(NSString *)title
					 summary:(NSString *)summary
					  prompt:(NSString *)prompt
					category:(SXToolCategory)category
				  parameters:(NSDictionary *)parameters
					 handler:(SXToolHandler)handler {
	SXTool *tool = [[self alloc] init];
	tool->_name = [name copy];
	tool->_title = [title copy];
	tool->_summary = [summary copy];
	tool->_prompt = [prompt copy];
	tool->_category = category;
	tool->_parameters = [parameters copy] ?: @{@"type": @"object", @"properties": @{}, @"required": @[]};
	tool->_handler = [handler copy];
	tool->_timeout = 8.0;
	return tool;
}

- (NSDictionary *)functionPayload {
	return @{
		@"type": @"function",
		@"function": @{
			@"name": self.name,
			@"description": self.prompt.length ? self.prompt : self.summary,
			@"parameters": self.parameters,
		},
	};
}

- (NSString *)parameterSignature {
	NSDictionary *properties = [self.parameters[@"properties"] isKindOfClass:[NSDictionary class]]
		? self.parameters[@"properties"] : @{};
	NSArray<NSString *> *required = [self.parameters[@"required"] isKindOfClass:[NSArray class]]
		? self.parameters[@"required"] : @[];
	if (!properties.count) return @"không tham số";

	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	for (NSString *key in properties) {
		BOOL isRequired = [required containsObject:key];
		// Tham số tuỳ chọn chỉ hiện tên để dòng prompt ngắn.
		[parts addObject:isRequired ? [key stringByAppendingString:@" (bắt buộc)"] : key];
	}
	[parts sortUsingSelector:@selector(compare:)];
	return [parts componentsJoinedByString:@", "];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<SXTool %@ (%@)>", self.name, SXToolCategoryTitle(self.category)];
}

@end

#pragma mark - Sổ đăng ký

static NSMutableArray<SXTool *> *SXToolRegistry(void) {
	static NSMutableArray<SXTool *> *tools;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ tools = [NSMutableArray array]; });
	return tools;
}

static NSLock *SXToolkitLock(void) {
	static NSLock *lock;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ lock = [[NSLock alloc] init]; });
	return lock;
}

/// name → kết quả trong lượt hiện tại (chống model gọi lặp cùng một tham số).
static NSMutableDictionary<NSString *, NSDictionary *> *SXToolCallCache(void) {
	static NSMutableDictionary *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
	return cache;
}

@implementation SXToolkit

+ (void)registerTool:(SXTool *)tool {
	if (![tool isKindOfClass:[SXTool class]] || !tool.name.length) return;
	NSLock *lock = SXToolkitLock();
	[lock lock];
	NSMutableArray *tools = SXToolRegistry();
	NSUInteger index = [tools indexOfObjectPassingTest:^BOOL(SXTool *other, NSUInteger idx, BOOL *stop) {
		(void)idx; (void)stop;
		return [other.name isEqualToString:tool.name];
	}];
	if (index == NSNotFound) [tools addObject:tool];
	else tools[index] = tool;
	[lock unlock];
}

+ (void)removeAllTools {
	NSLock *lock = SXToolkitLock();
	[lock lock];
	[SXToolRegistry() removeAllObjects];
	[SXToolCallCache() removeAllObjects];
	[lock unlock];
}

+ (NSArray<SXTool *> *)allTools {
	NSLock *lock = SXToolkitLock();
	[lock lock];
	NSArray *copy = [SXToolRegistry() copy];
	[lock unlock];
	return [copy sortedArrayUsingComparator:^NSComparisonResult(SXTool *a, SXTool *b) {
		if (a.category != b.category) return a.category < b.category ? NSOrderedAscending : NSOrderedDescending;
		return [a.name compare:b.name];
	}];
}

+ (SXTool *)toolNamed:(NSString *)name {
	if (!name.length) return nil;
	for (SXTool *tool in [self allTools]) {
		if ([tool.name isEqualToString:name]) return tool;
	}
	return nil;
}

+ (NSArray<SXTool *> *)toolsExcluding:(NSSet<NSString *> *)disabled {
	NSMutableArray<SXTool *> *result = [NSMutableArray array];
	for (SXTool *tool in [self allTools]) {
		if (disabled && [disabled containsObject:tool.name]) continue;
		[result addObject:tool];
	}
	return result;
}

+ (NSArray<NSDictionary *> *)definitionsExcluding:(NSSet<NSString *> *)disabled {
	NSMutableArray<NSDictionary *> *payloads = [NSMutableArray array];
	for (SXTool *tool in [self toolsExcluding:disabled]) {
		[payloads addObject:[tool functionPayload]];
	}
	return payloads;
}

+ (NSString *)promptBriefExcluding:(NSSet<NSString *> *)disabled {
	NSArray<SXTool *> *tools = [self toolsExcluding:disabled];
	if (!tools.count) return @"";

	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	[lines addObject:@"Bạn CÓ công cụ thật. Khi câu trả lời cần dữ liệu hoặc thao tác thực tế, hãy gọi công cụ "
					  @"thay vì đoán; không bao giờ bịa kết quả của công cụ."];
	[lines addObject:@"Danh sách công cụ:"];
	for (SXTool *tool in tools) {
		[lines addObject:[NSString stringWithFormat:@"- %@(%@): %@", tool.name,
						  [tool parameterSignature], tool.prompt]];
	}
	[lines addObject:@"Quy tắc: gọi tối thiểu lượt cần thiết; tham số phải đúng kiểu; nếu công cụ báo lỗi, "
					  @"đọc kỹ thông báo để sửa tham số hoặc đổi cách làm; sau khi có kết quả, trả lời người dùng "
					  @"bằng lời văn tự nhiên và nêu ngắn gọn điều vừa làm."];
	return [lines componentsJoinedByString:@"\n"];
}

+ (void)resetCallCache {
	NSLock *lock = SXToolkitLock();
	[lock lock];
	[SXToolCallCache() removeAllObjects];
	[lock unlock];
}

#pragma mark - Thực thi

/// Chuẩn hoá tham số theo schema: bỏ NSNull, ép kiểu từ chuỗi khi model gửi sai kiểu.
static NSDictionary *SXNormalizedArguments(SXTool *tool, NSDictionary *raw, NSError **error) {
	NSDictionary *properties = [tool.parameters[@"properties"] isKindOfClass:[NSDictionary class]]
		? tool.parameters[@"properties"] : @{};
	NSMutableDictionary *arguments = [NSMutableDictionary dictionary];

	for (NSString *key in properties) {
		id value = [raw isKindOfClass:[NSDictionary class]] ? raw[key] : nil;
		if (!value || value == [NSNull null]) continue;

		NSString *type = [properties[key] isKindOfClass:[NSDictionary class]] ? properties[key][@"type"] : nil;
		if ([type isEqualToString:@"string"] && ![value isKindOfClass:[NSString class]]) {
			value = [value description];
		} else if ([type isEqualToString:@"number"] && [value isKindOfClass:[NSString class]]) {
			NSScanner *scanner = [NSScanner scannerWithString:value];
			double number = 0;
			if ([scanner scanDouble:&number]) value = @(number);
		} else if ([type isEqualToString:@"integer"] && [value isKindOfClass:[NSString class]]) {
			value = @([value integerValue]);
		} else if ([type isEqualToString:@"boolean"] && [value isKindOfClass:[NSString class]]) {
			NSString *lower = [value lowercaseString];
			value = @([lower isEqualToString:@"true"] || [lower isEqualToString:@"1"] || [lower isEqualToString:@"yes"]);
		}
		if (value) arguments[key] = value;
	}

	// Giữ tham số ngoài schema (một số model gửi thêm khoá phụ) nhưng không cho NSNull.
	if ([raw isKindOfClass:[NSDictionary class]]) {
		for (NSString *key in raw) {
			if (arguments[key]) continue;
			id value = raw[key];
			if (value && value != [NSNull null]) arguments[key] = value;
		}
	}

	NSArray<NSString *> *required = [tool.parameters[@"required"] isKindOfClass:[NSArray class]]
		? tool.parameters[@"required"] : @[];
	NSMutableArray<NSString *> *missing = [NSMutableArray array];
	for (NSString *key in required) {
		id value = arguments[key];
		BOOL empty = !value
			|| ([value isKindOfClass:[NSString class]] && ![(NSString *)value length])
			|| ([value isKindOfClass:[NSNumber class]] && ![(NSNumber *)value boolValue] && [properties[key][@"type"] isEqualToString:@"boolean"]);
		if (empty) [missing addObject:key];
	}
	if (missing.count) {
		if (error) {
			*error = SXToolError(422, [NSString stringWithFormat:
				@"Thiếu tham số bắt buộc cho %@: %@. Gọi lại với đầy đủ tham số.",
				tool.name, [missing componentsJoinedByString:@", "]]);
		}
		return nil;
	}
	return arguments;
}

static NSString *SXToolCacheKey(NSString *name, NSDictionary *arguments) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:(arguments ?: @{})
												   options:NSJSONWritingSortedKeys
													 error:NULL];
	NSString *signature = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
	return [NSString stringWithFormat:@"%@\x01%@", name, signature];
}

/// Chạy handler trên hàng đợi riêng, có trần thời gian; exception → NSError.
static NSDictionary *SXRunHandler(SXTool *tool, NSDictionary *arguments, NSError **outError) {
	BOOL onMain = [NSThread isMainThread];
	dispatch_queue_t queue = tool.requiresMainThread
		? dispatch_get_main_queue()
		: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

	if (tool.requiresMainThread && onMain) {
		// Đã ở luồng chính: chạy trực tiếp, tránh tự khoá mình.
		NSDictionary *result = nil;
		NSError *error = nil;
		@try {
			result = tool.handler(arguments, &error);
		} @catch (NSException *exception) {
			error = SXToolError(500, [NSString stringWithFormat:@"Công cụ %@ gặp lỗi nội bộ (%@).",
									  tool.name, exception.name]);
		}
		if (error && outError) *outError = error;
		return result;
	}

	__block NSDictionary *result = nil;
	__block NSError *error = nil;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	dispatch_async(queue, ^{
		@try {
			result = tool.handler(arguments, &error);
		} @catch (NSException *exception) {
			error = SXToolError(500, [NSString stringWithFormat:@"Công cụ %@ gặp lỗi nội bộ (%@).",
									  tool.name, exception.name]);
		}
		dispatch_semaphore_signal(semaphore);
	});

	NSTimeInterval timeout = tool.timeout > 0 ? tool.timeout : 8.0;
	if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
		if (outError) {
			*outError = SXToolError(504, [NSString stringWithFormat:
				@"Công cụ %@ không trả lời trong %.0f giây. Thử cách khác hoặc trả lời ngắn hơn.",
				tool.name, timeout]);
		}
		SXLogWrn(@"tool", @"%@ quá %.0fs — bỏ qua kết quả", tool.name, timeout);
		return nil;
	}
	if (error && outError) *outError = error;
	return result;
}

+ (NSDictionary *)execute:(NSString *)name
				arguments:(NSDictionary *)arguments
				 excluded:(NSSet<NSString *> *)disabled
					error:(NSError **)outError {
	NSString *cleanName = [name isKindOfClass:[NSString class]]
		? [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
	if (!cleanName.length) {
		if (outError) *outError = SXToolError(400, @"Tên công cụ rỗng.");
		return nil;
	}

	SXTool *tool = [self toolNamed:cleanName];
	if (!tool) {
		NSMutableArray<NSString *> *names = [NSMutableArray array];
		for (SXTool *candidate in [self toolsExcluding:disabled]) [names addObject:candidate.name];
		if (outError) {
			*outError = SXToolError(404, [NSString stringWithFormat:
				@"Không có công cụ “%@”. Công cụ đang dùng được: %@.",
				cleanName, names.count ? [names componentsJoinedByString:@", "] : @"(không có)"]); 
		}
		return nil;
	}
	if (disabled && [disabled containsObject:tool.name]) {
		if (outError) {
			*outError = SXToolError(403, [NSString stringWithFormat:
				@"Công cụ “%@” đang bị tắt trong Cài đặt SiriX → Công cụ. Hãy trả lời mà không dùng nó.",
				tool.name]);
		}
		return nil;
	}

	NSError *argumentError = nil;
	NSDictionary *cleanArguments = SXNormalizedArguments(tool, arguments, &argumentError);
	if (!cleanArguments) {
		if (outError) *outError = argumentError;
		SXLogWrn(@"tool", @"%@ tham số không hợp lệ: %@", tool.name, argumentError.localizedDescription);
		return nil;
	}

	NSString *cacheKey = SXToolCacheKey(tool.name, cleanArguments);
	NSLock *lock = SXToolkitLock();
	[lock lock];
	NSDictionary *cached = SXToolCallCache()[cacheKey];
	[lock unlock];
	if (cached) {
		SXLogDbg(@"tool", @"%@ — dùng lại kết quả trong cùng lượt", tool.name);
		return cached;
	}

	CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
	NSError *handlerError = nil;
	NSDictionary *raw = SXRunHandler(tool, cleanArguments, &handlerError);
	NSInteger elapsedMs = (NSInteger)((CFAbsoluteTimeGetCurrent() - began) * 1000.0);

	if (handlerError) {
		SXLogWrn(@"tool", @"%@ lỗi sau %ld ms: %@", tool.name, (long)elapsedMs,
				 handlerError.localizedDescription);
		if (outError) *outError = handlerError;
		return nil;
	}

	// Chuẩn hoá kết quả về @{ @"result": NSString } — model chỉ cần văn bản.
	NSString *text = nil;
	if ([raw isKindOfClass:[NSDictionary class]]) {
		id value = raw[@"result"];
		if ([value isKindOfClass:[NSString class]]) text = value;
		else if (value) text = [value description];
	} else if ([raw isKindOfClass:[NSString class]]) {
		text = (NSString *)raw;
	}
	if (!text) text = @"Đã thực hiện xong.";

	static const NSUInteger kMaxResult = 4000;
	BOOL truncated = NO;
	if (text.length > kMaxResult) {
		text = [[text substringToIndex:kMaxResult] stringByAppendingString:@"\n…(đã cắt bớt)"];
		truncated = YES;
	}
	NSDictionary *result = @{@"result": text};

	SXLogDbg(@"tool", @"%@ → %ld ms, %lu ký tự%@", tool.name, (long)elapsedMs,
			 (unsigned long)text.length, truncated ? @" (cắt)" : @"");

	[lock lock];
	if (SXToolCallCache().count < 128) SXToolCallCache()[cacheKey] = result;
	[lock unlock];
	return result;
}

@end
