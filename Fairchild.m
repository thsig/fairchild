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
                        options:(NSDictionary *)options
                       callback:(RCTResponseSenderBlock)callback)
{
  NSURL *inputFileURL = [NSURL fileURLWithPath:inputFilePath];
  NSURL *outputFileURL;

  NSString *extension = [inputFileURL pathExtension];
  NSString *fileType = [self videoOutputFileType:extension];

  NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
  outputFileURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
  outputFileURL = [outputFileURL URLByAppendingPathComponent:[@[guid, extension] componentsJoinedByString:@"."]];

  NSFileManager *fileManager = [NSFileManager defaultManager];

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputFileURL options:nil];
  
  NSNumber *preset = [options objectForKey:@"quality"];
  NSString *presetName;
  if (preset) {
    presetName = [self videoCompressionPreset:preset];
  } else {
    presetName = [self videoCompressionPreset:@3];
  }

  NSNumber *originalSize = [self fileSize:asset];

  AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:asset
                                                                          presetName:presetName];
  exportSession.outputURL = outputFileURL;
  exportSession.outputFileType = fileType;

  [exportSession exportAsynchronouslyWithCompletionHandler:^(void)
   {
     AVAsset *compressedAsset = [AVURLAsset URLAssetWithURL:outputFileURL options:nil];
     NSNumber *compressedSize = [self fileSize:compressedAsset];

     if (exportSession.error) {
       NSLog(@"Fairchild: exportSession error %@", exportSession.error);
     }

    NSError *deleteError = nil;

     if (deleteOriginal) {
       [fileManager removeItemAtURL:inputFileURL error:&deleteError];
       if (deleteError) {
         NSLog(@"Fairchild: error while deleting original %@", deleteError);
       }
     }
     NSNumber *compressionRatio;
     if ([originalSize floatValue] > 0) {
       compressionRatio = [NSNumber numberWithFloat:(1.0 - ([compressedSize floatValue] / [originalSize floatValue]))];
     } else {
       compressionRatio = 0;
     }
     return callback(@[[NSNull null], @{
         @"outputFileURI":       [outputFileURL path],
         @"inputFileSizeBytes":  originalSize,
         @"outputFileSizeBytes": compressedSize,
         @"compressionRatio" :   compressionRatio
       }]);
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
