#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT NSString *const PCConfigChangedNotification;
FOUNDATION_EXPORT NSString *const PCDefaultSourceMode;

NSString *PCSharedDirectory(void);
NSString *PCConfigPath(void);
NSString *PCFramePath(void);
NSString *PCDaemonStatusPath(void);
NSString *PCCameraStatusPath(void);

BOOL PCEnsureSharedDirectory(NSError **error);
NSDictionary *PCDefaultConfiguration(void);
NSMutableDictionary *PCLoadConfiguration(void);
BOOL PCSaveConfiguration(NSDictionary *configuration, NSError **error);
void PCPostConfigChanged(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
