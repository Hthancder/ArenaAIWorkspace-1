#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary *SXConfigDefaults(void);
/// Validate one key from Settings/CFPreferences. No network or disk I/O.
FOUNDATION_EXPORT id _Nullable SXConfigValue(NSString *key, id _Nullable value);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *SXLegacyConfigKeys(void);
/// Map pre-profile settings without rebinding a credential to another endpoint.
FOUNDATION_EXPORT NSDictionary *SXUpgradeLegacyConfig(NSDictionary *settings);
/// Validated edits → {set, remove}. A changed custom URL clears an unprovided key.
FOUNDATION_EXPORT NSDictionary *SXConfigChangePlan(NSDictionary *current, NSDictionary *edits);
FOUNDATION_EXPORT NSData * _Nullable SXExportConfig(NSDictionary *values, BOOL includeSecrets, NSError **error);
/// Returns {set: dictionary, remove: array}; caller must preview/confirm before writing.
FOUNDATION_EXPORT NSDictionary * _Nullable SXImportConfig(NSData *data, NSDictionary *current, NSError **error);

/// Settings specifier rules and the small, secret-free state used to refresh a pane.
FOUNDATION_EXPORT BOOL SXConfigShowsRule(NSString * _Nullable rule, NSDictionary *settings);
FOUNDATION_EXPORT NSDictionary *SXConfigPresentationState(NSDictionary *settings);
FOUNDATION_EXPORT NSString *SXEffectiveTimeoutAction(NSDictionary *settings);
FOUNDATION_EXPORT BOOL SXConfigSupportsNativeUpdates(NSDictionary *settings);
NS_ASSUME_NONNULL_END
