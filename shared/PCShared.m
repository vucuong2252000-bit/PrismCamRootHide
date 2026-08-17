#import "PCShared.h"

#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#define jbroot(path) (path)
#endif

#include <sys/stat.h>

NSString *const PCConfigChangedNotification = @"com.local.prismcam.config-changed";
NSString *const PCDefaultSourceMode = @"image";

NSString *PCSharedDirectory(void) {
    return jbroot(@"/var/mobile/Library/PrismCam");
}

NSString *PCConfigPath(void) {
    return [PCSharedDirectory() stringByAppendingPathComponent:@"Config.plist"];
}

NSString *PCFramePath(void) {
    return [PCSharedDirectory() stringByAppendingPathComponent:@"CurrentFrame.img"];
}

NSString *PCDaemonStatusPath(void) {
    return [PCSharedDirectory() stringByAppendingPathComponent:@"DaemonStatus.plist"];
}

NSString *PCCameraStatusPath(void) {
    return [PCSharedDirectory() stringByAppendingPathComponent:@"CameraStatus.plist"];
}

BOOL PCEnsureSharedDirectory(NSError **error) {
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:PCSharedDirectory()
                                              withIntermediateDirectories:YES
                                                               attributes:@{NSFilePosixPermissions: @0750}
                                                                    error:error];
    if (created) {
        chmod(PCSharedDirectory().fileSystemRepresentation, 0750);
    }
    return created;
}

NSDictionary *PCDefaultConfiguration(void) {
    return @{
        @"enabled": @NO,
        @"armedUntil": @0,
        @"sourceMode": PCDefaultSourceMode,
        @"assetPath": @"",
        @"colorSyncEnabled": @YES,
        @"redGain": @1.0,
        @"greenGain": @1.0,
        @"blueGain": @1.0,
        @"pairingToken": @"",
        @"listenPort": @5600,
        @"maximumFPS": @15,
    };
}

NSMutableDictionary *PCLoadConfiguration(void) {
    NSMutableDictionary *merged = [PCDefaultConfiguration() mutableCopy];
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:PCConfigPath()];
    if ([stored isKindOfClass:NSDictionary.class]) {
        [merged addEntriesFromDictionary:stored];
    }
    return merged;
}

BOOL PCSaveConfiguration(NSDictionary *configuration, NSError **error) {
    if (!PCEnsureSharedDirectory(error)) {
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:configuration
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:error];
    if (!data) {
        return NO;
    }
    BOOL saved = [data writeToFile:PCConfigPath() options:NSDataWritingAtomic error:error];
    if (saved) {
        chmod(PCConfigPath().fileSystemRepresentation, 0640);
        PCPostConfigChanged();
    }
    return saved;
}

void PCPostConfigChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PCConfigChangedNotification,
                                         NULL,
                                         NULL,
                                         true);
}

