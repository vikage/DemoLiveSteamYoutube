//
//  ViewController.m
//  LiveStream
//
//  Created by Thanh Vu on 1/14/20.
//  Copyright © 2020 ThanhDev. All rights reserved.
//

#import "ViewController.h"
#import "CVPixelBufferTools.h"
#import <ReplayKit/ReplayKit.h>
@import LFLiveKit;

@interface ViewController ()<LFLiveSessionDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
@property (nonatomic, strong) IBOutlet UILabel *timeLabel;
@property (nonatomic, strong) LFLiveSession *liveSession;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) CMSampleBufferRef cameraBuffer;
@property (nonatomic) CMSampleBufferRef screenBuffer;
@end

@interface LFLiveSession (Fix)
- (void)pushVideo:(nullable CVPixelBufferRef)pixelBuffer;
@end

@implementation LFLiveSession (Fix)

- (void)pushAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    AudioBufferList audioBufferList;
    CMBlockBufferRef blockBuffer;
    
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &audioBufferList, sizeof(audioBufferList), NULL, NULL, 0, &blockBuffer);
    
    for( int y=0; y<audioBufferList.mNumberBuffers; y++ ) {
        AudioBuffer audioBuffer = audioBufferList.mBuffers[y];
        void* audio = audioBuffer.mData;
        NSData *data = [NSData dataWithBytes:audio length:audioBuffer.mDataByteSize];
        [self pushAudio:data];
    }
    
    CFRelease(blockBuffer);
}

@end

@implementation ViewController {
    NSTimer *_timer;
    NSInteger numberOfFrame;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self config];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self resetFpsCounter];
        self.timeLabel.text = [[NSDate date] description];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.captureSession startRunning];
    [self startLive];
    [self startRecordScreen];
}

- (void)resetFpsCounter {
    NSLog(@"FPS %d", (int)numberOfFrame);
    numberOfFrame = 0;
}

- (void)increaseFpsCounter {
    numberOfFrame++;
}

- (void)setCameraBuffer:(CMSampleBufferRef)cameraBuffer {
    if (_cameraBuffer)
    {
        CMSampleBufferInvalidate(_cameraBuffer);
        CFRelease(_cameraBuffer);
    }
    
    _cameraBuffer = cameraBuffer;
}

- (void)setScreenBuffer:(CMSampleBufferRef)screenBuffer {
    if (_screenBuffer)
    {
        CMSampleBufferInvalidate(_screenBuffer);
        CFRelease(_screenBuffer);
    }
    
    _screenBuffer = screenBuffer;
}

- (void)config {
    self.captureSession = [[AVCaptureSession alloc] init];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInTrueDepthCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
    AVCaptureInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    [self.captureSession addInput:input];
    [self.captureSession addInput:audioInput];
    
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    [self.captureSession addOutput:self.videoOutput];
    
    AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [audioOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    [self.captureSession addOutput:audioOutput];
    
    AVCaptureConnection *connection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
}

- (void)startRecordScreen {
    [[RPScreenRecorder sharedRecorder] startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {
        switch (bufferType) {
            case RPSampleBufferTypeVideo: {
                CMSampleBufferRef copySample = NULL;
                CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &copySample);
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    self.screenBuffer = copySample;
                    [self processVideoBuffer];
                });
            }
                break;
            case RPSampleBufferTypeAudioMic:
            {
                [self.liveSession pushAudioBuffer:sampleBuffer];
            }
            default:
                break;
        }
    } completionHandler:^(NSError * _Nullable error) {
        
    }];
}

- (LFLiveSession *)liveSession {
    if (!_liveSession) {
        LFLiveAudioConfiguration *audioConfiguration = [LFLiveAudioConfiguration defaultConfigurationForQuality:LFLiveAudioQuality_High];
        audioConfiguration.numberOfChannels = 1;
        LFLiveVideoConfiguration *videoConfiguration;
        
        videoConfiguration = [LFLiveVideoConfiguration defaultConfigurationForQuality:LFLiveVideoQuality_High2 outputImageOrientation:UIInterfaceOrientationPortrait];
        videoConfiguration.videoSize = UIScreen.mainScreen.bounds.size;
        
        videoConfiguration.autorotate = YES;
        
        _liveSession = [[LFLiveSession alloc] initWithAudioConfiguration:audioConfiguration videoConfiguration:videoConfiguration captureType:LFLiveInputMaskAll];
        
        _liveSession.delegate = self;
        _liveSession.showDebugInfo = YES;
    }
    
    return _liveSession;
}

- (void)startLive {
    LFLiveStreamInfo *stream = [[LFLiveStreamInfo alloc] init];
    stream.url = @"rtmps://live-api-s.facebook.com:443/rtmp/827061461065962?s_bl=1&s_sml=3&s_sw=0&s_vt=api-s&a=AbwDCrt0ZOIXaq8-";
    
    [self.liveSession startLive:stream];
}

- (void)processVideoBuffer {
    if (self.screenBuffer == NULL || self.cameraBuffer == NULL) {
        return;
    }
    
    CVImageBufferRef screenPixelBuffer = CMSampleBufferGetImageBuffer(self.screenBuffer);
    CVImageBufferRef cameraPixelBuffer = CMSampleBufferGetImageBuffer(self.cameraBuffer);
    
    if (screenPixelBuffer == NULL || cameraPixelBuffer == NULL) {
        return;
    }
    
    CIImage *screenImage = [[CIImage alloc] initWithCVImageBuffer:screenPixelBuffer];
    CIImage *cameraImage = [[CIImage alloc] initWithCVImageBuffer:cameraPixelBuffer];

    cameraImage = [cameraImage imageByApplyingTransform:CGAffineTransformMakeScale(0.3, 0.3)];
    CIImage *mergeImage = [cameraImage imageByCompositingOverImage:screenImage];

    CVPixelBufferRef finalPixelBuffer = [CVPixelBufferTools getPixelBufferFromCIImage:mergeImage pixelBuffer:screenPixelBuffer];
    [self.liveSession pushVideo:finalPixelBuffer];
    [self increaseFpsCounter];
    CVPixelBufferRelease(finalPixelBuffer);
}

// MARK: - LFLiveSessionDelegate
- (void)liveSession:(LFLiveSession *)session debugInfo:(LFLiveDebug *)debugInfo {
}

- (void)liveSession:(LFLiveSession *)session errorCode:(LFLiveSocketErrorCode)errorCode {
    NSLog(@"Error %d", (int)errorCode);
}

- (void)liveSession:(LFLiveSession *)session liveStateDidChange:(LFLiveState)state {
    NSLog(@"liveStateDidChange %d", (int)state);
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (connection.output == self.videoOutput) {
        CMSampleBufferRef copySample = NULL;
        CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &copySample);
        self.cameraBuffer = copySample;
        [self processVideoBuffer];
    } else {
        [self.liveSession pushAudioBuffer:sampleBuffer];
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end
