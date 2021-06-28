//
//  ViewController.m
//  AVF
//
//  Created by Tocce on 2021/6/24.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <VideoToolbox/VideoToolbox.h>


@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate>

@property(nonatomic, strong)  AVCaptureSession *session;

@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property(nonatomic, assign) BOOL isFirst;
@property(nonatomic, strong) NSFileHandle *fileHandle;

@property(nonatomic, assign) VTCompressionSessionRef compressionSessionRef;
@property(nonatomic, strong) dispatch_queue_t operationQueue;

@property(nonatomic, strong) NSMutableData *mutableData;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _isFirst = false;
    
    self.mutableData = [NSMutableData data];
    
    [self configureFileHandle];
    [self configureCompress];
    
    [self setupAVFoundation];
    
}

- (void)configureFileHandle {

    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject]
                        stringByAppendingPathComponent:@"videoAudioCapture.h264"];
    
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
    [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:file];
    
}

- (BOOL)decodeBuffer:(CMSampleBufferRef)buffer isKeyFrameBuffer:(BOOL)iskey {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
    NSDictionary *framerPro = @{(__bridge  NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame:@(iskey)};
    OSStatus status = VTCompressionSessionEncodeFrame(_compressionSessionRef, imageBuffer, kCMTimeInvalid, kCMTimeInvalid, (__bridge CFDictionaryRef)framerPro, NULL, NULL);
    if(status != noErr){
        
        NSLog(@"encode failure %d", status);
        return false;
    }
    
    return true;
    
}


void encodeOutputDataCallback(void * CM_NULLABLE outputCallbackRefCon, void * CM_NULLABLE sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CM_NULLABLE CMSampleBufferRef sampleBuffer) {
    
    if(status != noErr || sampleBuffer == nil){
        NSLog(@"encode callBack failure");
        return;
    }
    
    
    
    if(!CMSampleBufferDataIsReady(sampleBuffer)){
        NSLog(@"data failure");
        return;
    }
    
    ViewController *vc = (__bridge ViewController *)outputCallbackRefCon;

    const char header[] = "\x00\x00\x00\x01";
    size_t headerLen = sizeof(header) - 1;
    NSData *headerData = [NSData dataWithBytes:header length:headerLen];
    
    CFArrayRef attachArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef dicValue = CFArrayGetValueAtIndex(attachArray, 0);
    BOOL isKey = CFDictionaryContainsKey(dicValue, kCMSampleAttachmentKey_NotSync);
    
    if(isKey){
        
        CMFormatDescriptionRef descriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sParameterSetSize, sParameterCount;
        const uint8_t *sParameterSet;
        OSStatus spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(descriptionRef, 0, &sParameterSet, &sParameterSetSize, &sParameterCount, 0);
        
        size_t pParameterSize, pParameterCount;
        const uint8_t *pParameterSet;
        OSStatus ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(descriptionRef, 1, &pParameterSet, &pParameterSize, &pParameterCount, 0);
        
        if(spsStatus == noErr && ppsStatus == noErr){
            
            NSData *sps = [NSData dataWithBytes:sParameterSet length:sParameterSetSize];
            NSData *pps = [NSData dataWithBytes:pParameterSet length:pParameterSize];
            
            NSMutableData *spsData = [NSMutableData data];
            [spsData appendData:headerData];
            [spsData appendData:sps];
            
            [vc.mutableData appendData:spsData];
            
            // 编码
            
            NSMutableData *ppsData = [NSMutableData data];
            [ppsData appendData:headerData];
            [ppsData appendData:pps];
            
            
            [vc.mutableData appendData:ppsData];
            
        }
        
        
    }
    
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    status = CMBlockBufferGetDataPointer(blockBuffer, 0, &length, &totalLength, &dataPointer);
    if (noErr != status)
    {
        
        NSLog(@"GetDataPointer Error : %d!", (int)status);
        return;
    }
    
    size_t bufferOffset = 0;
    static const int avcHeaderLength = 4;
    while (bufferOffset < totalLength - avcHeaderLength)
    {
        uint32_t nalUnitLength = 0;
        memcpy(&nalUnitLength, dataPointer + bufferOffset, avcHeaderLength);
        
        // 大端转小端
        nalUnitLength = CFSwapInt32BigToHost(nalUnitLength);
        
        NSData *frameData = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + avcHeaderLength) length:nalUnitLength];
        
        NSMutableData *outputFrameData = [NSMutableData data];
        [outputFrameData appendData:headerData];
        [outputFrameData appendData:frameData];
        [vc.mutableData appendData:outputFrameData];
        bufferOffset += avcHeaderLength + nalUnitLength;
    }
    
    NSLog(@"success === %@", vc.mutableData);

}

-(void)decodeNaluData:(NSData *)naluData
{
//    uint8_t *frame = (uint8_t *)naluData.bytes;
//    uint32_t frameSize = (uint32_t)naluData.length;
//    // frame的前4位是NALU数据的开始码，也就是00 00 00 01，第5个字节是表示数据类型，转为10进制后，7是sps,8是pps,5是IDR（I帧）信息
//    int nalu_type = (frame[4] & 0x1F);
//
//    // 将NALU的开始码替换成NALU的长度信息
//    uint32_t nalSize = (uint32_t)(frameSize - 4);
//    uint8_t *pNalSize = (uint8_t*)(&nalSize);
//    frame[0] = *(pNalSize + 3);
//    frame[1] = *(pNalSize + 2);
//    frame[2] = *(pNalSize + 1);
//    frame[3] = *(pNalSize);
//
//    switch (nalu_type)
//    {
//        case 0x05: // I帧
//            NSLog(@"NALU type is IDR frame");
//            if([self initH264Decoder])
//            {
//                [self decode:frame withSize:frameSize];
//            }
//
//            break;
//        case 0x07: // SPS
//            NSLog(@"NALU type is SPS frame");
//            _spsSize = frameSize - 4;
//            _sps = malloc(_spsSize);
//            memcpy(_sps, &frame[4], _spsSize);
//
//            break;
//        case 0x08: // PPS
//            NSLog(@"NALU type is PPS frame");
//            _ppsSize = frameSize - 4;
//            _pps = malloc(_ppsSize);
//            memcpy(_pps, &frame[4], _ppsSize);
//            break;
//
//        default: // B帧或P帧
//            NSLog(@"NALU type is B/P frame");
//            if([self initH264Decoder])
//            {
//                [self decode:frame withSize:frameSize];
//            }
//            break;
//    }
}



#pragma 配置

- (void)configureCompress {
    
    OSStatus status = VTCompressionSessionCreate(NULL, 1024, 1080, kCMVideoCodecType_H264, NULL, NULL, NULL, encodeOutputDataCallback, (__bridge void * _Nullable)(self), &_compressionSessionRef);
    if(noErr != status){
        NSLog(@"解码器创作失败");
        return;
    }
    
    NSInteger bite = 1024 * 1024;
    OSStatus status1 = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bite));
    if(status1 != noErr){
        NSLog(@"bite failure");
        return;
    }
    int64_t dataLimitBytesPerSecondValue = bite * 1.5 / 8;
    CFNumberRef bytesPerSecond = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &dataLimitBytesPerSecondValue);
    int64_t oneSecondValue = 1;
    CFNumberRef oneSecond = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &oneSecondValue);
    const void* nums[2] = {bytesPerSecond, oneSecond};
    CFArrayRef dataRateLimits = CFArrayCreate(NULL, nums, 2, &kCFTypeArrayCallBacks);
    status = VTSessionSetProperty( _compressionSessionRef, kVTCompressionPropertyKey_DataRateLimits, dataRateLimits);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_DataRateLimits failed status:%d", (int)status);
        return ;
    }
    
    status1 = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    
    if(status1 != noErr) {
        NSLog(@"profile level failure");
        return;
    }
    
    status1 = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    if(status1 != noErr) {
        NSLog(@"Real Time failure");
        return;
    }
    
    status1 = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    if(status1 != noErr) {
        NSLog(@"B framer failure");
        return;
    }
    
    status1 = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(15 * 240));
    
    if(status1 != noErr) {
        NSLog(@"Max Frame failure");
        return;
    }
    
    
    status1 = VTCompressionSessionPrepareToEncodeFrames(_compressionSessionRef);
    
    if(status1 != noErr) {
        NSLog(@"prepare failure");
        return;
    }
    
    NSLog(@"配置成功 === %@", self.compressionSessionRef);
    
}


- (void)setupAVFoundation
{
    //session
    self.session = [[AVCaptureSession alloc] init];
    [self.session setSessionPreset:AVCaptureSessionPresetLow];
//    [self.session setSessionPreset:AVCaptureSessionPresetHigh];

    //device
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    //input
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if(input) {
        [self.session addInput:input];
    } else {
        NSLog(@"%@", error);
        return;
    }
    
    AVCaptureVideoPreviewLayer *previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];

    CALayer *rootLayer = [[self view] layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:CGRectMake(-70, 0, rootLayer.bounds.size.height, rootLayer.bounds.size.height)];
    [rootLayer insertSublayer:previewLayer atIndex:0];
    
    CALayer *layer = [[CALayer alloc]init];
    layer.frame = CGRectMake(20, 20, 50, 50);
    layer.opacity = .5;
    layer.backgroundColor = [UIColor redColor].CGColor;
    [rootLayer addSublayer:layer];
    
    

    //output
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    if([self.session canAddOutput:output]){
        [self.session addOutput:output];
    }
    
    output.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
    [output setAlwaysDiscardsLateVideoFrames:YES];
    
    
    [output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    
    
    
    

    //start
    [self.session startRunning];
}


- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//
//    CVPixelBufferLockBaseAddress(imageBuffer, 0);
//    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
//    size_t height = CVPixelBufferGetHeight(imageBuffer);
//    size_t y_size = width * height;
//    size_t uv_size = y_size / 4;
//    size_t count = CVPixelBufferGetPlaneCount(imageBuffer);
//
//    size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
//
//    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
//    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, baseAddress, bufferSize, NULL);
//    CGImageRef cgImage = CGImageCreate(width, height, 8, 32, bytesPerRow, rgbColorSpace, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrderDefault, provider, NULL, true, kCGRenderingIntentDefault);
//    UIImage *createImage = [UIImage imageWithCGImage:cgImage];
//
//    NSLog(@"%@", imageBuffer);
    
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    [self decodeBuffer:sampleBuffer isKeyFrameBuffer:false];
}










- (UIImage*)uiImageFromPixelBuffer:(CVPixelBufferRef)p {
    CIImage* ciImage = [CIImage imageWithCVPixelBuffer:p];
    
    CIContext* context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer : @(YES)}];
    
    CGRect rect = CGRectMake(0, 0, CVPixelBufferGetWidth(p), CVPixelBufferGetHeight(p));
    CGImageRef videoImage = [context createCGImage:ciImage fromRect:rect];
    
    UIImage* image = [UIImage imageWithCGImage:videoImage];
    
    
    CGImageRelease(videoImage);
    
    return image;
}



- (void)loadImageFinished:(UIImage *)image
{
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            
         //写入图片到相册
        PHAssetChangeRequest *req = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        NSLog(@"写入图片到相册 === %@", req);
            
     } completionHandler:^(BOOL success, NSError * _Nullable error) {
            
         NSLog(@"success = %d, error = %@", success, error);
            
    }];
}

@end
