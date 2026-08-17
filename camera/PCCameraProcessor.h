#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#ifdef __cplusplus
extern "C" {
#endif

void PCProcessCameraSample(CMSampleBufferRef sampleBuffer);
void PCReportHookState(NSString *message, BOOL installed);

#ifdef __cplusplus
}
#endif
