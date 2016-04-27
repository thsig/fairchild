# fairchild
Media compression and transformation native module for React Native. Named after the Fairchild 670 audio compressor.

![Fairchild banner](http://i.imgur.com/jduiG6v.jpg)

Currently iOS only. Early-stage but functional — contributions welcome!

## Description
This is a utility library for compression, cropping, rotation and other such operations on audio-visual media.

Currently, it accomplishes compression, rotation and square cropping via a single function (`compressVideo`) and its options, but the plan is to add more functions and operations to the library as needed.

The  idea is that libraries for uses such as these should provide specific, composeable operations to avoid burdening libraries such as [react-native-camera](https://github.com/lwansbrough/react-native-camera) with functionality that would be better be developed separately.

## Installation
Add the following line to your `package.json` (coming soon to npm!):
```javascript
"fairchild": "git+https://github.com/thsig/fairchild.git"
```

Then, similarly to **react-native-camera** — add the Fairchild XCode project from `node_modules/fairchild` to XCode, then add `libFairchild.a` to the **Link Library With Binaries** step under **Build Settings** for the main project.

## Usage
Fairchild is Promise-based, so it's easy to chain it with other operations.

Here's an example of using Fairchild in conjunction with **react-native-camera** to compress video files before persisting them to the server:
```javascript
var compressionOptions = {
  resolution: '720p',
  bitRate: 5 * 1000 * 1024,
  cropSquare: true,
  rotateDegrees: 90
};

this.refs.camera.capture()
  .then((uri) => Fairchild.compressVideo(uri, compressionOptions).outputFileURI; })
  .then(((compressedUri) => this.persistVideo(compressedUri))); // e.g. upload file to server
```

## Static methods
### `compressVideo(inputFilePath, outputOptions)`
`inputFilePath` should be a (string) path to the video file on the local device, such as those generated by `react-native-camera`.

Output is an object of the form:
```javascript
{
  outputFileUri,      // path to the compressed/processed file
  inputFileSizeBytes, // these other three are just diagnostic/informational output
  outputFileSizeBytes,
  compressionRatio
}
```

The following settings are currently supported in `outputOptions`:
##### `keepOriginal - true | false (default)`
When false, deletes the file at `inputFilePath` after the output file has been written. When true, does not delete it.
##### `fileType - 'mov' | 'mp4'`
Default: Same as source. The desired output filetype.
##### `isAsset - true | false`
Default: Inferred from path prefix. Indicates whether the file at `inputFilePath` is to be treated as a bundled asset (e.g. included in the XCode project). Should be `false` for most real-world use cases.
##### `resolution - '1080p' | '720p' (default) | '480p'`
The desired output resolution. In future versions, more fine-grained control over the output resolution will be implemented.

By default, the height and width of the output file are scaled according to the ratio

`(number of output pixels) / (input height * input width)`,

where the number of output pixels is `1920 * 1080`, `1280 * 720` or `640 * 480`, respectively.

The other case is when `cropSquare` is set to `true`. In that case, the ratio becomes

`(number of output pixels) / (w * w)`,

where `w = min(input height, input width)`.
##### `cropSquare - true | false (default)`
When true, the output file is cropped to a square aspect ratio such that its width and height are equal to `min(height, width)`, starting the crop from the top left corner of the original file.
##### `bitRate - integer`
Default: Same as source file. Indicates the average bitrate to be used for the output file.
##### `rotateDegrees: 0 (default) || 90 || -90 || 180`
When not 0, rotates the output file by `rotateDegrees` degrees.
