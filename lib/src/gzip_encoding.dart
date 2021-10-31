import 'dart:async';
import 'dart:io' show HttpHeaders, ZLibEncoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Using level 4, since have almost the same compression ratio of normal
/// texting content, but with a lower CPU usage. This is the recommended
/// for live data compression with `gzip`.
const int defaultGzipEncodingCompressionLevel = 4;

final _defaultGzipEncoder =
    ZLibEncoder(gzip: true, level: defaultGzipEncodingCompressionLevel);

/// The default `gzip` encoding [Middleware].
final Middleware gzipMiddleware = createGzipMiddleware();

/// Converts a [Response] to a `gzip` encoding
/// (only if the [Request] [acceptsGzipEncoding]).
///
/// - The [compressionLevel] for the `gzip` encoder. Default: 4
/// - If [addCompressionRatioHeader] is `true`, add header `X-Compression-Ratio`.
Middleware createGzipMiddleware(
    {int compressionLevel = defaultGzipEncodingCompressionLevel,
    bool addCompressionRatioHeader = true}) {
  return (Handler innerHandler) {
    return (request) {
      if (!acceptsGzipEncoding(request)) {
        return innerHandler(request);
      }
      return Future.sync(() => innerHandler(request)).then((response) =>
          gzipEncodeResponse(response,
              compressionLevel: compressionLevel,
              addCompressionRatioHeader: addCompressionRatioHeader));
    };
  };
}

/// Returns `true` if the request accepts `gzip` encoding.
bool acceptsGzipEncoding(Request request) {
  var acceptEncoding = request.headers[HttpHeaders.acceptEncodingHeader];
  return acceptEncoding?.contains('gzip') ?? false;
}

/// Converts [response] to a `gzip` encoding response.
/// Checks [canGzipEncodeResponse].
///
/// See [createGzipMiddleware].
FutureOr<Response> gzipEncodeResponse(Response response,
    {int compressionLevel = defaultGzipEncodingCompressionLevel,
    bool addCompressionRatioHeader = true}) async {
  if (!canGzipEncodeResponse(response)) {
    return response;
  }

  var bufferInitialCapacity = response.contentLength ?? 1024 * 4;

  // Read the body bytes from the response:
  var bytesBuffer = await response.read().fold<_BytesBuffer>(
      _BytesBuffer(bufferInitialCapacity),
      (result, bytes) => result..addAll(bytes));

  var gzipEncoder = compressionLevel == defaultGzipEncodingCompressionLevel
      ? _defaultGzipEncoder
      : ZLibEncoder(gzip: true, level: compressionLevel);

  // Compressed body:
  var compressedBody = gzipEncoder.convert(bytesBuffer.toUint8List());

  var bodyLength = bytesBuffer.length;
  var compressedBodyLength = compressedBody.length;
  var compressionRatio = compressedBodyLength / bodyLength;

  var headers = Map<String, String>.from(response.headers);

  headers[HttpHeaders.contentEncodingHeader] = 'gzip';
  headers[HttpHeaders.contentLengthHeader] = compressedBodyLength.toString();
  headers['X-Compression-Ratio'] =
      '$compressionRatio ($compressedBodyLength/$bodyLength)';

  return response.change(headers: headers, body: compressedBody);
}

/// Returns `true` if [response] can be compressed.
///
/// Checks:
/// - `Content-Encoding`: if already present, can't change it to `gzip`.
/// - `Content-Type`: checks if [isAlreadyCompressedContentType].
/// - `Content-Length`: checks if too small for compression (< 512).
bool canGzipEncodeResponse(Response response) {
  var headerContentEncoding =
      response.headers[HttpHeaders.contentEncodingHeader];

  // If the response already defines a `Content-Encoding` header it
  // won't apply the the `gzip` encoding to preserve the response behavior.
  if (headerContentEncoding != null && headerContentEncoding.isNotEmpty) {
    return false;
  }

  var responseContentLength = response.contentLength;

  // A small body will not benefit from being compressed:
  if (responseContentLength != null && responseContentLength < 512) {
    return false;
  }

  var headerContentType = response.headers[HttpHeaders.contentTypeHeader];

  // Do not compress if the `Content-Type` is an already compressed type:
  if (headerContentType != null &&
      isAlreadyCompressedContentType(headerContentType)) {
    return false;
  }

  return true;
}

/// Returns `true` if [contentType] is already compressed.
///
/// See [isAlreadyCompressedExtension].
bool isAlreadyCompressedContentType(String contentType) {
  contentType = contentType.toLowerCase().trim();
  if (contentType.isEmpty) return false;

  var idx = contentType.indexOf(';');
  if (idx >= 0) {
    contentType = contentType.substring(0, idx).trim();
  }

  var idx2 = contentType.indexOf('/');

  var type = idx2 >= 0 ? contentType.substring(idx2 + 1) : contentType;

  if (isAlreadyCompressedExtension(type)) {
    return true;
  }

  if (type.contains('+')) {
    var list = type.split('+');
    var alreadyCompressed =
        list.where((e) => isAlreadyCompressedExtension(e)).isNotEmpty;
    return alreadyCompressed;
  }

  return false;
}

bool isAlreadyCompressedExtension(String extension) {
  extension = extension.toLowerCase().trim();
  if (extension.isEmpty) return false;

  switch (extension) {
    case 'ico':
    case 'png':
    case 'jpg':
    case 'jpeg':

    case 'avi':

    case 'mp3':
    case 'mp4':
    case 'mpeg':

    case 'ogg':
    case 'ogx':

    case 'weba':
    case 'webm':
    case 'webp':

    case 'epub':
    case 'pdf':

    case 'woff':
    case 'woff2':

    case 'jar':
    case 'war':

    case '7z':
    case 'bz':
    case 'bz2':
    case 'gzip':
    case 'gz':
    case 'rar':
    case 'zip':
      return true;
    default:
      return false;
  }
}

// Optimized buffer to read the body.
class _BytesBuffer {
  Uint8List _bytes;
  int _length = 0;

  _BytesBuffer(int initialCapacity) : _bytes = Uint8List(initialCapacity);

  int get capacity => _bytes.length;

  int get length => _length;

  void _ensureCapacity(int needed) {
    if (capacity < needed) {
      var newCapacity = math.max(capacity * 2, needed);
      var bs = Uint8List(newCapacity);
      bs.addAll(_bytes);
      _bytes = bs;
    }
  }

  void addAll(List<int> bs) {
    var bsLength = bs.length;

    _ensureCapacity(_length + bsLength);

    _bytes.setAll(_length, bs);
    _length += bsLength;
  }

  Uint8List toUint8List() {
    if (_length == _bytes.length) {
      return _bytes;
    } else {
      return _bytes.sublist(0, _length);
    }
  }
}
