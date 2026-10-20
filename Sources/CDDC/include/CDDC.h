// IOAVService: the I2C bridge to an external display's DDC/CI channel on Apple silicon.
// These symbols are exported by IOKit.framework but absent from its headers. m1ddc,
// MonitorControl and Didact declare them the same way (register D1, learnings 2026-10-19).
#ifndef CDDC_H
#define CDDC_H
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset,
                                   void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress,
                                    void *inputBuffer, uint32_t inputBufferSize);

#endif
