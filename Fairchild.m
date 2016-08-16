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
                  outputOptions:(NSDictionary *)outputOptions
                       callback:(RCTResponseSenderBlock)callback)
{
  //
  // Read options
  //
  bool keepOriginal = [RCTConvert BOOL:[outputOptions objectForKey:@"keepOriginal"]];
  bool isAsset      = [RCTConvert BOOL:[outputOptions objectForKey:@"isAsset"]];
  bool cropSquare   = [RCTConvert BOOL:[outputOptions objectForKey:@"cropSquare"]];
  NSString *outputExtension          = [outputOptions objectForKey:@"fileType"];
  NSString *resolution               = [outputOptions objectForKey:@"resolution"];
  NSNumber *bitRate                  = [outputOptions objectForKey:@"bitRate"];
  NSNumber *cropSquareVerticalOffset = [outputOptions objectForKey:@"cropSquareVerticalOffset"];
  int rotateDegrees                  = [[outputOptions objectForKey:@"rotateDegrees"] intValue];
  
  if (!outputExtension) { outputExtension = @"mov"; }

  bool skipCompression = !resolution && !bitRate;

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
  NSString *fileType = [self videoOutputFileType:outputExtension];

  NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
  outputFileURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
  outputFileURL = [outputFileURL URLByAppendingPathComponent:[@[guid, outputExtension] componentsJoinedByString:@"."]];

  NSFileManager *fileManager = [NSFileManager defaultManager];

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputFileURL options:nil];
  
  // 
  // Calculate output dimensions
  //
  NSNumber *originalSize = [self fileSize:asset];
  AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
  CGSize originalDimensions = videoTrack.naturalSize;
  CGSize outputDimensions;
  double outputScale;
  
  if (resolution) {
    outputScale = [self outputScaleForResolution:resolution
                                 inputPixelCount:(originalDimensions.width * originalDimensions.height)];
  } else {
    outputScale = 1.0;
  }
  outputDimensions = [self outputDimensions:originalDimensions
                                outputScale:outputScale rotateDegrees:rotateDegrees
                                 cropSquare:cropSquare];
  int cropOffsetPixels;
  if (cropSquare) {
    cropOffsetPixels = [self cropOffsetPixels:originalDimensions
                     cropSquareVerticalOffset:cropSquareVerticalOffset
                                rotateDegrees:rotateDegrees];
  } else {
    cropOffsetPixels = 0;
  }
  
  NSLog(@"original dimensions: width %f, height %f", originalDimensions.width, originalDimensions.height);
  NSLog(@"output dimensions: width %f, height %f", outputDimensions.width, outputDimensions.height);
  
  //
  // Video composition operations & compression settings
  //
  AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
  videoComposition.frameDuration = CMTimeMake(1, 30);
  videoComposition.renderSize = CGSizeMake(outputDimensions.width, outputDimensions.height);
  AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
  float duration = CMTimeGetSeconds(asset.duration);
  NSLog(@"duration %f", duration);
  instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(duration + 1, 30));
  AVMutableVideoCompositionLayerInstruction *transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];

  // Configure transforms
  // Note: combineTransforms combines the transforms in reverse/right-associative order

  NSMutableArray *transforms = [[NSMutableArray alloc] init];
  if (outputScale == 1.0) {
    [self addTransform:transforms new:CGAffineTransformIdentity];
  } else {
    [self addTransform:transforms new:CGAffineTransformMakeScale(outputScale, outputScale)];
  }
  if (rotateDegrees) {
    // Convert degrees to radians
    CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(rotateDegrees *  M_PI / 180.0);
    int shorterDimensionLength; int longerDimensionLength;
    if (originalDimensions.height < originalDimensions.width) {
      shorterDimensionLength = originalDimensions.height;
      longerDimensionLength  = originalDimensions.width;
    } else {
      shorterDimensionLength = originalDimensions.width;
      longerDimensionLength  = originalDimensions.height;
    }
    if (rotateDegrees == 90) {
      [self addTransform:transforms new:CGAffineTransformMakeTranslation(shorterDimensionLength, -cropOffsetPixels)];
      [self addTransform:transforms new:rotationTransform];
    } else if (rotateDegrees == -90) {
      [self addTransform:transforms new:rotationTransform];
      [self addTransform:transforms new:CGAffineTransformMakeTranslation(-longerDimensionLength + cropOffsetPixels, 0)];
    }
  } else {
    [self addTransform:transforms new:CGAffineTransformMakeTranslation(-cropOffsetPixels, 0)];
  }
  CGAffineTransform finalTransform = [self combineTransforms:transforms];
  [transformer setTransform:finalTransform atTime:kCMTimeZero];

  // END

  instruction.layerInstructions = [NSArray arrayWithObject:transformer];
  videoComposition.instructions = [NSArray arrayWithObject:instruction];
  
  SDAVAssetExportSession *encoder = [[SDAVAssetExportSession alloc] initWithAsset:asset];
  encoder.outputFileType = fileType;
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
    AVVideoWidthKey:  [NSNumber numberWithInt:outputDimensions.width],
    AVVideoHeightKey: [NSNumber numberWithInt:outputDimensions.height],
    AVVideoCompressionPropertiesKey: compressionSettings
  };

  encoder.audioSettings = @
  {
    AVFormatIDKey: @(kAudioFormatMPEG4AAC),
    AVNumberOfChannelsKey: @1,
    AVSampleRateKey: @44100,
    AVEncoderBitRateKey: @128000,
  };
  
  NSDate *exportStart = [NSDate date];
  //
  // Perform the export
  //
  [encoder exportAsynchronouslyWithCompletionHandler:^
  {
    if (encoder.status == AVAssetExportSessionStatusCompleted)
    {
      NSDate *exportEnd = [NSDate date];
       AVAsset *compressedAsset = [AVURLAsset URLAssetWithURL:outputFileURL options:nil];
       NSNumber *compressedSize = [self fileSize:compressedAsset];
       if (!keepOriginal) {
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
      NSLog(@"execution time %f seconds", [exportEnd timeIntervalSinceDate:exportStart]);
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

- (CGSize)outputDimensions:(CGSize)originalDimensions
                       outputScale:(double)outputScale
                     rotateDegrees:(int)rotateDegrees
                        cropSquare:(bool)cropSquare
{
  int originalWidth  = originalDimensions.width;
  int originalHeight = originalDimensions.height;
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

  return CGSizeMake(outputWidth, outputHeight);
}

- (int)cropOffsetPixels:(CGSize)originalDimensions
cropSquareVerticalOffset:(NSNumber *)cropSquareVerticalOffset
           rotateDegrees:(int)rotateDegrees
{
  if (rotateDegrees == 90 || rotateDegrees == -90) {
    if (originalDimensions.width < originalDimensions.height) {
      // We only want to crop along the longer dimension, so this case becomes a no-op.
      return 0;
    } else {
      return [cropSquareVerticalOffset floatValue] * originalDimensions.width;
    }
  } else {
    if (originalDimensions.width > originalDimensions.height) {
      return 0;
    } else {
      return [cropSquareVerticalOffset floatValue] * originalDimensions.height;
    }
  }
}

// Need to wrap the CGAffineTransform-s in NSValue-s, since NSArray only accepts objects.
- (NSMutableArray *)addTransform:(NSMutableArray *)transforms new:(CGAffineTransform)newTransform
{
  [transforms addObject:[NSValue valueWithBytes:&newTransform objCType:@encode(CGAffineTransform)]];
  return transforms;
}

- (CGAffineTransform)combineTransforms:(NSMutableArray *)transforms
{
  int count = [transforms count];
  CGAffineTransform t;
  [[transforms objectAtIndex:(count-1)] getValue:&t];
  if (count == 1) {
    return t;
  }
  CGAffineTransform t_next;
  for (int i = count-2; i >= 0; i--) {
    [[transforms objectAtIndex:i] getValue:&t_next];
    t = CGAffineTransformConcat(t, t_next);
  }
  return t;
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

