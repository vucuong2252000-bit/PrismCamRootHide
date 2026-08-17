#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "PCCameraProcessor.h"

static void (*PCOriginalEmitSampleBuffer)(id, SEL, CMSampleBufferRef);
static void PCReplacementEmitSampleBuffer(id self, SEL selector, CMSampleBufferRef sampleBuffer) {
    PCProcessCameraSample(sampleBuffer);
    PCOriginalEmitSampleBuffer(self, selector, sampleBuffer);
}

static void (*PCOriginalRenderSampleBuffer)(id, SEL, CMSampleBufferRef, id);
static void PCReplacementRenderSampleBuffer(id self, SEL selector, CMSampleBufferRef sampleBuffer, id input) {
    PCProcessCameraSample(sampleBuffer);
    PCOriginalRenderSampleBuffer(self, selector, sampleBuffer, input);
}

static BOOL PCHookVoidMethod(Class cls, SEL selector, IMP replacement, IMP *original, unsigned expectedArguments) {
    if (!cls) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != expectedArguments) return NO;
    char returnType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != 'v') return NO;
    MSHookMessageEx(cls, selector, replacement, original);
    return *original != NULL;
}

static void PCInstallCameraHook(void) {
    if (PCHookVoidMethod(objc_getClass("BWNodeOutput"),
                         sel_registerName("emitSampleBuffer:"),
                         (IMP)PCReplacementEmitSampleBuffer,
                         (IMP *)&PCOriginalEmitSampleBuffer,
                         3)) {
        PCReportHookState(@"Hook BWNodeOutput đã nạp; chờ camera", YES);
        return;
    }

    NSArray<NSString *> *fallbackClasses = @[@"BWImageQueueSinkNode", @"BWRemoteQueueSinkNode"];
    for (NSString *name in fallbackClasses) {
        if (PCHookVoidMethod(objc_getClass(name.UTF8String),
                             sel_registerName("renderSampleBuffer:forInput:"),
                             (IMP)PCReplacementRenderSampleBuffer,
                             (IMP *)&PCOriginalRenderSampleBuffer,
                             4)) {
            PCReportHookState([NSString stringWithFormat:@"Hook %@ đã nạp; chờ camera", name], YES);
            return;
        }
    }
    PCReportHookState(@"Không tìm thấy điểm hook tương thích trên build iOS này", NO);
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PCInstallCameraHook();
        });
    }
}

