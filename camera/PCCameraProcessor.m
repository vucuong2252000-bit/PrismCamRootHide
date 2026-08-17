#import "PCCameraProcessor.h"
#import "../shared/PCShared.h"

#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>

static CGFloat PCClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(maximum, MAX(minimum, value));
}

@interface PCCameraProcessor : NSObject
@property(nonatomic, strong) CIContext *context;
@property(nonatomic, strong) CIImage *sourceImage;
@property(nonatomic, copy) NSDictionary *configuration;
@property(nonatomic, strong) NSDate *frameModificationDate;
@property(nonatomic) CFTimeInterval lastConfigurationRead;
@property(nonatomic) CFTimeInterval lastFrameRead;
@property(nonatomic) CFTimeInterval lastColorSample;
@property(nonatomic) CFTimeInterval lastStatusWrite;
@property(nonatomic) CGFloat sourceRed;
@property(nonatomic) CGFloat sourceGreen;
@property(nonatomic) CGFloat sourceBlue;
@property(nonatomic) CGFloat autoRed;
@property(nonatomic) CGFloat autoGreen;
@property(nonatomic) CGFloat autoBlue;
@end

@implementation PCCameraProcessor

+ (instancetype)sharedProcessor {
    static PCCameraProcessor *processor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        processor = [PCCameraProcessor new];
    });
    return processor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO,
                                                   kCIContextCacheIntermediates: @YES}];
        _autoRed = _autoGreen = _autoBlue = 1.0;
        _sourceRed = _sourceGreen = _sourceBlue = 1.0;
    }
    return self;
}

- (BOOL)isArmedAtTime:(CFTimeInterval)now {
    BOOL enabled = [self.configuration[@"enabled"] boolValue];
    double armedUntil = [self.configuration[@"armedUntil"] doubleValue];
    return enabled && armedUntil > NSDate.date.timeIntervalSince1970;
}

- (void)reloadStateIfNeeded:(CFTimeInterval)now {
    if (now - self.lastConfigurationRead >= 0.5 || !self.configuration) {
        self.configuration = PCLoadConfiguration();
        self.lastConfigurationRead = now;
    }
    if (![self isArmedAtTime:now]) {
        self.sourceImage = nil;
        return;
    }
    if (now - self.lastFrameRead < 0.08) return;
    self.lastFrameRead = now;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:PCFramePath() error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    if (!modified || [modified isEqualToDate:self.frameModificationDate]) return;
    NSData *data = [NSData dataWithContentsOfFile:PCFramePath() options:NSDataReadingMappedIfSafe error:nil];
    CIImage *image = data.length ? [CIImage imageWithData:data] : nil;
    if (image && !CGRectIsEmpty(image.extent)) {
        self.sourceImage = image;
        self.frameModificationDate = modified;
        CGFloat red = 1, green = 1, blue = 1;
        if ([self averageImage:image red:&red green:&green blue:&blue]) {
            self.sourceRed = MAX(red, 0.02);
            self.sourceGreen = MAX(green, 0.02);
            self.sourceBlue = MAX(blue, 0.02);
        }
    }
}

- (BOOL)averageImage:(CIImage *)image red:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue {
    CGRect extent = image.extent;
    if (CGRectIsInfinite(extent) || CGRectIsEmpty(extent)) return NO;
    CGFloat width = MAX(1, CGRectGetWidth(extent) * 0.35);
    CGFloat height = MAX(1, CGRectGetHeight(extent) * 0.35);
    CGRect center = CGRectMake(CGRectGetMidX(extent) - width / 2,
                               CGRectGetMidY(extent) - height / 2,
                               width,
                               height);
    CIFilter *average = [CIFilter filterWithName:@"CIAreaAverage"];
    [average setValue:image forKey:kCIInputImageKey];
    [average setValue:[CIVector vectorWithCGRect:center] forKey:kCIInputExtentKey];
    CIImage *output = average.outputImage;
    if (!output) return NO;
    uint8_t pixel[4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    [self.context render:output
                toBitmap:pixel
                rowBytes:4
                  bounds:CGRectMake(0, 0, 1, 1)
                  format:kCIFormatRGBA8
              colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);
    *red = pixel[0] / 255.0;
    *green = pixel[1] / 255.0;
    *blue = pixel[2] / 255.0;
    return YES;
}

- (CIImage *)image:(CIImage *)image aspectFillRect:(CGRect)target {
    CGRect extent = image.extent;
    CGFloat scale = MAX(CGRectGetWidth(target) / CGRectGetWidth(extent),
                        CGRectGetHeight(target) / CGRectGetHeight(extent));
    CIImage *scaled = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CGRect scaledExtent = scaled.extent;
    CGFloat dx = CGRectGetMidX(target) - CGRectGetMidX(scaledExtent);
    CGFloat dy = CGRectGetMidY(target) - CGRectGetMidY(scaledExtent);
    return [[scaled imageByApplyingTransform:CGAffineTransformMakeTranslation(dx, dy)] imageByCroppingToRect:target];
}

- (CIImage *)applyColorToImage:(CIImage *)image original:(CIImage *)original now:(CFTimeInterval)now {
    if ([self.configuration[@"colorSyncEnabled"] boolValue] && now - self.lastColorSample >= 0.35) {
        self.lastColorSample = now;
        CGFloat red = 1, green = 1, blue = 1;
        if ([self averageImage:original red:&red green:&green blue:&blue]) {
            CGFloat targetRed = PCClamp(red / self.sourceRed, 0.70, 1.40);
            CGFloat targetGreen = PCClamp(green / self.sourceGreen, 0.70, 1.40);
            CGFloat targetBlue = PCClamp(blue / self.sourceBlue, 0.70, 1.40);
            self.autoRed = self.autoRed * 0.82 + targetRed * 0.18;
            self.autoGreen = self.autoGreen * 0.82 + targetGreen * 0.18;
            self.autoBlue = self.autoBlue * 0.82 + targetBlue * 0.18;
        }
    }
    CGFloat red = PCClamp([self.configuration[@"redGain"] doubleValue] * self.autoRed, 0.55, 1.60);
    CGFloat green = PCClamp([self.configuration[@"greenGain"] doubleValue] * self.autoGreen, 0.55, 1.60);
    CGFloat blue = PCClamp([self.configuration[@"blueGain"] doubleValue] * self.autoBlue, 0.55, 1.60);
    CIFilter *matrix = [CIFilter filterWithName:@"CIColorMatrix"];
    [matrix setValue:image forKey:kCIInputImageKey];
    [matrix setValue:[CIVector vectorWithX:red Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [matrix setValue:[CIVector vectorWithX:0 Y:green Z:0 W:0] forKey:@"inputGVector"];
    [matrix setValue:[CIVector vectorWithX:0 Y:0 Z:blue W:0] forKey:@"inputBVector"];
    [matrix setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
    return matrix.outputImage ?: image;
}

- (CIImage *)addVisibleMarkerToImage:(CIImage *)image target:(CGRect)target {
    CGFloat markerHeight = MAX(10, CGRectGetHeight(target) * 0.025);
    CGRect markerRect = CGRectMake(CGRectGetMinX(target), CGRectGetMinY(target), CGRectGetWidth(target), markerHeight);
    CIImage *marker = [[CIImage imageWithColor:[CIColor colorWithRed:0.95 green:0.05 blue:0.55 alpha:0.82]]
                       imageByCroppingToRect:markerRect];
    return [marker imageByCompositingOverImage:image];
}

- (void)processSample:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) return;
    @synchronized (self) {
        CFTimeInterval now = CFAbsoluteTimeGetCurrent();
        [self reloadStateIfNeeded:now];
        if (![self isArmedAtTime:now] || !self.sourceImage) return;
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!pixelBuffer) return;
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        if (!width || !height) return;

        CGRect target = CGRectMake(0, 0, width, height);
        CIImage *original = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        CIImage *output = [self image:self.sourceImage aspectFillRect:target];
        output = [self applyColorToImage:output original:original now:now];
        output = [self addVisibleMarkerToImage:output target:target];
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        [self.context render:output toCVPixelBuffer:pixelBuffer bounds:target colorSpace:colorSpace];
        CGColorSpaceRelease(colorSpace);

        if (now - self.lastStatusWrite >= 1.0) {
            self.lastStatusWrite = now;
            [@{@"message": @"Đang thay khung hình; marker an toàn đang bật",
               @"active": @YES,
               @"width": @(width),
               @"height": @(height),
               @"updatedAt": @(NSDate.date.timeIntervalSince1970)} writeToFile:PCCameraStatusPath() atomically:YES];
        }
    }
}

@end


void PCProcessCameraSample(CMSampleBufferRef sampleBuffer) {
    [[PCCameraProcessor sharedProcessor] processSample:sampleBuffer];
}

void PCReportHookState(NSString *message, BOOL installed) {
    PCEnsureSharedDirectory(nil);
    [@{@"message": message ?: @"Không rõ trạng thái hook",
       @"hookInstalled": @(installed),
       @"updatedAt": @(NSDate.date.timeIntervalSince1970)} writeToFile:PCCameraStatusPath() atomically:YES];
}

