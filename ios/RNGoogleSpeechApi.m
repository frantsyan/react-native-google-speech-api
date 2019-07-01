// DO NOT something to effect to global AVAudioSession like setCategory.
// It is highly recommended to do this in JS to avoid conflict with other native modules.

#import <AVFoundation/AVFoundation.h>

#import "RNGoogleSpeechApi.h"
#import "AudioController.h"
#import "SpeechRecognitionService.h"
#import "google/cloud/speech/v1/CloudSpeech.pbrpc.h"

#define SAMPLE_RATE 16000.0f

@interface RNGoogleSpeechApi () <AVAudioRecorderDelegate, AVAudioPlayerDelegate, AudioControllerDelegate>

@property (strong, nonatomic) AVAudioRecorder *audioRecorder;
@property (strong, nonatomic) AVAudioSession *audioSession;
@property (strong, nonatomic) NSString *apiKey;
@property (nonatomic, strong) NSMutableData *audioData;

@end

@implementation RNGoogleSpeechApi

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"onSpeechToTextCustom"];
}

- (NSString *) soundFilePath {
    NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = dirPaths[0];
    return [docsDir stringByAppendingPathComponent:@"sound.caf"];
}

RCT_EXPORT_METHOD(setApiKey:(NSString *)apiKey) {
    _apiKey = apiKey;
}

RCT_EXPORT_METHOD(startSpeech) {
//    _audioSession = [AVAudioSession sharedInstance];
//    [_audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
//    [_audioRecorder record];
    [AudioController sharedInstance].delegate = self;
    _audioSession = [AVAudioSession sharedInstance];
    [_audioSession setCategory:AVAudioSessionCategoryRecord error:nil];
    
    _audioData = [[NSMutableData alloc] init];
    [[AudioController sharedInstance] prepareWithSampleRate:SAMPLE_RATE];
    [[SpeechRecognitionService sharedInstance] setSampleRate:SAMPLE_RATE];
    [[SpeechRecognitionService sharedInstance] setApiKey:_apiKey];
    [[AudioController sharedInstance] start];
}

- (IBAction)stopAudio:(id)sender {
    [[AudioController sharedInstance] stop];
    [[SpeechRecognitionService sharedInstance] stopStreaming];
    [_audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
}

- (void) processSampleData:(NSData *)data
{
    [self.audioData appendData:data];
    NSInteger frameCount = [data length] / 2;
    int16_t *samples = (int16_t *) [data bytes];
    int64_t sum = 0;
    for (int i = 0; i < frameCount; i++) {
        sum += abs(samples[i]);
    }
    
    // We recommend sending samples in 100ms chunks
    int chunk_size = 0.1 /* seconds/chunk */ * SAMPLE_RATE * 2 /* bytes/sample */ ; /* bytes/chunk */
    
    if ([self.audioData length] > chunk_size) {
        [[SpeechRecognitionService sharedInstance] streamAudioData:self.audioData
                                                    withCompletion:^(StreamingRecognizeResponse *response, NSError *error) {
                                                        if (error) {
                                                            [self sendEventWithName:@"onSpeechToTextCustom" body:@{@"text": @"", @"isFinal":@(YES)}];
                                                            [self stopAudio:nil];
                                                        } else if (response) {
                                                            BOOL finished = NO;
                                                            for (StreamingRecognitionResult *result in response.resultsArray) {
                                                                if (result.isFinal) {
                                                                    finished = YES;
                                                                }
                                                            }
                                                            [self sendEventWithName:@"onSpeechToTextCustom" body:@{@"text": response.resultsArray[0].alternativesArray[0].transcript, @"isFinal":@(finished)}];
                                                            if (finished) {
                                                                [self stopAudio:nil];
                                                            }
                                                        }
                                                    }
         ];
        self.audioData = [[NSMutableData alloc] init];
    }
}

RCT_EXPORT_METHOD(cancelSpeech) {
    [self stopAudio:nil];
}

@end
