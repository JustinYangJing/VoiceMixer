//
//  MixerVoiceHandle.m
//  VoiceMixer
//
//  Created by JustinYang on 2017/4/17.
//  Copyright © 2017年 JustinYang. All rights reserved.
//

#import "MixerVoiceHandle.h"
#import "CAComponentDescription.h"
//输出音频的采样率(也是session设置的采样率)，
const double kGraphSampleRate = 44100.0;
//每次回调提供多长时间的数据,结合采样率 0.005 = x*1/44100, x = 220.5, 因为回调函数中的inNumberFrames是2的幂，所以x应该是256
const double kSessionBufDuration    = 0.005;

void CheckError(OSStatus error,const char *operaton){
    if (error==noErr) {
        return;
    }
    char errorString[20]={};
    *(UInt32 *)(errorString+1)=CFSwapInt32HostToBig(error);
    if (isprint(errorString[1])&&isprint(errorString[2])&&isprint(errorString[3])&&isprint(errorString[4])) {
        errorString[0]=errorString[5]='\'';
        errorString[6]='\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error:%s (%s)\n",operaton,errorString);
    exit(1);
}

typedef struct {
    AudioStreamBasicDescription asbd;
    Float32 *leftData;
    Float32 *rightData;
    UInt32 numFrames;
    UInt32 sampleNum;
    UInt32 channelCount; //声音是单声道还是立体声
} SoundBuffer, *SoundBufferPtr;

@interface MixerVoiceHandle ()

@property (nonatomic,strong) NSArray *sourceArr;

@end


@implementation MixerVoiceHandle{
    SoundBufferPtr _mSoundBufferP;
    AUGraph        _mGraph;
    AudioUnit      _mMixer;
    AudioUnit      _mOutput;
    dispatch_queue_t _mQueue;//串行队列,初始化和初始设置音量等操作放到这个队列中，因为加载文件需要比较久，所以都放到了子线程中
}
-(instancetype)initWithSourceArr:(NSArray *)sourceArr{
    self = [super init];
    if (self) {
        if (sourceArr.count < 2) {
            fprintf(stderr, "文件个数不能为少于2个");
            return nil;
        }
        self.isPlaying = NO;
        self.sourceArr = sourceArr;
        _mQueue = dispatch_queue_create("serial queue", DISPATCH_QUEUE_SERIAL);
        dispatch_async(_mQueue, ^{
            [self loadFileIntoMemory];
            [self configGraph];
        });
    }
    return self;
}

-(void)loadFileIntoMemory{
    
    _mSoundBufferP = (SoundBufferPtr)malloc(sizeof(SoundBuffer) * self.sourceArr.count);
    
    for (int i = 0; i < self.sourceArr.count; i++) {
        NSLog(@"read Audio file : %@",self.sourceArr[i]);
        CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)self.sourceArr[i], kCFURLPOSIXPathStyle, false);
        ExtAudioFileRef fp;
        //open the audio file
        CheckError(ExtAudioFileOpenURL(url, &fp), "cant open the file");
        
        AudioStreamBasicDescription fileFormat;
        UInt32 propSize = sizeof(fileFormat);
        
        //read the file data format , it represents the file's actual data format.
        CheckError(ExtAudioFileGetProperty(fp, kExtAudioFileProperty_FileDataFormat,
                                           &propSize, &fileFormat),
                   "read audio data format from file");
        
        double rateRatio = kGraphSampleRate/fileFormat.mSampleRate;
        
        UInt32 channel = 1;
        if (fileFormat.mChannelsPerFrame == 2) {
            channel = 2;
        }
        AVAudioFormat *clientFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                       sampleRate:kGraphSampleRate
                                                                         channels:channel
                                                                      interleaved:NO];
        
        propSize = sizeof(AudioStreamBasicDescription);
        //设置从文件中读出的音频格式
        CheckError(ExtAudioFileSetProperty(fp, kExtAudioFileProperty_ClientDataFormat,
                                           propSize, clientFormat.streamDescription),
                   "cant set the file output format");
        //get the file's length in sample frames
        UInt64 numFrames = 0;
        propSize = sizeof(numFrames);
        CheckError(ExtAudioFileGetProperty(fp, kExtAudioFileProperty_FileLengthFrames,
                                           &propSize, &numFrames),
                   "cant get the fileLengthFrames");
        
        numFrames = numFrames * rateRatio;
        
        _mSoundBufferP[i].numFrames = (UInt32)numFrames;
        _mSoundBufferP[i].channelCount = channel;
        _mSoundBufferP[i].asbd      = *(clientFormat.streamDescription);
        _mSoundBufferP[i].leftData = (Float32 *)calloc(numFrames, sizeof(Float32));
        if (channel == 2) {
            _mSoundBufferP[i].rightData = (Float32 *)calloc(numFrames, sizeof(Float32));
        }
        
        _mSoundBufferP[i].sampleNum = 0;
        //如果是立体声，还要多为AudioBuffer申请一个空间存放右声道数据
        AudioBufferList *bufList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer)*(channel-1));
        
        AudioBuffer emptyBuffer = {0};
        for (int arrayIndex = 0; arrayIndex < channel; arrayIndex++) {
            bufList->mBuffers[arrayIndex] = emptyBuffer;
        }
        bufList->mNumberBuffers = channel;
        
        bufList->mBuffers[0].mNumberChannels = 1;
        bufList->mBuffers[0].mData = _mSoundBufferP[i].leftData;
        bufList->mBuffers[0].mDataByteSize = (UInt32)numFrames*sizeof(Float32);
        
        if (2 == channel) {
            bufList->mBuffers[1].mNumberChannels = 1;
            bufList->mBuffers[1].mDataByteSize = (UInt32)numFrames*sizeof(Float32);
            bufList->mBuffers[1].mData = _mSoundBufferP[i].rightData;
        }
        
        UInt32 numberOfPacketsToRead = (UInt32) numFrames;
        CheckError(ExtAudioFileRead(fp, &numberOfPacketsToRead,
                                    bufList),
                   "cant read the audio file");
        free(bufList);
        ExtAudioFileDispose(fp);
    }
}

-(void)configGraph{
    
    CheckError(NewAUGraph(&_mGraph), "cant new a graph");
    
    
    AUNode mixerNode;
    AUNode outputNode;
    
    AudioComponentDescription mixerACD;
    mixerACD.componentType      = kAudioUnitType_Mixer;
    mixerACD.componentSubType   = kAudioUnitSubType_MultiChannelMixer;
    mixerACD.componentManufacturer = kAudioUnitManufacturer_Apple;
    mixerACD.componentFlags = 0;
    mixerACD.componentFlagsMask = 0;
    
    AudioComponentDescription outputACD;
    outputACD.componentType      = kAudioUnitType_Output;
    outputACD.componentSubType   = kAudioUnitSubType_RemoteIO;
    outputACD.componentManufacturer = kAudioUnitManufacturer_Apple;
    outputACD.componentFlags = 0;
    outputACD.componentFlagsMask = 0;
    
    CheckError(AUGraphAddNode(_mGraph, &mixerACD,
                              &mixerNode),
               "cant add node");
    CheckError(AUGraphAddNode(_mGraph, &outputACD,
                              &outputNode),
               "cant add node");
    
    CheckError(AUGraphConnectNodeInput(_mGraph, mixerNode, 0, outputNode, 0),
               "connect mixer Node to output node error");
    
    CheckError(AUGraphOpen(_mGraph), "cant open the graph");
    
    CheckError(AUGraphNodeInfo(_mGraph, mixerNode,
                               NULL, &_mMixer),
               "generate mixer unit error");
    CheckError(AUGraphNodeInfo(_mGraph, outputNode, NULL, &_mOutput),
               "generate remote I/O unit error");
    
    UInt32 numberOfMixBus = (UInt32)self.sourceArr.count;
    
    //配置混音的路数，有多少个音频文件要混音
    CheckError(AudioUnitSetProperty(_mMixer, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0,
                                    &numberOfMixBus, sizeof(numberOfMixBus)),
               "set mix elements error");
    
    // Increase the maximum frames per slice allows the mixer unit to accommodate the
    //    larger slice size used when the screen is locked.
    UInt32 maximumFramesPerSlice = 4096;
    CheckError( AudioUnitSetProperty (_mMixer,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &maximumFramesPerSlice,
                                      sizeof (maximumFramesPerSlice)
                                      ), "cant set kAudioUnitProperty_MaximumFramesPerSlice");

    
    for (int i = 0; i < numberOfMixBus; i++) {
        // setup render callback struct
        AURenderCallbackStruct rcbs;
        rcbs.inputProc = &renderInput;
        rcbs.inputProcRefCon = _mSoundBufferP;
        
        CheckError(AUGraphSetNodeInputCallback(_mGraph, mixerNode, i, &rcbs),
                   "set mixerNode callback error");
        
        
        AVAudioFormat *clientFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                       sampleRate:kGraphSampleRate
                                                                         channels:_mSoundBufferP[i].channelCount
                                                                      interleaved:NO];
        CheckError(AudioUnitSetProperty(_mMixer, kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input, i,
                                        clientFormat.streamDescription, sizeof(AudioStreamBasicDescription)),
                   "cant set the input scope format on bus[i]");
        
    }
    
    double sample = kGraphSampleRate;
    CheckError(AudioUnitSetProperty(_mMixer, kAudioUnitProperty_SampleRate,
                                    kAudioUnitScope_Output, 0,&sample , sizeof(sample)),
               "cant the mixer unit output sample");
    //未设置io unit kAudioUnitScope_Output 的element 1的输出AudioComponentDescription
    
    
    CheckError(AUGraphInitialize(_mGraph), "cant initial graph");
    
}

-(void)stopAUGraph{
    Boolean isRunning = false;
    
    OSStatus result = AUGraphIsRunning(_mGraph, &isRunning);
    if (result) { printf("AUGraphIsRunning result %ld %08lX %4.4s\n", (long)result, (long)result, (char*)&result); return; }
    
    if (isRunning) {
        result = AUGraphStop(_mGraph);
        if (result) { printf("AUGraphStop result %ld %08lX %4.4s\n", (long)result, (long)result, (char*)&result); return; }
        self.isPlaying = NO;
    }
}
-(void)startAUGraph{
    printf("PLAY\n");
    
    OSStatus result = AUGraphStart(_mGraph);
    if (result) { printf("AUGraphStart result %ld %08lX %4.4s\n", (long)result, (long)result, (char*)&result); return; }
    self.isPlaying = YES;
    
}
-(void)enableInput:(NSInteger)busIndex isOn:(BOOL)isOn{
    dispatch_async(_mQueue, ^{
        CheckError(AudioUnitSetParameter(_mMixer, kMultiChannelMixerParam_Enable,
                                         kAudioUnitScope_Input, busIndex,
                                         (AudioUnitParameterValue)isOn, 0),
                   "cant  set kMultiChannelMixerParam_Enable parameter") ;
    });
   
}
-(void)setInputVolumeWithBus:(NSInteger)busIndex value:(CGFloat)value{
    dispatch_async(_mQueue, ^{
    CheckError(AudioUnitSetParameter(_mMixer, kMultiChannelMixerParam_Volume,
                                     kAudioUnitScope_Input, busIndex,
                                     (AudioUnitParameterValue)value, 0),
               "cant  set kMultiChannelMixerParam_Volume parameter in kAudioUnitScope_Input") ;
    });
}
-(void)setOutputVolume:(AudioUnitParameterValue)value{
    dispatch_async(_mQueue, ^{
    CheckError(AudioUnitSetParameter(_mMixer, kMultiChannelMixerParam_Volume,
                                     kAudioUnitScope_Output, 0, value, 0),
               "cant set kMultiChannelMixerParam_Volume parameter in kAudioUnitScope_Output");
    });
}
static OSStatus renderInput(void *inRefCon,
                            AudioUnitRenderActionFlags *ioActionFlags,
                            const AudioTimeStamp *inTimeStamp,
                            UInt32 inBusNumber, UInt32 inNumberFrames,
                            AudioBufferList *ioData)
{
    SoundBufferPtr sndbuf = (SoundBufferPtr)inRefCon;
    
    UInt32 sample = sndbuf[inBusNumber].sampleNum;      // frame number to start from
    UInt32 bufSamples = sndbuf[inBusNumber].numFrames;  // total number of frames in the sound buffer
    Float32 *leftData = sndbuf[inBusNumber].leftData; // audio data buffer
    Float32 *rightData = nullptr;
    
    Float32 *outL = (Float32 *)ioData->mBuffers[0].mData; // output audio buffer for L channel
    Float32 *outR = nullptr;
    if (sndbuf[inBusNumber].channelCount == 2) {
        outR = (Float32 *)ioData->mBuffers[1].mData; //out audio buffer for R channel;
        rightData = sndbuf[inBusNumber].rightData;
    }
   
    for (UInt32 i = 0; i < inNumberFrames; ++i) {
        outL[i] = leftData[sample];
        if (sndbuf[inBusNumber].channelCount == 2) {
            outR[i] = rightData[sample];
        }
        sample++;
        
        if (sample > bufSamples) {
            // start over from the beginning of the data, our audio simply loops
            printf("looping data for bus %d after %ld source frames rendered\n", (unsigned int)inBusNumber, (long)sample-1);
            sample = 0;
        }
    }
    
    sndbuf[inBusNumber].sampleNum = sample; // keep track of where we are in the source data buffer
    
    return noErr;
}
@end
