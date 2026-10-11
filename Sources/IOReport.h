#ifndef WATTS_IOREPORT_H
#define WATTS_IOREPORT_H
#include <CoreFoundation/CoreFoundation.h>
typedef struct __IOReportSubscription *WattsReportSubscription;
WattsReportSubscription IOReportCreateSubscription(void *, CFDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
CF_IMPLICIT_BRIDGING_ENABLED
CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
CFDictionaryRef IOReportCreateSamples(WattsReportSubscription, CFMutableDictionaryRef, CFTypeRef);
CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef);
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef, int32_t);
CF_IMPLICIT_BRIDGING_DISABLED
#endif
