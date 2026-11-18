#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary *SXConfigDefaults(void);
/// Validate one key from Settings/CFPreferences. No network or disk I/O.
FOUNDATION_EXPORT id _Nullable SXConfigValue(NSString *key, id value);
FOUNDATION_EXPORT NSData * _Nullable SXExportConfig(NSDictionary *values, BOOL includeSecrets, NSError **error);
/// Returns {set: dictionary, remove: array}; caller must preview/confirm before writing.
FOUNDATION_EXPORT NSDictionary * _Nullable SXImportConfig(NSData *data, NSDictionary *current, NSError **error);
NS_ASSUME_NONNULL_END
