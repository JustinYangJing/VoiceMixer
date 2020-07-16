# VoiceMixer
Voice Mixer

应一个小伙伴要求，在之前的demo上加入了录音和各路背景音乐混音的效果，可分别设置各路背景音和录音音量的大小，并可以把混音后的音频以ACC编码格式，m4a封装格式输出到沙盒中；我在改写这个需求的时候，想对audio unit直接设置回调，各种配置参数，回调就是不调用；但是另外的写法，不设置AUNode的回调，直接设置mix的audio unit和 remoteIO的audio unit的回调就有效了；跑这个demo时，各位可以直接给remoteIO的audio unit(代码中的_mOutput)设置回调，看是否调用。



[混音代码解析](https://lifestyle1.cn/2017/04/19/iOS%E9%9F%B3%E9%A2%91%E7%BC%96%E7%A8%8B%E4%B9%8B%E6%B7%B7%E9%9F%B3/)

