import 'dart:async';
import 'dart:io' show HttpHeaders, ZLibEncoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Using level 4, since have almost the same compression ratio of normal
/// texting content, but with a lower CPU usage. This is the recommended
/// for live data compression with `gzip`.
const int _defaultGzipCompressionLevel = 4;

/// A body with less than 512 bytes will have almost no benefit to be
/// compressed by `Gzip`, since a `gzip` encoded response will add an extra
/// header to the HTTP protocol and extra `Gzip` bytes to the compressed data.
const int _defaultMinimalGzipContentLength = 512;

final _defaultGzipEncoder =
    ZLibEncoder(gzip: true, level: _defaultGzipCompressionLevel);

/// The default `gzip` encoding [Middleware].
final Middleware gzipMiddleware = createGzipMiddleware();

/// Converts a [Response] to a `gzip` encoding
/// (only if the [Request] [acceptsGzipEncoding]).
///
/// - [minimalGzipContentLength] is the minimal size for a content to be
///   compressed. Default to `512`.
/// - [alreadyCompressedContentType] is a function that returns `true` if the
///   passed `contentType` is already compressed, like a `PNG`, `JPEG` or `Zip`.
///   Defaults to [isAlreadyCompressedContentType].
/// - The [compressionLevel] for the `gzip` encoder. Default: 4
/// - If [addCompressionRatioHeader] is `true`, add header `X-Compression-Ratio`.
/// - If [addServerTiming] is `true`, include or append Gzip encoding timing
///   to the `server-timing` header.
/// - [serverTimingEntryName] is the entry name to be used in
///   the `server-timing` header.
Middleware createGzipMiddleware({
  int minimalGzipContentLength = _defaultMinimalGzipContentLength,
  _AlreadyCompressedContentType? alreadyCompressedContentType,
  int compressionLevel = _defaultGzipCompressionLevel,
  bool addCompressionRatioHeader = true,
  bool addServerTiming = false,
  String serverTimingEntryName = 'gzip',
}) {
  return (Handler innerHandler) {
    return (request) {
      if (!acceptsGzipEncoding(request)) {
        return innerHandler(request);
      }
      return Future.sync(() => innerHandler(request))
          .then((response) => gzipEncodeResponse(
                response,
                minimalGzipContentLength: minimalGzipContentLength,
                alreadyCompressedContentType: alreadyCompressedContentType,
                compressionLevel: compressionLevel,
                addCompressionRatioHeader: addCompressionRatioHeader,
                addServerTiming: addServerTiming,
                serverTimingEntryName: serverTimingEntryName,
              ));
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
/// - [minimalGzipContentLength] is the minimal size for a content to be
///   compressed. Default to `512`.
/// - [alreadyCompressedContentType] is a function that returns `true` if the
///   passed `contentType` is already compressed, like a `PNG`, `JPEG` or `Zip`.
///   Defaults to [isAlreadyCompressedContentType].
/// - If [addCompressionRatioHeader] is `true` it adds the header
///   `X-Compression-Ratio`, with compression info, e.g.: `0.55 (550/1000)`
/// - If [addServerTiming] is `true`, include or append Gzip encoding timing to
///   the `server-timing` header.
/// - [serverTimingEntryName] is the entry name to be used in the
///   `server-timing` header.
/// See [createGzipMiddleware].
FutureOr<Response> gzipEncodeResponse(
  Response response, {
  int minimalGzipContentLength = _defaultMinimalGzipContentLength,
  _AlreadyCompressedContentType? alreadyCompressedContentType,
  int compressionLevel = _defaultGzipCompressionLevel,
  bool addCompressionRatioHeader = true,
  bool addServerTiming = false,
  String serverTimingEntryName = 'gzip',
}) async {
  if (!canGzipEncodeResponse(response,
      minimalGzipContentLength: minimalGzipContentLength,
      alreadyCompressedContentType: alreadyCompressedContentType)) {
    return response;
  }

  var gzipInit = DateTime.now();

  var bufferInitialCapacity = response.contentLength ?? 1024 * 4;

  // Read the body bytes from the response:
  var bytesBuffer = await response.read().fold<_BytesBuffer>(
      _BytesBuffer(bufferInitialCapacity),
      (result, bytes) => result..addAll(bytes));

  var gzipEncoder = compressionLevel == _defaultGzipCompressionLevel
      ? _defaultGzipEncoder
      : ZLibEncoder(gzip: true, level: compressionLevel);

  // Compressed body:
  var compressedBody = gzipEncoder.convert(bytesBuffer.toUint8List());

  var bodyLength = bytesBuffer.length;
  var compressedBodyLength = compressedBody.length;

  var headers = Map<String, String>.from(response.headers);

  headers[HttpHeaders.contentEncodingHeader] = 'gzip';
  headers[HttpHeaders.contentLengthHeader] = compressedBodyLength.toString();

  if (addCompressionRatioHeader) {
    var compressionRatio = compressedBodyLength / bodyLength;

    var compressionRatioStr = '$compressionRatio';
    if (compressionRatioStr.length > 6) {
      compressionRatioStr = compressionRatio.toStringAsFixed(4);
    }

    headers['X-Compression-Ratio'] =
        '$compressionRatioStr ($compressedBodyLength/$bodyLength)';
  }

  if (addServerTiming) {
    const headerServerTiming = 'server-timing';

    var gzipTime = DateTime.now().difference(gzipInit);
    var dur = gzipTime.inMicroseconds / 1000;

    var serverTiming2 = StringBuffer();

    var serverTiming = headers[headerServerTiming];
    if (serverTiming != null && serverTiming.isNotEmpty) {
      serverTiming2.write(serverTiming);
      serverTiming2.write(',');
    }

    serverTiming2.write(serverTimingEntryName);
    serverTiming2.write(';dur=');
    serverTiming2.write(dur);

    headers[headerServerTiming] = serverTiming2.toString();
  }

  return response.change(headers: headers, body: compressedBody);
}

/// a function that returns `true` if the passed `contentType`
/// is already compressed.
typedef _AlreadyCompressedContentType = bool Function(String contentType);

/// Returns `true` if [response] can be compressed.
///
/// - [minimalGzipContentLength] is the minimal size for a content to be
///   compressed. Default to `512`.
/// - [alreadyCompressedContentType] is a function that returns `true` if the
///   passed `contentType` is already compressed, like a `PNG`, `JPEG` or `Zip`.
///
/// Checks:
/// - `Content-Encoding`: if already present, can't change it to `gzip`.
/// - `Content-Type`: checks if [isAlreadyCompressedContentType].
/// - `Content-Length`: checks if too small for compression (< 512).
bool canGzipEncodeResponse(Response response,
    {int minimalGzipContentLength = _defaultMinimalGzipContentLength,
    _AlreadyCompressedContentType? alreadyCompressedContentType}) {
  var headerContentEncoding =
      response.headers[HttpHeaders.contentEncodingHeader];

  // If the response already defines a `Content-Encoding` header it
  // won't apply the the `gzip` encoding to preserve the response behavior.
  if (headerContentEncoding != null && headerContentEncoding.isNotEmpty) {
    return false;
  }

  var responseContentLength = response.contentLength;

  // A small body will not benefit from being compressed:
  if (responseContentLength != null &&
      responseContentLength < minimalGzipContentLength) {
    return false;
  }

  var headerContentType = response.headers[HttpHeaders.contentTypeHeader];

  // Do not compress if the `Content-Type` is an already compressed type:
  if (headerContentType != null) {
    alreadyCompressedContentType ??= isAlreadyCompressedContentType;
    if (alreadyCompressedContentType(headerContentType)) {
      return false;
    }
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
