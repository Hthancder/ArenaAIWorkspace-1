#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SXProvider) {
	SXProviderOpenAI = 0,
	SXProviderGemini,
	SXProviderGroq,
	SXProviderCustom,
};

FOUNDATION_EXPORT NSArray<NSString *> *SXChatProviderIDs(void);
FOUNDATION_EXPORT SXProvider SXProviderFromID(NSString * _Nullable identifier);
FOUNDATION_EXPORT NSString *SXProviderID(SXProvider provider);
FOUNDATION_EXPORT NSString *SXProviderName(SXProvider provider);
FOUNDATION_EXPORT NSString *SXChatKey(SXProvider provider, NSString *suffix); // Key / Model / FallbackModel
FOUNDATION_EXPORT NSString *SXChatDefaultModel(SXProvider provider);
FOUNDATION_EXPORT NSString *SXChatBase(NSDictionary *settings, SXProvider provider);
FOUNDATION_EXPORT NSString *SXChatModel(NSDictionary *settings, SXProvider provider);
FOUNDATION_EXPORT NSString *SXChatFallback(NSDictionary *settings, SXProvider provider);
FOUNDATION_EXPORT NSString * _Nullable SXChatIssue(NSDictionary *settings, SXProvider provider);

// Media profiles share presentation and request routing. Fields map key/model/voice
// to their persistent setting names; unavailable fields are not in the profile.
FOUNDATION_EXPORT NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *SXMediaProfiles(NSString *kind);
FOUNDATION_EXPORT NSString *SXSTTEffectiveSource(NSDictionary *settings);
FOUNDATION_EXPORT BOOL SXSTTUsesFixedEnglishModel(NSDictionary *settings);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *SXSTTFields(NSDictionary *settings);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *SXSTTConfiguration(NSDictionary *settings);
FOUNDATION_EXPORT NSString *SXTTSEffectiveSource(NSDictionary *settings);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *SXTTSConfiguration(NSDictionary *settings);
FOUNDATION_EXPORT BOOL SXTTSModeAllows(NSString *mode, BOOL answer);

NS_ASSUME_NONNULL_END
