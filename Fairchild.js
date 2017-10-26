'use strict';

// Currently only supports iOS. Android support is planned for future releases.

// To fix bluebird not finding self
if (typeof self === 'undefined') {
  global.self = global;
}

var Fairchild = require('react-native').NativeModules.Fairchild;

var NativeAppEventEmitter = require('react-native').NativeAppEventEmitter;  // iOS
var Promise = require('bluebird');

var _thumbForVideo = Promise.promisify(Fairchild.thumbForVideo);
var _compressImage = Promise.promisify(Fairchild.compressImage);

var compressionError = (err) => {
  console.log('compressionError:', err);
  throw error;
};

var Fairchild = {

  // Currently always returns a square thumb, starting from the top left.
  //
  // Supported outputOptions
  //
  // width:          integer (default: same as source)
  // thumbTimeRatio: float (default: 0.0)
  // isAsset:        boolean (default: inferred from path prefix)
  thumbForVideo(inputFilePath, outputOptions = {}) {
    if (inputFilePath) {
      if (inputFilePath.match(/^\//)) {
        inputFilePath = `file://${inputFilePath}`;
      }
      var o = outputOptions;
      var isAsset = o.isAsset;
      if (isAsset === null || isAsset === undefined) {
        isAsset = !!inputFilePath.match(/^(assets-library|file):/);
      }
      var thumbTimeRatio = Math.min(o.thumbTimeRatio || 0.0, 1.0);
      var opts = {
        isAsset:        isAsset || false,
        width:          o.width || 0,
        thumbTimeRatio: thumbTimeRatio
      };
      return _thumbForVideo(inputFilePath, opts);
    } else {
      console.error('Error: Fairchild.extractThumb called with blank inputFilePath.');
    }
  },

  compressImage(inputFilePath, outputOptions = {}) {
    if (inputFilePath) {
      if (inputFilePath.match(/^\//)) {
        inputFilePath = `file://${inputFilePath}`;
      }
      var o = outputOptions;
      var isAsset = o.isAsset;
      if (isAsset === null || isAsset === undefined) {
        isAsset = !!inputFilePath.match(/^(assets-library|file):/);
      }
      var opts = {
        isAsset: isAsset,
        keepOriginal: o.keepOriginal
      };
      return _compressImage(inputFilePath, opts);
    } else {
      console.error('Error: Fairchild.compressImage called with blank inputFilePath.');
    }
  }

};

module.exports = Fairchild;
