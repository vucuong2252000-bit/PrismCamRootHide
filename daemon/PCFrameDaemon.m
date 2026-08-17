#import "PCFrameDaemon.h"
#import "../shared/PCShared.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static const NSUInteger PCMaximumJPEGSize = 8 * 1024 * 1024;

@interface PCFrameDaemon ()
@property(nonatomic, strong) dispatch_queue_t stateQueue;
@property(nonatomic, strong) dispatch_queue_t workerQueue;
@property(nonatomic, strong) dispatch_source_t acceptSource;
@property(nonatomic) int listenFD;
@property(atomic) NSUInteger generation;
@property(nonatomic, copy) NSDictionary *configuration;
@property(nonatomic, copy) NSString *activeMode;
@property(nonatomic, copy) NSString *activeAssetPath;
@property(nonatomic, strong) CIContext *ciContext;
@property(nonatomic, strong) NSTimer *configurationTimer;
@end

@implementation PCFrameDaemon

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenFD = -1;
        _stateQueue = dispatch_queue_create("com.local.prismcam.state", DISPATCH_QUEUE_SERIAL);
        _workerQueue = dispatch_queue_create("com.local.prismcam.worker", DISPATCH_QUEUE_CONCURRENT);
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    }
    return self;
}

- (void)start {
    PCEnsureSharedDirectory(nil);
    [self writeStatus:@"Daemon đã khởi động" extra:@{}];
    [self reloadConfiguration];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.configurationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                   target:self
                                                                 selector:@selector(reloadConfiguration)
                                                                 userInfo:nil
                                                                  repeats:YES];
    });
}

- (void)reloadConfiguration {
    NSDictionary *next = PCLoadConfiguration();
    BOOL enabled = [next[@"enabled"] boolValue] &&
                   [next[@"armedUntil"] doubleValue] > NSDate.date.timeIntervalSince1970;
    NSString *mode = enabled ? next[@"sourceMode"] : @"disabled";
    NSString *asset = next[@"assetPath"] ?: @"";
    BOOL changed = ![mode isEqualToString:self.activeMode] || ![asset isEqualToString:self.activeAssetPath];
    self.configuration = next;
    if (!changed) return;

    self.generation += 1;
    NSUInteger generation = self.generation;
    self.activeMode = mode;
    self.activeAssetPath = asset;
    [self stopOBSListener];

    if ([mode isEqualToString:@"image"]) {
        [self publishImageAsset:asset generation:generation];
    } else if ([mode isEqualToString:@"video"]) {
        [self startVideoAsset:asset generation:generation];
    } else if ([mode isEqualToString:@"obs"]) {
        [self startOBSListener];
    } else {
        [self writeStatus:@"Camera ảo đang tắt" extra:@{@"mode": @"disabled"}];
    }
}

- (void)publishImageAsset:(NSString *)asset generation:(NSUInteger)generation {
    dispatch_async(self.workerQueue, ^{
        NSData *data = [NSData dataWithContentsOfFile:asset options:NSDataReadingMappedIfSafe error:nil];
        if (generation != self.generation || !data.length) {
            [self writeStatus:@"Không đọc được ảnh đã chọn" extra:@{@"mode": @"image"}];
            return;
        }
        [self publishFrame:data mode:@"image"];
    });
}

- (void)startVideoAsset:(NSString *)asset generation:(NSUInteger)generation {
    dispatch_async(self.workerQueue, ^{
        if (![[NSFileManager defaultManager] fileExistsAtPath:asset]) {
            [self writeStatus:@"Không tìm thấy video đã chọn" extra:@{@"mode": @"video"}];
            return;
        }
        while (generation == self.generation) {
            @autoreleasepool {
                NSURL *url = [NSURL fileURLWithPath:asset];
                AVURLAsset *video = [AVURLAsset URLAssetWithURL:url options:nil];
                AVAssetTrack *track = [[video tracksWithMediaType:AVMediaTypeVideo] firstObject];
                if (!track) {
                    [self writeStatus:@"Video không có track hình" extra:@{@"mode": @"video"}];
                    return;
                }
                NSError *readerError = nil;
                AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:video error:&readerError];
                AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc]
                    initWithTrack:track
                    outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
                output.alwaysCopiesSampleData = NO;
                if (![reader canAddOutput:output]) {
                    [self writeStatus:@"Không thể tạo bộ đọc video" extra:@{@"mode": @"video"}];
                    return;
                }
                [reader addOutput:output];
                [reader startReading];
                CFTimeInterval wallStart = CFAbsoluteTimeGetCurrent();
                CMTime firstPTS = kCMTimeInvalid;
                while (generation == self.generation) {
                    CMSampleBufferRef sample = [output copyNextSampleBuffer];
                    if (!sample) break;
                    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
                    if (!CMTIME_IS_VALID(firstPTS)) firstPTS = pts;
                    double due = CMTimeGetSeconds(CMTimeSubtract(pts, firstPTS));
                    double wait = due - (CFAbsoluteTimeGetCurrent() - wallStart);
                    if (wait > 0 && wait < 1.0) usleep((useconds_t)(wait * 1000000));
                    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sample);
                    NSData *jpeg = [self JPEGDataFromPixelBuffer:pixelBuffer];
                    if (jpeg.length && generation == self.generation) {
                        [self publishFrame:jpeg mode:@"video"];
                    }
                    CFRelease(sample);
                }
                [reader cancelReading];
            }
        }
    });
}

- (NSData *)JPEGDataFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return nil;
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CGImageRef cgImage = [self.ciContext createCGImage:image fromRect:image.extent];
    if (!cgImage) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
                                                                          CFSTR("public.jpeg"),
                                                                          1,
                                                                          NULL);
    if (destination) {
        CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @0.82});
        CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(cgImage);
    return data;
}

- (void)startOBSListener {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        [self writeStatus:@"Không tạo được socket OBS" extra:@{@"mode": @"obs"}];
        return;
    }
    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    fcntl(fd, F_SETFL, O_NONBLOCK);
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons([self.configuration[@"listenPort"] intValue]);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 2) != 0) {
        close(fd);
        [self writeStatus:@"Không mở được cổng OBS" extra:@{@"mode": @"obs"}];
        return;
    }
    self.listenFD = fd;
    self.acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.stateQueue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.acceptSource, ^{
        [weakSelf acceptPendingClients];
    });
    dispatch_source_set_cancel_handler(self.acceptSource, ^{
        close(fd);
    });
    dispatch_resume(self.acceptSource);
    [self writeStatus:[NSString stringWithFormat:@"Chờ OBS ở cổng %@", self.configuration[@"listenPort"]]
                 extra:@{@"mode": @"obs", @"listening": @YES}];
}

- (void)stopOBSListener {
    dispatch_source_t source = self.acceptSource;
    self.acceptSource = nil;
    self.listenFD = -1;
    if (source) dispatch_source_cancel(source);
}

- (void)acceptPendingClients {
    while (self.listenFD >= 0) {
        int client = accept(self.listenFD, NULL, NULL);
        if (client < 0) break;
        NSString *token = self.configuration[@"pairingToken"] ?: @"";
        NSUInteger generation = self.generation;
        dispatch_async(self.workerQueue, ^{
            [self processOBSClient:client token:token generation:generation];
        });
    }
}

- (BOOL)readPairingHeader:(int)client token:(NSString *)token {
    struct timeval timeout = {.tv_sec = 5, .tv_usec = 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    NSMutableData *line = [NSMutableData data];
    while (line.length < 256) {
        uint8_t byte = 0;
        ssize_t count = recv(client, &byte, 1, 0);
        if (count != 1) return NO;
        if (byte == '\n') break;
        [line appendBytes:&byte length:1];
    }
    NSString *header = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
    NSString *expected = [NSString stringWithFormat:@"PRISMCAM/1 %@", token];
    return token.length >= 12 && [header isEqualToString:expected];
}

- (void)processOBSClient:(int)client token:(NSString *)token generation:(NSUInteger)generation {
    @autoreleasepool {
        if (![self readPairingHeader:client token:token]) {
            close(client);
            [self writeStatus:@"Từ chối kết nối OBS: sai mã ghép nối" extra:@{@"mode": @"obs"}];
            return;
        }
        [self writeStatus:@"OBS đã kết nối" extra:@{@"mode": @"obs", @"connected": @YES}];
        NSMutableData *jpeg = [NSMutableData data];
        BOOL collecting = NO;
        uint8_t previous = 0;
        uint8_t buffer[32768];
        while (generation == self.generation) {
            ssize_t count = recv(client, buffer, sizeof(buffer), 0);
            if (count <= 0) break;
            for (ssize_t index = 0; index < count; index++) {
                uint8_t byte = buffer[index];
                if (!collecting) {
                    if (previous == 0xFF && byte == 0xD8) {
                        uint8_t start[] = {0xFF, 0xD8};
                        [jpeg setLength:0];
                        [jpeg appendBytes:start length:2];
                        collecting = YES;
                    }
                } else {
                    [jpeg appendBytes:&byte length:1];
                    if (previous == 0xFF && byte == 0xD9) {
                        [self publishFrame:[jpeg copy] mode:@"obs"];
                        collecting = NO;
                        [jpeg setLength:0];
                    } else if (jpeg.length > PCMaximumJPEGSize) {
                        collecting = NO;
                        [jpeg setLength:0];
                    }
                }
                previous = byte;
            }
        }
        close(client);
        if (generation == self.generation) {
            [self writeStatus:@"OBS đã ngắt kết nối" extra:@{@"mode": @"obs", @"connected": @NO}];
        }
    }
}

- (void)publishFrame:(NSData *)frame mode:(NSString *)mode {
    if (!frame.length) return;
    [frame writeToFile:PCFramePath() options:NSDataWritingAtomic error:nil];
    [self writeStatus:[NSString stringWithFormat:@"Đang phát nguồn %@", mode]
                 extra:@{@"mode": mode,
                         @"lastFrameAt": @(NSDate.date.timeIntervalSince1970),
                         @"frameBytes": @(frame.length)}];
}

- (void)writeStatus:(NSString *)message extra:(NSDictionary *)extra {
    NSMutableDictionary *status = [@{@"message": message,
                                     @"updatedAt": @(NSDate.date.timeIntervalSince1970)} mutableCopy];
    [status addEntriesFromDictionary:extra];
    [status writeToFile:PCDaemonStatusPath() atomically:YES];
}

@end
