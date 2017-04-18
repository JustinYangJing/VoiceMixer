//
//  MixerVoiceHandle.h
//  VoiceMixer
//
//  Created by JustinYang on 2017/4/17.
//  Copyright © 2017年 JustinYang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVAudioFormat.h>

#define handleError(error)  if(error){ NSLog(@"%@",error); exit(1);}

extern const double kGraphSampleRate;
extern const double kSessionBufDuration;

void CheckError(OSStatus error,const char *operaton);
@interface MixerVoiceHandle : NSObject

@property (nonatomic,assign) BOOL isPlaying;

-(instancetype)initWithSourceArr:(NSArray *)sourceArr;
-(void)stopAUGraph;
-(void)startAUGraph;

-(void)enableInput:(NSInteger)busIndex isOn:(BOOL)isOn;
-(void)setInputVolumeWithBus:(NSInteger)busIndex value:(CGFloat)value;
-(void)setOutputVolume:(AudioUnitParameterValue)value;
@end
