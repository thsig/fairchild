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
  // keepOriginal:  boolean (default: false)
  // fileType:      'mov' | 'mp4' (default: same as source)
  // isAsset:       boolean (default: inferred from path prefix)
  // resolution:    '1080p' | '720p' (default) | '480p'
  // cropSquare:    boolean (default: false)
  // cropSquareVerticalOffset : number from 0.0 to 1.0 (default: 0.0)
  // bitRate:       integer (default: same as source)
  // rotateDegrees: integer (default: 0)
  compressVideo(inputFilePath, outputOptions) {
    if (inputFilePath) {
      if (inputFilePath.match(/^\//)) {
        inputFilePath = `file://${inputFilePath}`;
      }
      var o = outputOptions;
      var ft = o.fileType;
      if (!o.fileType) { ft = extractFileType(inputFilePath); }
      var isAsset = o.isAsset;
      if (isAsset === null || isAsset === undefined) {
        isAsset = !!inputFilePath.match(/^(assets-library|file):/);
      }
      var vo = o.cropSquareVerticalOffset || 0;
      if (vo) {
        if (vo > 1.0) { vo = 1.0; }
        if (vo < 0.0) { vo = 0.0; }
      }
      var opts = {
        fileType:      ft,
        keepOriginal:  o.keepOriginal || false,
        isAsset:       isAsset || false,
        resolution:    o.resolution,
        cropSquare:    o.cropSquare || false,
        cropSquareVerticalOffset: vo,
        bitRate:       o.bitRate,
        rotateDegrees: o.rotateDegrees || 0,
      };
      return _compressVideo(inputFilePath, opts)
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
