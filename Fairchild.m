#import "RCTConvert.h"
#import "Fairchild.h"
#import "SDAVAssetExportSession.h"
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
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
  outputFileURL = [NSURL fileURLWithPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
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
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(cfurl, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, thumb, nil);
    BOOL writeSuccessful = CGImageDestinationFinalize(destination);
    float actualTimeSeconds = CMTimeGetSeconds(actualTime);
    if (error) {
      NSLog(@"Fairchild - Error during thumb extraction: %@", error);
    }
                                         
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

