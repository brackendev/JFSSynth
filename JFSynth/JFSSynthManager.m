//
//  JFSAudioManager.m
//  JFSynth
//
//  Created by John Forester on 10/27/13.
//  Copyright (c) 2013 John Forester. All rights reserved.
//

#import "JFSSynthManager.h"
#import "TheAmazingAudioEngine.h"

typedef NS_ENUM(NSInteger, JFSEnvelopeState) {
    JFSEnvelopeStateNone,
    JFSEnvelopeStateAttack,
    JFSEnvelopeStateSustain,
    JFSEnvelopeStateDecay,
    JFSEnvelopeStateRelease,
};

@interface JFSSynthManager ()

@property (nonatomic, strong) AEAudioController *audioController;
@property (nonatomic, strong) AEBlockChannel *oscillatorChannel;
@property (nonatomic, strong) AEAudioUnitFilter *lpFilter;

@property (nonatomic, assign) double waveLengthInSamples;

@property (nonatomic, assign) Float32 amp;

@property (nonatomic, assign) Float32 attackSlope;
@property (nonatomic, assign) Float32 decaySlope;
@property (nonatomic, assign) Float32 releaseSlope;

@property (nonatomic, assign) JFSEnvelopeState envelopeState;

@end

@implementation JFSSynthManager

#define ENABLE_SYNTH 0

#define SAMPLE_RATE 44100.0
#define VOLUME 0.3

+ (JFSSynthManager *) sharedManager
{
    static dispatch_once_t pred = 0;
    __strong static id _sharedObject = nil;
    
#ifdef ENABLE_SYNTH
    dispatch_once(&pred, ^{
        _sharedObject = [[self alloc] init];
    });
#endif
    
    return _sharedObject;
}

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        _audioController = [[AEAudioController alloc]
                            initWithAudioDescription:[AEAudioController nonInterleavedFloatStereoAudioDescription]
                            inputEnabled:NO];
        
        
        [self setUpAmpEnvelope];
        [self setUpOscillatorChannel];
        
        
        AudioComponentDescription lpFilterComponent = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple,
                                                                                      kAudioUnitType_Effect,
                                                                                      kAudioUnitSubType_LowPassFilter);
        
        NSError *error = nil;
        
        self.lpFilter = [[AEAudioUnitFilter alloc] initWithComponentDescription:lpFilterComponent
                                                                              audioController:_audioController
                                                                                        error:&error];
        if (!self.lpFilter) {
            NSLog(@"filter initialization error %@", [error localizedDescription]);
        }
        
        self.cutoffLevel = 80;
        self.resonanceLevel = 0.0;
        
        AEChannelGroupRef channelGroup = [_audioController createChannelGroup];
        [_audioController addChannels:@[_oscillatorChannel] toChannelGroup:channelGroup];
        [_audioController addFilter:self.lpFilter toChannel:_oscillatorChannel];
        
        [_audioController setAudioSessionCategory:kAudioSessionCategory_SoloAmbientSound];
        
        error = nil;
        
        if (![_audioController start:&error]) {
            NSLog(@"AudioController start error: %@", [error localizedDescription]);
        }
    }
    
    return self;
}

#pragma accessor methods

//TODO set limits

- (void)setMaxMidiVelocity:(Float32)maxMidiVelocity
{
    _maxMidiVelocity = maxMidiVelocity;
    self.attackPeak = 0.4 * pow(maxMidiVelocity/127., 3.);
}

- (void)setAttackTime:(Float32)attackTime
{
    _attackTime = attackTime;
    [self updateAttackSlope];
}

- (void)setDecayTime:(Float32)decayTime
{
    _decayTime = decayTime;
    [self updateDecaySlope];
}

- (void)setSustainLevel:(Float32)sustainLevel
{
    _sustainLevel = 0.4 * pow(sustainLevel/127., 3.);
    
    [self updateDecaySlope];
    [self updateReleaseSlope];
}

- (void)setReleaseTime:(Float32)releaseTime
{
    _releaseTime = releaseTime;
    
    [self updateReleaseSlope];
}

- (void)setCutoffLevel:(Float32)cutoffLevel
{
    _cutoffLevel = cutoffLevel;
    
    Float32 minCuttoff = 10;
    Float32 maxCutoff = (SAMPLE_RATE/2);
    
    AudioUnitSetParameter(self.lpFilter.audioUnit,
                          kLowPassParam_CutoffFrequency,
                          kAudioUnitScope_Global,
                          0,
                          ((cutoffLevel/127) * maxCutoff - minCuttoff) + minCuttoff,
                          0);
}

- (void)setResonanceLevel:(Float32)resonanceLevel
{
    _resonanceLevel = resonanceLevel;
    
    Float32 minResonance = -20.0;
    Float32 maxResonance = 40.0;
    
    AudioUnitSetParameter(self.lpFilter.audioUnit,
                          kLowPassParam_Resonance,
                          kAudioUnitScope_Global,
                          0,
                          ((resonanceLevel/127) * maxResonance - minResonance) + minResonance,
                          0);
}

#pragma setup methods

- (void)setUpAmpEnvelope
{
    self.amp = 0;
    self.maxMidiVelocity = 127;
    
    self.attackTime = 0.0001;
    self.decayTime = 2;
    self.sustainLevel = self.maxMidiVelocity;
    self.releaseTime = 0.9;
}

- (void)setUpOscillatorChannel
{
    __weak JFSSynthManager *weakSelf = self;
    
    __block UInt32 framePosition = 0;
    
    _oscillatorChannel = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
        for (UInt32 i = 0; i < frames; i++) {
            switch (self.envelopeState) {
                case JFSEnvelopeStateAttack:
                    if (weakSelf.amp < weakSelf.attackPeak) {
                        weakSelf.amp += weakSelf.attackSlope;
                    } else {
                        weakSelf.envelopeState = JFSEnvelopeStateDecay;
                    }
                    break;
                case JFSEnvelopeStateDecay:
                    if (weakSelf.amp > weakSelf.sustainLevel) {
                        weakSelf.amp += weakSelf.decaySlope;
                    } else {
                        weakSelf.envelopeState = JFSEnvelopeStateSustain;
                    }
                    break;
                case JFSEnvelopeStateRelease:
                    if (weakSelf.amp > 0.0) {
                        weakSelf.amp += weakSelf.releaseSlope;
                    }
                    break;
                default:
                    break;
            }
            
            Float32 sample;
            
            switch (weakSelf.waveType)
            {
                case JFSSquareWave:
                    if (framePosition < weakSelf.waveLengthInSamples / 2) {
                        sample = FLT_MAX;
                    } else {
                        sample = FLT_MIN;
                    }
                    break;
                case JFSSineWave:
                    sample = (Float32)FLT_MAX * sin(2 * M_PI * (framePosition / weakSelf.waveLengthInSamples));
                    break;
                default:
                    break;
            }
            
            if (self.envelopeState != JFSEnvelopeStateNone) {
                sample *= weakSelf.amp * VOLUME;
                
                ((Float32 *)audio->mBuffers[0].mData)[i] = sample;
                ((Float32 *)audio->mBuffers[1].mData)[i] = sample;
                
                framePosition++;
                
                if (framePosition > weakSelf.waveLengthInSamples) {
                    framePosition -= weakSelf.waveLengthInSamples;
                }
            }
        }
    }];
    
    _oscillatorChannel.audioDescription = [AEAudioController nonInterleavedFloatStereoAudioDescription];
}

- (void)playFrequency:(double)frequency
{
    self.envelopeState = JFSEnvelopeStateAttack;
    
    self.waveLengthInSamples = SAMPLE_RATE / frequency;
    self.amp = 0;
}

- (void)stopPlaying
{
    self.envelopeState = JFSEnvelopeStateRelease;
}

#pragma mark - envelope updates

- (void)updateAttackSlope
{
    self.attackSlope = self.attackPeak / (self.attackTime * SAMPLE_RATE);
}

- (void)updateDecaySlope
{
    self.decaySlope = -(self.attackPeak - self.sustainLevel) / (self.decayTime * SAMPLE_RATE);
}

- (void)updateReleaseSlope
{
    self.releaseSlope = -self.attackPeak / (self.releaseTime * SAMPLE_RATE);
    
}

@end