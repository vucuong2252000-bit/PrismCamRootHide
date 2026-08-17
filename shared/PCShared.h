#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END

