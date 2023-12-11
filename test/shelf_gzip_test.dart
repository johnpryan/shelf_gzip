import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_gzip/shelf_gzip.dart';
import 'package:test/test.dart';

final Uint8List _pngTransparentPixel = base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  group('shelf_gzip', () {
    test('basic', () async {
      // `shelf` Pipeline:
      var pipeline = const Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(gzipMiddleware);

      var handler = pipeline.addHandler((request) {
        var requestedUri = request.requestedUri;
        var path = requestedUri.path;
        if (path == '/transparent-pixel') {
          print('Sending PNG... $requestedUri');
          return Response.ok(_pngTransparentPixel,
              headers: {'Content-Type': 'image/png'});
        } else {
          return Response.ok('Requested: $requestedUri');
        }
      });

      var server = await serve(handler, 'localhost', 0);

      var port = server.port;

      var baseURL = 'http://localhost:$port';

      print('baseURL: $baseURL');

      // No gzip, small body:
      expect(
          await _getURL('$baseURL/foo',
              expectedContentEncoding: '',
              compressionState:
                  HttpClientResponseCompressionState.notCompressed),
          equals('Requested: http://localhost:$port/foo'));

      var longValue = 'long_value_'.padRight(1024, 'x');

      // Expected gzip, long body:
      expect(
          await _getURL('$baseURL/$longValue',
              expectedContentEncoding: 'gzip',
              compressionState:
                  HttpClientResponseCompressionState.decompressed),
          equals('Requested: http://localhost:$port/$longValue'));

      // Expected a PNG without gzip encoding:
      expect(
          await _getURL('$baseURL/transparent-pixel',
              expectedContentType: 'image/png',
              expectedContentEncoding: '',
              compressionState:
                  HttpClientResponseCompressionState.notCompressed),
          startsWith('\u0089PNG\r\n'));

      server.close();
    });

    test('Check added headers', () async {
      // `shelf` Pipeline:
      var pipeline = const Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(createGzipMiddleware(
            addCompressionRatioHeader: true,
            addServerTiming: true,
            serverTimingEntryName: 'x-gzip',
          ));

      var handler = pipeline.addHandler((request) {
        var requestedUri = request.requestedUri;
        return Response.ok('Requested: $requestedUri');
      });

      var server = await serve(handler, 'localhost', 0);

      var port = server.port;

      var baseURL = 'http://localhost:$port';

      print('baseURL: $baseURL');

      // No gzip, small body:
      expect(
          await _getURL(
            '$baseURL/foo',
            expectedContentEncoding: '',
            compressionState: HttpClientResponseCompressionState.notCompressed,
            expectedHeaders: {
              'x-compression-ratio': isNull,
              'server-timing': isNull,
            },
          ),
          equals('Requested: http://localhost:$port/foo'));

      var longValue = 'long_value_'.padRight(1024, 'x');

      // Expected gzip, long body:
      expect(
          await _getURL(
            '$baseURL/$longValue',
            expectedContentEncoding: 'gzip',
            compressionState: HttpClientResponseCompressionState.decompressed,
            expectedHeaders: {
              'x-compression-ratio': isNotEmpty,
              'server-timing': startsWith('x-gzip;dur='),
            },
          ),
          equals('Requested: http://localhost:$port/$longValue'));

      server.close();
    });

    test('isAlreadyCompressedExtension', () async {
      expect(isAlreadyCompressedExtension('gz'), isTrue);
      expect(isAlreadyCompressedExtension('gzip'), isTrue);
      expect(isAlreadyCompressedExtension('zip'), isTrue);

      expect(isAlreadyCompressedExtension('png'), isTrue);
      expect(isAlreadyCompressedExtension('jpeg'), isTrue);
      expect(isAlreadyCompressedExtension('jpg'), isTrue);

      expect(isAlreadyCompressedExtension('txt'), isFalse);
      expect(isAlreadyCompressedExtension('text'), isFalse);
      expect(isAlreadyCompressedExtension('html'), isFalse);
    });

    test('isAlreadyCompressedContentType', () async {
      expect(isAlreadyCompressedContentType('application/gzip'), isTrue);
      expect(isAlreadyCompressedContentType('application/zip'), isTrue);

      expect(isAlreadyCompressedContentType('image/png'), isTrue);
      expect(isAlreadyCompressedContentType('image/jpeg'), isTrue);

      expect(isAlreadyCompressedContentType('text/plain'), isFalse);
      expect(isAlreadyCompressedContentType('text/html'), isFalse);

      expect(isAlreadyCompressedContentType('application/json'), isFalse);
      expect(isAlreadyCompressedContentType('application/javascript'), isFalse);

      expect(isAlreadyCompressedContentType('png'), isTrue);
      expect(isAlreadyCompressedContentType('json'), isFalse);
    });
  });
}

/// Simple HTTP get URL function.
Future<String> _getURL(String url,
    {Map<String, dynamic>? parameters,
    String? expectedContentType,
    String? expectedContentEncoding,
    HttpClientResponseCompressionState? compressionState,
    Map<String, dynamic>? expectedHeaders}) async {
  var uri = Uri.parse(url);

  if (parameters != null) {
    parameters = parameters.map((key, value) => MapEntry(key, '$value'));

    uri = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.port,
      path: uri.path,
      fragment: uri.fragment,
      queryParameters: parameters,
    );
  }

  var httpClient = HttpClient();

  var response =
      await httpClient.getUrl(uri).then((request) => request.close());

  var headerContentType = response.headers[HttpHeaders.contentTypeHeader];
  var headerContentEncoding =
      response.headers[HttpHeaders.contentEncodingHeader];

  var headerCompressionRatio = response.headers['X-Compression-Ratio'];

  print('Client> '
      'Content-Type: $headerContentType ; '
      'Content-Encoding: $headerContentEncoding ; '
      'X-Compression-Ratio: $headerCompressionRatio ; '
      'compressionState: ${response.compressionState} '
      '> $url');

  if (expectedContentType != null) {
    var contentType = headerContentType ?? [''];
    expect(contentType.first, equals(expectedContentType));
  }

  if (expectedContentEncoding != null) {
    var contentEncoding = headerContentEncoding ?? [''];
    expect(contentEncoding.first, equals(expectedContentEncoding));
  }

  if (compressionState != null) {
    expect(response.compressionState, equals(compressionState));
  }

  if (expectedHeaders != null) {
    print('HttpClientResponse Headers:');
    response.headers.forEach((k, v) => print('-- $k: $v'));

    for (var e in expectedHeaders.entries) {
      expect(response.headers.value(e.key), e.value);
    }
  }

  var data = await response.transform(Latin1Decoder()).toList();
  var body = data.join();

  return body;
}
