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

  compressVideo(inputFilePath, deleteOriginal, options) {
    return _compressVideo(inputFilePath, !!deleteOriginal, options || {})
      .catch(compressionError);
  }

};

module.exports = Fairchild;
