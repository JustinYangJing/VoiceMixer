//
//  ViewController.m
//  VoiceMixer
//
//  Created by JustinYang on 2017/4/17.
//  Copyright © 2017年 JustinYang. All rights reserved.
//

#import "ViewController.h"
#import "MixerVoiceHandle.h"
@interface ViewController ()
@property (nonatomic,strong) MixerVoiceHandle *mixerHandle;

@property (weak, nonatomic) IBOutlet UISlider *mixVolume;
@property (weak, nonatomic) IBOutlet UISwitch *bus0Swith;
@property (weak, nonatomic) IBOutlet UISwitch *bu1Switch;
@property (weak, nonatomic) IBOutlet UISwitch *bus2Switch;
@property (weak, nonatomic) IBOutlet UISwitch *bus3Switch;
@property (weak, nonatomic) IBOutlet UISlider *bus0Volume;
@property (weak, nonatomic) IBOutlet UISlider *bus1Volume;
@property (weak, nonatomic) IBOutlet UISlider *bus2Volume;
@property (weak, nonatomic) IBOutlet UISlider *bus3Volume;
@property (weak, nonatomic) IBOutlet UISwitch *bus4Switch;
@property (weak, nonatomic) IBOutlet UISlider *bus4Volume;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    NSString *sourceA = [[NSBundle mainBundle] pathForResource:@"GuitarMonoSTP" ofType:@"aif"];
    NSString *sourceB = [[NSBundle mainBundle] pathForResource:@"DrumsMonoSTP" ofType:@"aif"];
    NSString *sourceC = [[NSBundle mainBundle] pathForResource:@"guitarStereo" ofType:@"caf"];
    NSString *sourceD = [[NSBundle mainBundle] pathForResource:@"sound_voices" ofType:@"wav"];
    
    NSArray *arr = @[sourceA,sourceB,sourceC,sourceD];
    self.mixerHandle = [[MixerVoiceHandle alloc] initWithSourceArr:arr];
    
    [self.mixerHandle enableInput:0 isOn:self.bus0Swith.isOn];
    [self.mixerHandle enableInput:1 isOn:self.bu1Switch.isOn];
    [self.mixerHandle enableInput:2 isOn:self.bus2Switch.isOn];
    [self.mixerHandle enableInput:3 isOn:self.bus3Switch.isOn];
    [self.mixerHandle enableInput:4 isOn:self.bus4Switch.isOn];
    [self.mixerHandle setInputVolumeWithBus:0 value:self.bus0Volume.value];
    [self.mixerHandle setInputVolumeWithBus:1 value:self.bus1Volume.value];
    [self.mixerHandle setInputVolumeWithBus:2 value:self.bus2Volume.value];
    [self.mixerHandle setInputVolumeWithBus:3 value:self.bus3Volume.value];
    [self.mixerHandle setInputVolumeWithBus:4 value:self.bus4Volume.value];
    [self.mixerHandle setOutputVolume:self.mixVolume.value];
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)playHandle:(UIButton *)sender {
    if (self.mixerHandle.isPlaying) {
        [self.mixerHandle stopAUGraph];
        sender.selected = NO;
    }else{
        [self.mixerHandle startAUGraph];
        sender.selected = YES;
    }
}
- (IBAction)volumeHandle:(UISlider *)sender {
    [self.mixerHandle setOutputVolume:self.mixVolume.value];
    
}
- (IBAction)busEnableHandle:(UISwitch *)sender {
    NSInteger bus = sender.tag;
    [self.mixerHandle enableInput:bus isOn:sender.isOn];
    if(0 == bus ) self.bus0Volume.enabled = sender.isOn;
    if(1 == bus ) self.bus1Volume.enabled = sender.isOn;
    if(2 == bus ) self.bus2Volume.enabled = sender.isOn;
    if(3 == bus ) self.bus3Volume.enabled = sender.isOn;
    if (4 == bus) self.bus4Volume.enabled = sender.isOn;
}

- (IBAction)busVolumeHandle:(UISlider *)sender {
    [self.mixerHandle setInputVolumeWithBus:sender.tag value:sender.value];
}
- (IBAction)recordMixed:(UIButton *)sender {
    if (sender.selected) {
        sender.selected = NO;
        [self.mixerHandle stopWriteMixedPCM];
    }else{
        sender.selected = YES;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.mixerHandle startWriteMixedPCM];
        });
    }
}

@end
