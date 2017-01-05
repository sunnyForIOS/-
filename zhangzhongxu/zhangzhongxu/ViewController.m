//
//  ViewController.m
//  zhangzhongxu
//
//  Created by 张忠旭 on 16/10/2.
//  Copyright © 2016年 张忠旭. All rights reserved.
//

#import "ViewController.h"

#include "libavutil/intreadwrite.h"
#include "avcodec.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"
#include "CommonUitl.h"
#import "FCOutputAudio.h"
#import "KxAudioManager.h"
#import "KxLogger.h"
#import <Accelerate/Accelerate.h>


#define MAXAUDIOBUF		245670 //9600/*245760*/
static void avStreamFPSTimeBase(AVStream *st, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase)
{
    CGFloat fps, timebase;
    
    if (st->time_base.den && st->time_base.num)
        timebase = av_q2d(st->time_base);
    else if(st->codec->time_base.den && st->codec->time_base.num)
        timebase = av_q2d(st->codec->time_base);
    else
        timebase = defaultTimeBase;
    
    if (st->codec->ticks_per_frame != 1) {
        //timebase *= st->codec->ticks_per_frame;
    }
    
    if (st->avg_frame_rate.den && st->avg_frame_rate.num)
        fps = av_q2d(st->avg_frame_rate);
    else if (st->r_frame_rate.den && st->r_frame_rate.num)
        fps = av_q2d(st->r_frame_rate);
    else
        fps = 1.0 / timebase;
    
    if (pFPS)
        *pFPS = fps;
    if (pTimeBase)
        *pTimeBase = timebase;
}

typedef enum {
    
    KxMovieFrameTypeAudio,
    KxMovieFrameTypeVideo,
    KxMovieFrameTypeArtwork,
    KxMovieFrameTypeSubtitle,
    
} KxMovieFrameType;
@interface KxMovieFrame : NSObject
@property (readonly, nonatomic) KxMovieFrameType type;

@end

@interface KxAudioFrame : KxMovieFrame
@property (readwrite, nonatomic) CGFloat position;
@property (readwrite, nonatomic) CGFloat duration;
@property (readwrite, nonatomic, strong) NSData *samples;
@end

@implementation KxMovieFrame
@end

@implementation KxAudioFrame
- (KxMovieFrameType) type { return KxMovieFrameTypeAudio; }
@end

@interface ViewController ()
{
    FCOutputAudio	*_out_audio;
    AudioStreamBasicDescription _audio_fmt;
    AVCodecContext *_audioCodecCtx;
    AVFrame *_audioFrame;
    AVCodec *aCodec;
    SwrContext *_swrContext;
    CGFloat _audioTimeBase;
    CGFloat _videoTimeBase;
    CGFloat fps;
    void *_swrBuffer;
    NSInteger _swrBufferSize;
    NSMutableArray      *_audioFrames;
    NSUInteger          _currentAudioFramePos;
    NSData              *_currentAudioFrame;
    
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _out_audio = [[FCOutputAudio alloc] init];
    _audioFrames = [NSMutableArray array];
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    [audioManager activateAudioSession];
    
    [self initWithVideo:[CommonUitl bundlePath:@"tg.mp3"]];// test.264  mytest.mp4(Mp4Hander 生成的文件h264格式)
    
    self.outputFrames = [NSMutableArray new];
    self.presentationTimes = [NSMutableArray new];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.displayLink setPaused:YES];
    self.bufferSemaphore = dispatch_semaphore_create(0);
    
    _h264Decoder = [[H264Decoder alloc]init];
    _h264Decoder.delegate = self;
    
    //开始播放
    dispatch_async(dispatch_queue_create("com.wikijoin.video", NULL), ^{
        [self loadFrame];
    });
    
}

-(void)initWithVideo:(NSString *)moviePath
{
    
    AVCodec *pCodec;
    avcodec_register_all();
    av_register_all();
    
    avformat_network_init();
    //moviePath = @"rtmp://live.hkstv.hk.lxdns.com/live/hks";
    // moviePath = @"rtsp://192.168.42.1/live";
    moviePath = @"rtsp://184.72.239.149/vod/mp4:BigBuckBunny_115k.mov";
    //moviePath = @"rtmp://live.hkstv.hk.lxdns.com/live/hks";
    NSData *data = [NSData dataWithContentsOfFile:moviePath];
    if (data.length > 0) {
        // NSLog(@"source data =%@",data);
    }
    
    AVDictionary *options = NULL;
    //av_dict_set(&options, "rtsp_transport", "tcp", 0);
    av_dict_set(&options, "probesize", "122880", 0);
    pFormatCtx = avformat_alloc_context();
    
    if (avformat_open_input(&pFormatCtx,[moviePath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &options) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        return;
    }
    
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        avformat_close_input(&pFormatCtx);
        return ;
    }
    
    av_dump_format(pFormatCtx, 0, [moviePath.lastPathComponent cStringUsingEncoding: NSUTF8StringEncoding], false);
    
    
    //    if ((streamNo = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, &pCodec, 0)) < 0) {
    //        av_log(NULL, AV_LOG_ERROR, "Cannot find a video stream in the input file\n");
    //        return;
    //    }
    streamNo = -1;
    audioNo = -1;
    
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_VIDEO) {
            streamNo = i;
            break;
        }
    }
    
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioNo = i;
            break;
        }
    }
    if (streamNo != -1) {
        AVCodecContext* pCodecCtx = pFormatCtx->streams[streamNo]->codec;
        //NSData *extraData = [NSData dataWithBytes:pCodecCtx->extradata length:pCodecCtx->extradata_size];
        pCodec = avcodec_find_decoder(pCodecCtx->codec_id);
        if(avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot open video decoder\n");
            return;
        }
        
    }
    //
    
    //    if ((audioNo = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &aCodec, 0)) < 0) {
    //        av_log(NULL, AV_LOG_ERROR, "Cannot find a video stream in the input file\n");
    //        return;
    //    }
    AVStream *stream = pFormatCtx->streams[streamNo];
    avStreamFPSTimeBase(stream, 0.04, &fps, &_videoTimeBase);
    NSLog(@"_videoTimeBase = %f", _videoTimeBase);
    int ret = [self openAudioStream:audioNo];
    //    aCodecCtx = pFormatCtx->streams[audioNo]->codec;
    //    //NSData *extraData = [NSData dataWithBytes:pCodecCtx->extradata length:pCodecCtx->extradata_size];
    //    aCodec = avcodec_find_decoder(aCodecCtx->codec_id);
    //    if(avcodec_open2(aCodecCtx, aCodec, NULL) < 0) {
    //        av_log(NULL, AV_LOG_ERROR, "Cannot open video decoder\n");
    //        return;
    //    }
    
    
    
}

-(void)loadFrame
{
    
    while (av_read_frame(pFormatCtx, &packet)>= 0) {
        if (packet.stream_index == streamNo) {
            NSLog(@"video pkt->pts = %lld,pkt->dts =%d", packet.pts,packet.dts);
            
            NSLog(@"=========dddd=========");
            [_h264Decoder decodeFrame:packet.data withSize:packet.size withExtraData:pFormatCtx->streams[streamNo]->codec->extradata withExtraDataSize:pFormatCtx->streams[streamNo]->codec->extradata_size];
        }
        else if(packet.stream_index == audioNo)
        {
            NSLog(@"audio pkt->pts = %lld,pkt->dts =%d", packet.pts,packet.dts);
            
            int pktSize = packet.size;
            
            while (pktSize > 0) {
                
                int gotframe = 0;
                int len = avcodec_decode_audio4(_audioCodecCtx,
                                                _audioFrame,
                                                &gotframe,
                                                &packet);
                
                if (len < 0) {
                    NSLog( @"decode audio error, skip packet");
                    break;
                }
                
                if (gotframe) {
                    // [self AudioThread:_audioFrame->data[0] size:_audioFrame->nb_samples];
                    KxAudioFrame * frame = [self handleAudioFrame];
                    [_audioFrames addObject:frame];
                }
                if (0 == len)
                    break;
                
                pktSize -= len;
            }
            
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)displayPixelBuffer:(CVImageBufferRef)imageBuffer
{
    int width = (int)CVPixelBufferGetWidth(imageBuffer);
    int height = (int)CVPixelBufferGetHeight(imageBuffer);
    CGFloat halfWidth = self.view.frame.size.width;
    CGFloat halfheight = self.view.frame.size.height;
    if (width > halfWidth || height > halfheight) {
        width /= 2;
        height /= 2;
    }
    if (!openGLLayer) {
        openGLLayer = [[AAPLEAGLLayer alloc] init];
        [openGLLayer setFrame:CGRectMake((self.view.frame.size.width-width)/2, (self.view.frame.size.height-height)/2, width, height)];
        openGLLayer.presentationRect = CGSizeMake(width, height);
        
        [openGLLayer setupGL];
        [self.view.layer addSublayer:openGLLayer];
        
        [openGLLayer start:@"mytest.mp4" width:width height:height];
    }
    
    [openGLLayer displayPixelBuffer:imageBuffer];
    
}

- (void)displayLinkCallback:(CADisplayLink *)sender
{
    if ([self.outputFrames count] && [self.presentationTimes count]) {
        CVImageBufferRef imageBuffer = NULL;
        NSNumber *insertionIndex = nil;
        id imageBufferObject = nil;
        @synchronized(self){
            insertionIndex = [self.presentationTimes firstObject];
            imageBufferObject = [self.outputFrames firstObject];
            imageBuffer = (__bridge CVImageBufferRef)imageBufferObject;
            
            if (imageBufferObject) {
                [self.outputFrames removeObjectAtIndex:0];
            }
            if (insertionIndex) {
                [self.presentationTimes removeObjectAtIndex:0];
                if ([self.presentationTimes count] == 3) {
                    dispatch_semaphore_signal(self.bufferSemaphore);
                }
            }
            
            if (imageBuffer) {
                [self displayPixelBuffer:imageBuffer];
            }
        }
        
    }
}

#pragma --mark H264DecoderDelegate
-(void) startDecodeData
{
    if ([self.presentationTimes count] >= 5) {
        [self.displayLink setPaused:NO];
        dispatch_semaphore_wait(self.bufferSemaphore, DISPATCH_TIME_FOREVER);
    }
}

-(void) getDecodeImageData:(CVImageBufferRef) imageBuffer
{
    id imageBufferObject = (__bridge id)imageBuffer;
    @synchronized(self){
        NSUInteger insertionIndex = self.presentationTimes.count + 1;
        
        [self.outputFrames addObject:imageBufferObject];
        [self.presentationTimes addObject:[NSNumber numberWithInteger:insertionIndex]];
        
    }
}

//////////////////////////////////////////////////
//音频
-(void)AudioThread:(uint8_t *)data size:(int)len
{
    if (![_out_audio IsInit]) {
        //初始音频设备相关
        
        bzero(&_audio_fmt, sizeof(AudioStreamBasicDescription));
        _audio_fmt.mSampleRate = 8000;
        _audio_fmt.mFormatID = kAudioFormatLinearPCM;
        _audio_fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        _audio_fmt.mBytesPerPacket = 2;
        _audio_fmt.mBytesPerFrame = 2;
        _audio_fmt.mFramesPerPacket = 1;
        _audio_fmt.mChannelsPerFrame = 1;
        _audio_fmt.mBitsPerChannel = 16;
        
        assert([_out_audio InitAudio:&_audio_fmt : MAXAUDIOBUF]);
        [_out_audio AudioStart];
    }
    
    [_out_audio WriteData:data : len ];
}

- (int) openAudioStream: (NSInteger) audioStream
{
    if (audioNo == -1)
        return -1;
    _audioCodecCtx = pFormatCtx->streams[audioNo]->codec;
    //NSData *extraData = [NSData dataWithBytes:pCodecCtx->extradata length:pCodecCtx->extradata_size];
    
    SwrContext *swrContext = NULL;
    
    AVCodec *codec = avcodec_find_decoder(_audioCodecCtx->codec_id);
    if(!codec)
        return -1;
    
    if (avcodec_open2(_audioCodecCtx, codec, NULL) < 0)
        return -1;
    
    if (!audioCodecIsSupported(_audioCodecCtx)) {
        
        id<KxAudioManager> audioManager = [KxAudioManager audioManager];
        swrContext = swr_alloc_set_opts(NULL,
                                        av_get_default_channel_layout(audioManager.numOutputChannels),
                                        AV_SAMPLE_FMT_S16,
                                        audioManager.samplingRate,
                                        av_get_default_channel_layout(_audioCodecCtx->channels),
                                        _audioCodecCtx->sample_fmt,
                                        _audioCodecCtx->sample_rate,
                                        0,
                                        NULL);
        
        int rec = swr_init(swrContext);
        if (!swrContext || rec
            /*swr_init(swrContext)*/) {
            
            if (swrContext)
                swr_free(&swrContext);
            avcodec_close(_audioCodecCtx);
            
            return -1;
        }
    }
    
    _audioFrame = av_frame_alloc();
    
    if (!_audioFrame) {
        if (swrContext)
            swr_free(&swrContext);
        avcodec_close(_audioCodecCtx);
        return -1;
    }
    
    audioNo = audioStream;
    _swrContext = swrContext;
    
    AVStream *st = pFormatCtx->streams[audioNo];
    avStreamFPSTimeBase(st, 0.025, 0, &_audioTimeBase);
    
    NSLog( @"audio codec smr: %.d fmt: %d chn: %d tb: %f %@",
          _audioCodecCtx->sample_rate,
          _audioCodecCtx->sample_fmt,
          _audioCodecCtx->channels,
          _audioTimeBase,
          _swrContext ? @"resample" : @"");
    [self enableAudio:YES];
    return 0;
}

- (KxAudioFrame *) handleAudioFrame
{
    if (!_audioFrame->data[0])
        return nil;
    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    
    const NSUInteger numChannels = audioManager.numOutputChannels;
    NSInteger numFrames;
    
    void * audioData;
    
    if (_swrContext) {
        
        const NSUInteger ratio = MAX(1, audioManager.samplingRate / _audioCodecCtx->sample_rate) *
        MAX(1, audioManager.numOutputChannels / _audioCodecCtx->channels) * 2;
        
        const int bufSize = av_samples_get_buffer_size(NULL,
                                                       audioManager.numOutputChannels,
                                                       _audioFrame->nb_samples * ratio,
                                                       AV_SAMPLE_FMT_S16,
                                                       1);
        
        if (!_swrBuffer || _swrBufferSize < bufSize) {
            _swrBufferSize = bufSize;
            _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
        }
        
        Byte *outbuf[2] = { _swrBuffer, 0 };
        
        numFrames = swr_convert(_swrContext,
                                outbuf,
                                _audioFrame->nb_samples * ratio,
                                (const uint8_t **)_audioFrame->data,
                                _audioFrame->nb_samples);
        
        if (numFrames < 0) {
            LoggerAudio(0, @"fail resample audio");
            return nil;
        }
        
        //int64_t delay = swr_get_delay(_swrContext, audioManager.samplingRate);
        //if (delay > 0)
        //    LoggerAudio(0, @"resample delay %lld", delay);
        
        audioData = _swrBuffer;
        
    } else {
        
        if (_audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
            NSAssert(false, @"bucheck, audio format is invalid");
            return nil;
        }
        
        audioData = _audioFrame->data[0];
        numFrames = _audioFrame->nb_samples;
    }
    
    const NSUInteger numElements = numFrames * numChannels;
    NSMutableData *data = [NSMutableData dataWithLength:numElements * sizeof(float)];
    
    float scale = 1.0 / (float)INT16_MAX ;
    vDSP_vflt16((SInt16 *)audioData, 1, data.mutableBytes, 1, numElements);
    vDSP_vsmul(data.mutableBytes, 1, &scale, data.mutableBytes, 1, numElements);
    
    KxAudioFrame *frame = [[KxAudioFrame alloc] init];
    frame.position = av_frame_get_best_effort_timestamp(_audioFrame) * _audioTimeBase;
    frame.duration = av_frame_get_pkt_duration(_audioFrame) * _audioTimeBase;
    frame.samples = data;
    NSLog(@"audio frame position =%f,audio frame duration =%f",frame.position,frame.duration);
    if (frame.duration == 0) {
        // sometimes ffmpeg can't determine the duration of audio frame
        // especially of wma/wmv format
        // so in this case must compute duration
        frame.duration = frame.samples.length / (sizeof(float) * numChannels * audioManager.samplingRate);
    }
    
#if 0
    LoggerAudio(2, @"AFD: %.4f %.4f | %.4f ",
                frame.position,
                frame.duration,
                frame.samples.length / (8.0 * 44100.0));
#endif
    
    return frame;
}


static BOOL audioCodecIsSupported(AVCodecContext *audio)
{
    if (audio->sample_fmt == AV_SAMPLE_FMT_S16) {
        
        id<KxAudioManager> audioManager = [KxAudioManager audioManager];
        return  (int)audioManager.samplingRate == audio->sample_rate &&
        audioManager.numOutputChannels == audio->channels;
    }
    return NO;
}
- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    //fillSignalF(outData,numFrames,numChannels);
    //return;
    BOOL _buffered = YES;
    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        //return;
    }
    
    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        KxAudioFrame *frame = _audioFrames[0];
                        
#ifdef DUMP_AUDIO_DATA
                        LoggerAudio(2, @"Audio frame position: %f", frame.position);
#endif
                        
                        
                        
                        [_audioFrames removeObjectAtIndex:0];
                        
                        
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //LoggerStream(1, @"silence audio");
                
                break;
            }
        }
    }
}

- (void) enableAudio: (BOOL) on
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    
    if (on ) {
        
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
        LoggerAudio(2, @"audio device smr: %d fmt: %d chn: %d",
                    (int)audioManager.samplingRate,
                    (int)audioManager.numBytesPerSample,
                    (int)audioManager.numOutputChannels);
        
    } else {
        
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}


@end
