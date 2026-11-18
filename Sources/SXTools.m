#import "SXTools.h"
#import "SXToolCatalog.h"
#import "SXPrefs.h"
#import "SXLog.h"

@implementation SXTools

+ (void)loadCatalogIfNeeded {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SXInstallBuiltinTools();
	});
}

+ (NSSet<NSString *> *)disabledTools {
	SXPrefs *prefs = [SXPrefs shared];
	NSSet *disabled = prefs.disabledTools;
	return [disabled isKindOfClass:[NSSet class]] ? disabled : [NSSet set];
}

+ (NSArray<SXTool *> *)catalog {
	[self loadCatalogIfNeeded];
	return [SXToolkit allTools];
}

+ (NSArray<NSDictionary *> *)definitions {
	[self loadCatalogIfNeeded];
	// Dạng trung lập {name, description, parameters}: SXLLM tự bọc thành
	// `tools[].function` cho OpenAI và `functionDeclarations` cho Gemini.
	NSMutableArray<NSDictionary *> *defs = [NSMutableArray array];
	for (SXTool *tool in [SXToolkit toolsExcluding:[self disabledTools]]) {
		[defs addObject:@{
			@"name": tool.name,
			@"description": tool.prompt.length ? tool.prompt : tool.summary,
			@"parameters": tool.parameters,
		}];
	}
	return defs;
}

+ (NSDictionary *)execute:(NSString *)name
				arguments:(NSDictionary *)arguments
					error:(NSError **)error {
	[self loadCatalogIfNeeded];
	NSDictionary *result = [SXToolkit execute:name
								   arguments:arguments
									excluded:[self disabledTools]
									   error:error];
	return result;
}

+ (NSString *)promptBrief {
	[self loadCatalogIfNeeded];
	return [SXToolkit promptBriefExcluding:[self disabledTools]];
}

+ (void)beginTurn {
	[SXToolkit resetCallCache];
}

@end
