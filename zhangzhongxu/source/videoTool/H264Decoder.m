//
//  H264Decoder.m
//  VTDemo
//
//  Created by lileilei on 15/7/25.
//  Copyright (c) 2015年 lileilei. All rights reserved.
//

#import "H264Decoder.h"
static  long long frameCount = 0;
@implementation H264Decoder

-(void) decodeFrame:(uint8_t *)frame
           withSize:(uint32_t)frameSize
      withExtraData:(uint8_t *)extraData
  withExtraDataSize:(uint32_t)extraDataSize
{
    
    NSData *h264Data = [NSData dataWithBytes:frame length:frameSize];
   // NSLog(@"h264Data =%@",h264Data);
    
    
    OSStatus status;
    int startCodeSPSIndex = 0;
    int startCodePPSIndex = 0;
    int spsLength = 0;
    int ppsLength = 0;
    NSData *spsData = nil;
    NSData *ppsData = nil;
    int nalu_type = 0;
    
    NSData *extra = [NSData dataWithBytes:extraData length:extraDataSize];
    NSLog(@"extra =%@",extra);
    if (_formatDesc == NULL) {
        for (int i = 0; i < extraDataSize; i++) {
            if (i >= 3) {
                if (extraData[i] == 0x01 && extraData[i-1] == 0x00 && extraData[i-2] == 0x00 && extraData[i-3] == 0x00) {
                    if (startCodeSPSIndex == 0) {
                        startCodeSPSIndex = i;
                    }
                    if (i > startCodeSPSIndex) {
                        startCodePPSIndex = i;
                    }
                }
            }
        }
        
        spsLength = startCodePPSIndex - startCodeSPSIndex - 4;
        ppsLength = extraDataSize - (startCodePPSIndex + 1);
        nalu_type = ((uint8_t) extraData[startCodeSPSIndex + 1] & 0x1F);
        if (nalu_type == 7) {
            spsData = [NSData dataWithBytes:&(extraData[startCodeSPSIndex + 1]) length: spsLength];
        }
        
        nalu_type = ((uint8_t) extraData[startCodePPSIndex + 1] & 0x1F);
        if (nalu_type == 8) {
            ppsData = [NSData dataWithBytes:&(extraData[startCodePPSIndex + 1]) length: ppsLength];
        }
        
        
        const uint8_t* const parameterSetPointers[2] = { (const uint8_t*)[spsData bytes], (const uint8_t*)[ppsData bytes] };
        const size_t parameterSetSizes[2] = { [spsData length], [ppsData length] };
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &_formatDesc);
    }
    if((status == noErr) && (_decompressionSession == NULL))
    {
        [self createDecompSession];
    }
    
    int startCodeIndex = 0;

    int fouthStartCodeIndex = 0;
    
    long blockLength = 0;
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    for (int i = 0; i < startCodeIndex + frameSize; i++)
    {
        if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01 )
        {
            nalu_type = (frame[i + 4] & 0x1F);
            if (nalu_type == 5)
            {
                fouthStartCodeIndex = i;
                blockLength = frameSize - fouthStartCodeIndex;
                data = malloc(blockLength);
                data = memcpy(data, &frame[fouthStartCodeIndex], blockLength);
                NSData *type5 = [NSData dataWithBytes:data length:blockLength];
                
                uint32_t dataLength32 = htonl (blockLength - 4);
                memcpy (data, &dataLength32, sizeof (uint32_t));
                
                
                
                status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                            blockLength,
                                                            kCFAllocatorNull, NULL,
                                                            0,
                                                            blockLength,
                                                            0, &blockBuffer);
                
                NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
                break;
            }
            if (nalu_type == 1)
            {
                
                fouthStartCodeIndex = i;
                blockLength = frameSize - fouthStartCodeIndex;
                data = malloc(blockLength);
                data = memcpy(data, &frame[fouthStartCodeIndex], blockLength);
                NSData *type1 = [NSData dataWithBytes:data length:blockLength];
                
                uint32_t dataLength32 = htonl (blockLength - 4);
                memcpy (data, &dataLength32, sizeof (uint32_t));
                
                
                status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                            blockLength,
                                                            kCFAllocatorNull, NULL,
                                                            0,
                                                            blockLength,
                                                            0, &blockBuffer);
                
                NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
                break;
            }
        }
    }

//
//
//    CFMutableDictionaryRef atoms = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
//    CFMutableDictionarySetData(atoms, CFSTR ("avcC"), (uint8_t *)extraData, extraDataSize);
//    CFMutableDictionaryRef extensions = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
//    CFMutableDictionarySetObject(extensions, CFSTR ("SampleDescriptionExtensionAtoms"), (CFTypeRef *) atoms);
//    
//    CMVideoFormatDescriptionCreate(NULL, format_id, width, height, extensions, &videoFormatDescr);
    
    /*
    
    OSStatus status;
    
    uint8_t *data = NULL;
    uint8_t *pps = NULL;
    uint8_t *sps = NULL;
    
    int startCodeIndex = 0;
    int secondStartCodeIndex = 0;
    int thirdStartCodeIndex = 0;
    
    long blockLength = 0;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    
    int nalu_type = (frame[startCodeIndex + 4] & 0x1F);
    NSLog(@"nalu_type = %d",nalu_type);
    
    if (nalu_type != 7 && _formatDesc == NULL)
    {
        NSLog(@"Video error: Frame is not an I Frame and format description is null");
        return;
    }
    
    if (nalu_type == 7)
    {
        // 去掉起始头0x00 00 00 01   有的为0x00 00 01
        for (int i = startCodeIndex + 4; i < startCodeIndex + 440; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                secondStartCodeIndex = i;
                _spsSize = secondStartCodeIndex;
                break;
            }
        }
        
        nalu_type = (frame[secondStartCodeIndex + 4] & 0x1F);
    }
    NSLog(@"nalu_type = %d",nalu_type);
    if(nalu_type == 8)
    {
        for (int i = _spsSize + 4; i < _spsSize + 600; i++)
        {
            if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01)
            {
                thirdStartCodeIndex = i;
                _ppsSize = thirdStartCodeIndex - _spsSize;
                break;
            }
        }
        
        sps = malloc(_spsSize - 4);
        pps = malloc(_ppsSize - 4);
        
        memcpy (sps, &frame[4], _spsSize-4);
        memcpy (pps, &frame[_spsSize+4], _ppsSize-4);
        
        uint8_t*  parameterSetPointers[2] = {sps, pps};
        size_t parameterSetSizes[2] = {_spsSize-4, _ppsSize-4};
        
        status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                     (const uint8_t *const*)parameterSetPointers,
                                                                     parameterSetSizes, 4,
                                                                     &_formatDesc);
        
        
        nalu_type = (frame[thirdStartCodeIndex + 4] & 0x1F);
    }
    NSLog(@"nalu_type = %d",nalu_type);
    if((status == noErr) && (_decompressionSession == NULL))
    {
        [self createDecompSession];
    }
    
    
    
    if(nalu_type == 5)
    {
        
        int offset = _spsSize + _ppsSize;
        blockLength = frameSize - offset;
        data = malloc(blockLength);
        data = memcpy(data, &frame[offset], blockLength);
        NSData *type5 = [NSData dataWithBytes:data length:blockLength];
        
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                    blockLength,
                                                    kCFAllocatorNull, NULL,
                                                    0,
                                                    blockLength,
                                                    0, &blockBuffer);
        
        NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
    }
    
    if (nalu_type == 1)
    {
        blockLength = frameSize;
        data = malloc(blockLength);
        data = memcpy(data, &frame[0], blockLength);
        NSData *type1 = [NSData dataWithBytes:data length:blockLength];
        
        uint32_t dataLength32 = htonl (blockLength - 4);
        memcpy (data, &dataLength32, sizeof (uint32_t));
        
        status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                    blockLength,
                                                    kCFAllocatorNull, NULL,
                                                    0,
                                                    blockLength,
                                                    0, &blockBuffer);
    }
    */
    
    ////////////////////////////////////////////
    /*
    int fouthStartCodeIndex = 0;
    for (int i = startCodeIndex + 4; i < startCodeIndex + frameSize; i++)
    {
        if (frame[i] == 0x00 && frame[i+1] == 0x00 && frame[i+2] == 0x00 && frame[i+3] == 0x01 )
        {
            nalu_type = (frame[i + 4] & 0x1F);
            if (nalu_type == 5)
            {
                fouthStartCodeIndex = i;
                blockLength = frameSize - fouthStartCodeIndex;
                data = malloc(blockLength);
                data = memcpy(data, &frame[fouthStartCodeIndex], blockLength);
                NSData *type5 = [NSData dataWithBytes:data length:blockLength];
                
                uint32_t dataLength32 = htonl (blockLength - 4);
                memcpy (data, &dataLength32, sizeof (uint32_t));
                
                
                status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                            blockLength,
                                                            kCFAllocatorNull, NULL,
                                                            0,
                                                            blockLength,
                                                            0, &blockBuffer);
                
                NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
                break;
            }
            if (nalu_type == 1)
            {
                fouthStartCodeIndex = i;
                blockLength = frameSize - fouthStartCodeIndex;
                data = malloc(blockLength);
                data = memcpy(data, &frame[fouthStartCodeIndex], blockLength);
                NSData *type1 = [NSData dataWithBytes:data length:blockLength];
                
                uint32_t dataLength32 = htonl (blockLength - 4);
                memcpy (data, &dataLength32, sizeof (uint32_t));
                
                
                status = CMBlockBufferCreateWithMemoryBlock(NULL, data,
                                                            blockLength,
                                                            kCFAllocatorNull, NULL,
                                                            0,
                                                            blockLength,
                                                            0, &blockBuffer);
                
                NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
                break;
            }
        }
    }
    */
    ////////////////////////////////////////////
    
    
    
    if(status == noErr)
    {
        const size_t * samplesizeArrayPointer;
        size_t sampleSizeArray= blockLength;
        samplesizeArrayPointer = &sampleSizeArray;
        
//        int32_t timeSpan = 1000000;
//        CMTime PTime = CMTimeMake(0, timeSpan);
//        CMSampleTimingInfo timingInfo;
//        timingInfo.presentationTimeStamp = PTime;
//        timingInfo.duration =  kCMTimeZero;
//        timingInfo.decodeTimeStamp = kCMTimeInvalid;
        
        int32_t timeSpan = 90000;
        CMSampleTimingInfo timingInfo;
        frameCount++;
        NSDate *currentTime = [NSDate date];

        timingInfo.presentationTimeStamp = CMTimeMake(frameCount, timeSpan);
        timingInfo.duration =  CMTimeMake(3000, timeSpan);
        timingInfo.decodeTimeStamp = kCMTimeInvalid;
        
        status = CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, true, NULL, NULL, _formatDesc, 1, 1, &timingInfo, 0, samplesizeArrayPointer, &sampleBuffer);
        
//        const size_t sampleSize = blockLength;
//        status = CMSampleBufferCreate(kCFAllocatorDefault,
//                                      blockBuffer, true, NULL, NULL,
//                                      _formatDesc, 1, 0, NULL, 1,
//                                      &sampleSize, &sampleBuffer);
        
        NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
    }
    
    if(status == noErr)
    {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        
        [self render:sampleBuffer];
    }
    
    
    if (NULL != blockBuffer) {
        CFRelease(blockBuffer);
        blockBuffer = NULL;
    }
    
    [self relaseData:data];
    [self relaseData:pps];
    [self relaseData:sps];
    
    [self.delegate startDecodeData];
}

-(void)relaseData:(uint8_t*) tmpData{
    if (NULL != tmpData)
    {
        free (tmpData);
        tmpData = NULL;
    }
}

-(void) createDecompSession
{
    _decompressionSession = NULL;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                      [NSNumber numberWithBool:YES],
                                                      (id)kCVPixelBufferOpenGLESCompatibilityKey,
                                                      nil];
    //使用UIImageView播放时可以设置这个
    //    NSDictionary *destinationImageBufferAttributes =[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO],(id)kCVPixelBufferOpenGLESCompatibilityKey,[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil];
    
    OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc, NULL,
                                                    (__bridge CFDictionaryRef)(destinationImageBufferAttributes),
                                                    &callBackRecord, &_decompressionSession);
    NSLog(@"Video Decompression Session Create: \t %@", (status == noErr) ? @"successful!" : @"failed...");
}

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration)
{
    NSLog(@"presentationTimeStamp = %f,presentationDuration =%f",(float)presentationTimeStamp.value,
          (float)presentationDuration.value/presentationDuration.timescale);
    if (status != noErr || !imageBuffer) {
        NSLog(@"Error decompresssing frame at time: %.3f error: %d infoFlags: %u", (float)presentationTimeStamp.value/presentationTimeStamp.timescale, (int)status, (unsigned int)infoFlags);
        return;
    }
    
    __weak H264Decoder *weakSelf = (__bridge H264Decoder *)decompressionOutputRefCon;
    [weakSelf.delegate getDecodeImageData:imageBuffer];
}

- (void) render:(CMSampleBufferRef)sampleBuffer
{
    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags flagOut;
//    VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,
//                                      &sampleBuffer, &flagOut);
    
    NSDate *currentTime = [NSDate date];
    VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,
                                      (void*)CFBridgingRetain(currentTime), &flagOut);
    
    CFRelease(sampleBuffer);
}

NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)",    // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)",      // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)",         // SPS parameter
    @"8: Picture parameter set (non-VCL)",          // PPS parameter
    @"9: Access unit delimiter (non-VCL)",
    @"10: End of sequence (non-VCL)",
    @"11: End of stream (non-VCL)",
    @"12: Filler data (non-VCL)",
    @"13: Sequence parameter set extension (non-VCL)",
    @"14: Prefix NAL unit (non-VCL)",
    @"15: Subset sequence parameter set (non-VCL)",
    @"16: Reserved (non-VCL)",
    @"17: Reserved (non-VCL)",
    @"18: Reserved (non-VCL)",
    @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    @"20: Coded slice extension (non-VCL)",
    @"21: Coded slice extension for depth view components (non-VCL)",
    @"22: Reserved (non-VCL)",
    @"23: Reserved (non-VCL)",
    @"24: STAP-A Single-time aggregation packet (non-VCL)",
    @"25: STAP-B Single-time aggregation packet (non-VCL)",
    @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
    @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
    @"28: FU-A Fragmentation unit (non-VCL)",
    @"29: FU-B Fragmentation unit (non-VCL)",
    @"30: Unspecified (non-VCL)",
    @"31: Unspecified (non-VCL)",
};
@end

