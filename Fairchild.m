#import "RCTConvert.h"
#import "Fairchild.h"
#import "SDAVAssetExportSession.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import <AVFoundation/AVFoundation.h>
@import MobileCoreServices;
@import ImageIO;
@import Photos;

/* #import <Photos/PHAsset.h> // for testing */

@implementation Fairchild

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

// Set up a queue for this lib's async operations.
- (dispatch_queue_t)methodQueue
{
  return dispatch_queue_create("rn.fairchild", DISPATCH_QUEUE_SERIAL);
}

/* ----------------- */
/* Video Compression */
/* ----------------- */

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
  NSString *orientation              = [outputOptions objectForKey:@"orientation"]; // target orientation of output file
  float startTimeSeconds             = [[outputOptions objectForKey:@"startTimeSeconds"] floatValue];
  float endTimeSeconds               = [[outputOptions objectForKey:@"endTimeSeconds"] floatValue];
  
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
  
  // CGAffineTransform tx = [videoTrack preferredTransform];
  //  int trackRotationDegrees = acos(tx.a) * 180 / M_PI;
  CGSize originalDimensions = videoTrack.naturalSize;
  int rotateDegrees;
  if (originalDimensions.width > originalDimensions.height) {
    if ([orientation isEqualToString:@"portrait"]) {
      rotateDegrees = 90;
    } else {
      rotateDegrees = 0;
    }
  } else {
    if ([orientation isEqualToString:@"portrait"]) {
      rotateDegrees = 0;
    } else {
      rotateDegrees = 90;
    }
  }
  // rotateDegrees = rotateDegrees - (trackRotationDegrees - 90);
  
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
  
  CMTimeRange outputTimeRange = [self outputTimeRange:asset startTimeSeconds:startTimeSeconds endTimeSeconds:endTimeSeconds];
  
  //
  // Video composition operations & compression settings
  
  //
  AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
  videoComposition.frameDuration = CMTimeMake(1, 30);
  videoComposition.renderSize = CGSizeMake(outputDimensions.width, outputDimensions.height);
  AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
  float outputDurationSeconds = CMTimeGetSeconds(outputTimeRange.duration);
  float outputStartSeconds = CMTimeGetSeconds(outputTimeRange.start);
  instruction.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(outputStartSeconds, 30),
                                          CMTimeMakeWithSeconds(outputDurationSeconds + 1, 30));
  AVMutableVideoCompositionLayerInstruction *transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];

  CGAffineTransform finalTransform = [self finalTransform:originalDimensions
                                              outputScale:outputScale
                                            rotateDegrees:rotateDegrees
                                         cropOffsetPixels:cropOffsetPixels];
  [transformer setTransform:finalTransform atTime:outputTimeRange.start];

  instruction.layerInstructions = [NSArray arrayWithObject:transformer];
  videoComposition.instructions = [NSArray arrayWithObject:instruction];
  
  SDAVAssetExportSession *encoder = [[SDAVAssetExportSession alloc] initWithAsset:asset];
  encoder.outputFileType = fileType;
  encoder.outputURL = outputFileURL;
  encoder.shouldOptimizeForNetworkUse = YES;
  encoder.videoComposition = videoComposition;
  encoder.timeRange = outputTimeRange;

  NSDictionary *compressionSettings;
  if (bitRate) {
    if ([videoTrack estimatedDataRate] <= [bitRate floatValue]) {
      compressionSettings = @{};
    } else {
      compressionSettings = @{AVVideoAverageBitRateKey: bitRate};
    }
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
        NSLog(@"Fairchild: deleted original file at %@", inputFileURL);
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

- (CMTimeRange)outputTimeRange:(AVAsset *)asset startTimeSeconds:(float)startTimeSeconds endTimeSeconds:(float)endTimeSeconds
{
  float originalAssetDuration = CMTimeGetSeconds(asset.duration);
  CMTimeScale timeScale = asset.duration.timescale;
  
  // Ensure that start time is in [0, originalAssetDuration - 2 milliseconds) and that
  // end time is in [2 milliseconds, originalAssetDuration].
  float clampedStartTimeSeconds = (startTimeSeconds > originalAssetDuration - 0.02) ? 0 : MIN(MAX(0, startTimeSeconds), originalAssetDuration - 0.002);
  float clampedEndTimeSeconds = (endTimeSeconds < 0) ? originalAssetDuration : MIN(MAX(0.002, endTimeSeconds), originalAssetDuration);
  
  // We use millisecond precision
  CMTime startTime = CMTimeMake(clampedStartTimeSeconds * 1000, 1000);
  CMTime endTime   = CMTimeMake(clampedEndTimeSeconds * 1000, 1000);
  
  return CMTimeRangeMake(startTime, CMTimeSubtract(endTime, startTime));
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
  double outputPixelCount = [[pixelCounts objectForKey:resolution] doubleValue];
  if (outputPixelCount >= inputPixelCount) {
    return 1.0;
  } else {
    return outputPixelCount / inputPixelCount;
  }
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
      outputWidth = originalWidth * outputScale;
      outputHeight = outputWidth;
    }
    // Make sure width and height are multiples of 16 to avoid green borders.
    while (outputWidth % 2 > 0)  { outputWidth++; }
    while (outputHeight % 2 > 0) { outputHeight++; }

  } else {
    if (rotateDegrees == 90 || rotateDegrees == -90) {
      outputHeight = originalWidth * outputScale;
      outputWidth  = originalHeight * outputScale;
    } else {
      outputWidth  = originalWidth * outputScale;
      outputHeight = originalHeight * outputScale;
    }
  }

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

- (CGAffineTransform)finalTransform:(CGSize)originalDimensions
                        outputScale:(double)outputScale
                      rotateDegrees:(int)rotateDegrees
                   cropOffsetPixels:(int)cropOffsetPixels
{
  NSMutableArray *transforms = [[NSMutableArray alloc] init];
  if (outputScale == 1.0) {
    [self addTransform:transforms new:CGAffineTransformIdentity];
  } else {
    [self addTransform:transforms new:CGAffineTransformMakeScale(outputScale, outputScale)];
  }
  int shorterDimensionLength; int longerDimensionLength;
  if (originalDimensions.height < originalDimensions.width) {
    shorterDimensionLength = originalDimensions.height;
    longerDimensionLength  = originalDimensions.width;
  } else {
    shorterDimensionLength = originalDimensions.width;
    longerDimensionLength  = originalDimensions.height;
  }
  if (rotateDegrees) {
    // Convert degrees to radians
    CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(rotateDegrees *  M_PI / 180.0);
    if (rotateDegrees == 90) {
      [self addTransform:transforms new:CGAffineTransformMakeTranslation(shorterDimensionLength, -cropOffsetPixels)];
      [self addTransform:transforms new:rotationTransform];
    } else if (rotateDegrees == -90) {
      [self addTransform:transforms new:rotationTransform];
      [self addTransform:transforms new:CGAffineTransformMakeTranslation(-longerDimensionLength + cropOffsetPixels, 0)];
    }
  } else {
    [self addTransform:transforms new:CGAffineTransformMakeTranslation(0, -cropOffsetPixels)];
  }
  return [self combineTransforms:transforms];
}

// Need to wrap the CGAffineTransform-s in NSValue-s, since NSArray only accepts objects.
- (NSMutableArray *)addTransform:(NSMutableArray *)transforms new:(CGAffineTransform)newTransform
{
  [transforms addObject:[NSValue valueWithBytes:&newTransform objCType:@encode(CGAffineTransform)]];
  return transforms;
}

  // Note: Combines the transforms in reverse/right-associative order
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

/* ----------------- */
/* Thumb Extraction  */
/* ----------------- */

RCT_EXPORT_METHOD(thumbForVideo:(NSString *)inputFilePath
                 outputOptions:(NSDictionary *)outputOptions
                      callback:(RCTResponseSenderBlock)callback)
{
  bool isAsset = [RCTConvert BOOL:[outputOptions objectForKey:@"isAsset"]];
  int width = [[outputOptions objectForKey:@"width"] intValue];
  Float64 thumbTimeRatio = [[outputOptions objectForKey:@"thumbTimeRatio"] floatValue];
  
  NSURL *inputFileURL;
  if (isAsset) {
    inputFileURL = [NSURL URLWithString:inputFilePath];
  } else {
    inputFileURL = [NSURL fileURLWithPath:inputFilePath];
  }
  NSURL *outputFileURL;
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
  outputFileURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
  outputFileURL = [outputFileURL URLByAppendingPathComponent:[@[guid, @"png"] componentsJoinedByString:@"."]];
  
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputFileURL options:nil];
  
  if (!width) {
    // Then we default to a square crop from the top-left of the first video track,
    // according to its naturalSize.
    CGSize originalDimensions = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject].naturalSize;
    width = MIN(originalDimensions.height, originalDimensions.width);
  }
  
  NSValue *thumbTime = [NSValue valueWithCMTime:CMTimeMultiplyByFloat64([asset duration], thumbTimeRatio)];
  
  AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
  imageGenerator.maximumSize = CGSizeMake(width, width);
  
  NSDate *exportStart = [NSDate date];
  
  [imageGenerator generateCGImagesAsynchronouslyForTimes:@[thumbTime]
                                       completionHandler:^(CMTime requestedTime,
                                                           CGImageRef thumb,
                                                           CMTime actualTime,
                                                           AVAssetImageGeneratorResult result,
                                                           NSError * error) {
    NSDate *exportEnd = [NSDate date];
    NSNumber *thumbSize;
    CFURLRef cfurl = (__bridge CFURLRef)outputFileURL;
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(cfurl, kUTTypePNG, 2, NULL);
    CGImageDestinationAddImage(destination, thumb, nil);
    CGImageDestinationFinalize(destination);
    float actualTimeSeconds = CMTimeGetSeconds(actualTime);
                                  
    return callback(@[[NSNull null], @{
      @"uri":               [outputFileURL path],
      @"width":             [NSNumber numberWithInt:width],
      @"actualTimeSeconds": [NSNumber numberWithFloat:actualTimeSeconds]
    }]);
  }];
}

/* ----------------- */
/* Image compression  */
/* ----------------- */

RCT_EXPORT_METHOD(compressImage:(NSString *)inputFilePath
                 outputOptions:(NSDictionary *)outputOptions
                      callback:(RCTResponseSenderBlock)callback)
{
  dispatch_queue_t globalConcurrentQueue =
  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  
  dispatch_async(globalConcurrentQueue, ^{
    float maxPixelCount = 1920.0 * 1080.0; // 720p
    bool isAsset = [RCTConvert BOOL:[outputOptions objectForKey:@"isAsset"]];
    NSURL *inputFileURL;
    if (isAsset) {
      inputFileURL = [NSURL URLWithString:inputFilePath];
    } else {
      inputFileURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:inputFilePath ofType:nil]];
    }
    NSData *imageData = [NSData dataWithContentsOfURL:inputFileURL];
    UIImage *inputImage = [UIImage imageWithData:imageData];
  
    CGSize originalSize = inputImage.size;
    int originalPixelCount = originalSize.width * originalSize.height;
    double outputScale = (originalPixelCount > maxPixelCount) ? maxPixelCount / originalPixelCount : 1.0;
    CGSize outputSize = CGSizeMake((int) (originalSize.width * outputScale), (int) (originalSize.height * outputScale));
    
    UIGraphicsBeginImageContext(outputSize);
    [inputImage drawInRect:CGRectMake(0, 0, outputSize.width, outputSize.height)];
    UIImage *compressedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    NSData *pngData = UIImagePNGRepresentation(compressedImage);
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    NSURL *outputFileURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
    outputFileURL = [outputFileURL URLByAppendingPathComponent:[@[guid, @"png"] componentsJoinedByString:@"."]];
    
    NSError* error;
    [pngData writeToURL:outputFileURL options:0 error:&error];
    
    NSData *outputData = [NSData dataWithContentsOfURL:outputFileURL];
    
    callback(@[[NSNull null], @{
      @"outputFileURI":    [outputFileURL path],
      @"width":  [NSNumber numberWithInt:outputSize.width],
      @"height": [NSNumber numberWithInt:outputSize.height]
    }]);
  });
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

