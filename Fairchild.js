'use strict';

// Currently only supports iOS. Android support is planned for future releases.

// To fix bluebird not finding self
if (typeof self === 'undefined') {
  global.self = global;
}

var Fairchild = require('react-native').NativeModules.Fairchild;

var NativeAppEventEmitter = require('react-native').NativeAppEventEmitter;  // iOS
var Promise = require('bluebird');

var _compressVideo = Promise.promisify(Fairchild.compressVideo);

var compressionError = (err) => {
  console.log('compressionError:', err);
  throw error;
};

var Fairchild = {

  // Supported outputOtions:
  // fileType:      'mov' | 'mp4' (default: same as source)
  // isAsset:       boolean (default: inferred from path prefix)
  // resolution:    '1080p' | '720p' (default) | '480p'
  // cropSquare:    boolean (default: false)
  // bitRate:       integer (default: same as source)
  // rotateDegrees: integer (default: 0)
  compressVideo(inputFilePath, deleteOriginal, outputOptions) {
    if (inputFilePath) {
      var o = outputOptions;
      var ft = o.fileType;
      if (!o.fileType) { ft = extractFileType(inputFilePath); }
      var isAsset = o.isAsset;
      if (isAsset === null || isAsset === undefined) {
        isAsset = inputFilePath.match(/^(assets-library|file):/);
      }
      var opts = {
        fileType:      ft,
        isAsset:       isAsset || false,
        resolution:    o.resolution || '720p',
        cropSquare:    o.cropSquare || false,
        bitRate:       o.bitRate,
        rotateDegrees: o.rotateDegrees || 0,
      };
      return _compressVideo(inputFilePath, !!deleteOriginal, opts)
        .catch(compressionError);
    } else {
      console.error('Error: Fairchild.compressVideo called with blank inputFilePath.');
    }
  }

};

var extractFileType = (inputFilePath) => {
  var segments = inputFilePath.split('.');
  var ft = segments[segments.length - 1].toLowerCase();
  if (ft === 'mp4' || ft === 'mov') {
    return ft;
  } else {
    console.error('Error: Unsupported extension', ft, 'and no fileType provided in outputOptions.');
    return null;
  }
}

module.exports = Fairchild;
