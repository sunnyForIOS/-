//
//  ViewController.h
//  zhangzhongxu
//
//  Created by 张忠旭 on 16/10/2.
//  Copyright © 2016年 张忠旭. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "H264Decoder.h"

#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avio.h"
#import "AAPLEAGLLayer.h"

@interface ViewController : UIViewController<H264DecoderDelegate>{
    AVFormatContext *pFormatCtx;
    AVPacket packet;
    AVPicture picture;
    int streamNo;
    int audioNo;
    AAPLEAGLLayer *openGLLayer;
}

@property CADisplayLink *displayLink;
@property NSMutableArray *outputFrames;
@property NSMutableArray *presentationTimes;
@property dispatch_semaphore_t bufferSemaphore;

@property (nonatomic, retain) H264Decoder *h264Decoder;

@end
