#import "RCTConvert.h"
#import "SDAVAssetExportSession.h"
#import "Fairchild.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import <AVFoundation/AVFoundation.h>

/* #import <Photos/PHAsset.h> // for testing */

@implementation Fairchild

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

// Set up a queue for this lib's async operations.
- (dispatch_queue_t)methodQueue
{
  return dispatch_queue_create("rn.fairchild", DISPATCH_QUEUE_SERIAL);
}

RCT_EXPORT_METHOD(compressVideo:(NSString *)inputFilePath
                 deleteOriginal:(BOOL)deleteOriginal
                  outputOptions:(NSDictionary *)outputOptions
                       callback:(RCTResponseSenderBlock)callback)
{
  //
  // Read options
  //
  bool isAsset    = [RCTConvert BOOL:[outputOptions objectForKey:@"isAsset"]];
  bool cropSquare = [RCTConvert BOOL:[outputOptions objectForKey:@"cropSquare"]];
  NSString *outputExtension = [outputOptions objectForKey:@"fileType"];
  NSString *resolution      = [outputOptions objectForKey:@"resolution"];
  NSNumber *bitRate         = [outputOptions objectForKey:@"bitRate"];
  int rotateDegrees         = [[outputOptions objectForKey:@"rotateDegrees"] intValue];

  //
  // Set up input & output files
  //
  NSURL *inputFileURL;
  if (isAsset) {
    inputFileURL = [NSURL URLWithString:inputFilePath];
  } else {
    inputFileURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:inputFilePath ofType:nil]];
  }
  NSURL *outputFileURL;

  NSString *extension = [inputFileURL pathExtension];
  /* NSString *fileType = [self videoOutputFileType:extension]; */
  NSString *fileType = [self videoOutputFileType:@"mp4"];

  NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
  outputFileURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
  outputFileURL = [outputFileURL URLByAppendingPathComponent:[@[guid, extension] componentsJoinedByString:@"."]];

  NSFileManager *fileManager = [NSFileManager defaultManager];

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputFileURL options:nil];
  
  // 
  // Calculate output dimensions
  //
  NSNumber *originalSize = [self fileSize:asset];
  AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
  CGSize originalDimensions = videoTrack.naturalSize;
  int originalWidth  = originalDimensions.width;
  int originalHeight = originalDimensions.height;

  double outputScale = [self outputScaleForResolution:resolution inputPixelCount:(originalWidth * originalHeight)];

  int outputWidth; int outputHeight;
  if (cropSquare) {
    // width (= height) should be the smaller of the two (and scaled).
    if (originalHeight < originalWidth) {
      outputHeight = originalHeight * outputScale;
      outputWidth = outputHeight;
    } else {
      outputWidth = outputWidth * outputScale;
      outputHeight = outputWidth;
    }
  } else {
    if (rotateDegrees == 90 || rotateDegrees == -90) {
      outputHeight = originalWidth * outputScale;
      outputWidth  = originalHeight * outputScale;
    } else {
      outputWidth  = originalWidth * outputScale;
      outputHeight = originalHeight * outputScale;
    }
  }

  // Make sure width and height are multiples of 16 to avoid green borders.
  while (outputWidth % 16 > 0)  { outputWidth++; }
  while (outputHeight % 16 > 0) { outputHeight++; }

  NSLog(@"original: width %i, height %i", originalWidth, originalHeight);
  NSLog(@"output: width %i, height %i", outputWidth, outputHeight);
  
  //
  // Video composition operations & compression settings
  //
  AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
  videoComposition.frameDuration = CMTimeMake(1, 30);
  videoComposition.renderSize = CGSizeMake(outputWidth, outputHeight);
  AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
  float duration = CMTimeGetSeconds(asset.duration);
  NSLog(@"duration %f", duration);
  instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(duration + 1, 30));
  AVMutableVideoCompositionLayerInstruction *transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];

  CGAffineTransform t1; CGAffineTransform t2; CGAffineTransform finalTransform;
  if (outputScale == 1.0) {
    t1 = CGAffineTransformIdentity;
  } else {
    t1 = CGAffineTransformMakeScale(outputScale, outputScale);
  }
  if (rotateDegrees) {
    int translation = originalHeight < originalWidth ? originalHeight : originalWidth;
    if (rotateDegrees == 90) {
      t2 = CGAffineTransformTranslate(t1, translation, 0);
    } else if (rotateDegrees == -90) {
      t2 = CGAffineTransformTranslate(t1, 0, translation);
    }
    finalTransform = CGAffineTransformRotate(t2, rotateDegrees * M_PI / 180.0); // convert degrees to radians
  } else {
    finalTransform = t1;
  }
  [transformer setTransform:finalTransform atTime:kCMTimeZero];
  instruction.layerInstructions = [NSArray arrayWithObject:transformer];
  videoComposition.instructions = [NSArray arrayWithObject:instruction];
  
  SDAVAssetExportSession *encoder = [[SDAVAssetExportSession alloc] initWithAsset:asset];
  encoder.outputFileType = fileType;
  /* encoder.outputFileType = AVFileTypeQuickTimeMovie; */
  encoder.outputURL = outputFileURL;
  encoder.shouldOptimizeForNetworkUse = YES;
  encoder.videoComposition = videoComposition;

  NSDictionary *compressionSettings;
  if (bitRate) {
    compressionSettings = @{AVVideoAverageBitRateKey: bitRate};
  } else {
    compressionSettings = @{};
  }

  encoder.videoSettings = @
  {
    AVVideoCodecKey: AVVideoCodecH264,
    AVVideoWidthKey:  [NSNumber numberWithInt:outputWidth],
    AVVideoHeightKey: [NSNumber numberWithInt:outputHeight],
    AVVideoCompressionPropertiesKey: compressionSettings
  };

  encoder.audioSettings = @
  {
    AVFormatIDKey: @(kAudioFormatMPEG4AAC),
    AVNumberOfChannelsKey: @1,
    AVSampleRateKey: @44100,
    AVEncoderBitRateKey: @128000,
  };
  
  //
  // Perform the export
  //
  [encoder exportAsynchronouslyWithCompletionHandler:^
  {
    if (encoder.status == AVAssetExportSessionStatusCompleted)
    {
       AVAsset *compressedAsset = [AVURLAsset URLAssetWithURL:outputFileURL options:nil];
       NSNumber *compressedSize = [self fileSize:compressedAsset];
       if (deleteOriginal) {
         NSError *deleteError = nil;
         [fileManager removeItemAtURL:inputFileURL error:&deleteError];
         if (deleteError) {
           NSLog(@"Fairchild: error while deleting original %@", deleteError);
         }
       }
       NSNumber *compressionRatio;
       if ([originalSize floatValue] > 0) {
         compressionRatio = [NSNumber numberWithFloat:(1.0 - ([compressedSize floatValue] / [originalSize floatValue]))];
       } else {
         compressionRatio = @(0);
       }
      
      AVAssetTrack *firstCompressedVideoTrack = [[compressedAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
      CGSize originalDimensions = firstCompressedVideoTrack.naturalSize;
      int compressedWidth  = originalDimensions.width;
      int compressedHeight = originalDimensions.height;
      
      NSLog(@"----------------------");
      NSLog(@"compression complete");
      NSLog(@"compression ratio %@", compressionRatio);
      NSLog(@"original size %@", originalSize);
      NSLog(@"compressed size %@", compressedSize);
      NSLog(@"compressed dimensions: width %i, height %i", compressedWidth, compressedHeight);
      NSLog(@"----------------------");
      return callback(@[[NSNull null], @{
         @"outputFileURI":       [outputFileURL path],
         @"inputFileSizeBytes":  originalSize,
         @"outputFileSizeBytes": compressedSize,
         @"compressionRatio" :   compressionRatio
       }]);
    }
    else if (encoder.status == AVAssetExportSessionStatusCancelled)
    {
      NSLog(@"Video export cancelled, error: %@", encoder.error);
    }
    else
    {
      NSLog(@"Video export failed with error: %@ (%d)", encoder.error.localizedDescription, encoder.error.code);
    }
  }];
}

- (NSString *)videoCompressionPreset:(NSNumber *)quality
{
  NSDictionary *presets = @{
    @1: AVAssetExportPresetLowQuality,
    @2: AVAssetExportPresetMediumQuality,
    @3: AVAssetExportPreset640x480,
    @4: AVAssetExportPreset960x540,
    @5: AVAssetExportPresetHighestQuality
  };
  return [presets objectForKey:quality];
}

- (NSString *)videoOutputFileType:(NSString *)extension
{
  NSDictionary *fileTypes = @{
    @"mp4":  AVFileTypeMPEG4,
    @"mov":  AVFileTypeQuickTimeMovie
  };
  return [fileTypes objectForKey:extension];
}

- (double)outputScaleForResolution:(NSString *)resolution inputPixelCount:(int)inputPixelCount
{
  NSDictionary *pixelCounts = @{
    @"480p":  @(640.0 * 480.0),
    @"720p":  @(1080.0 * 720.0),
    @"1080p": @(1920.0 * 1080.0)
  };
  return [[pixelCounts objectForKey:resolution] doubleValue] / inputPixelCount;
}

- (NSNumber *)fileSize:(AVAsset *)asset
{
  NSArray *tracks = [asset tracks];
  float estimatedBytes = 0.0 ;
  for (AVAssetTrack * track in tracks) {
          float rate = ([track estimatedDataRate] / 8); // convert bits per second to bytes per second
          float seconds = CMTimeGetSeconds([track timeRange].duration);
          estimatedBytes += seconds * rate;
  }
  return [NSNumber numberWithFloat:estimatedBytes];
}

- (NSDictionary *)constantsToExport
{
  return @{
    @"MainBundlePath": [[NSBundle mainBundle] bundlePath],
    @"NSFileTypeRegular": NSFileTypeRegular,
    @"NSFileTypeDirectory": NSFileTypeDirectory
  };
}

@end

