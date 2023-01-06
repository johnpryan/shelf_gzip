# shelf_gzip

[![pub package](https://img.shields.io/pub/v/shelf_gzip.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/shelf_gzip)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/johnpryan/shelf_gzip/actions/workflows/dart.yml/badge.svg)](https://github.com/johnpryan/shelf_gzip/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/johnpryan/shelf_gzip?logo=git&logoColor=white)](https://github.com/johnpryan/shelf_gzip/releases)
[![New Commits](https://img.shields.io/github/commits-since/johnpryan/shelf_gzip/latest?logo=git&logoColor=white)](https://github.com/johnpryan/shelf_gzip/network)
[![Last Commits](https://img.shields.io/github/last-commit/johnpryan/shelf_gzip?logo=git&logoColor=white)](https://github.com/johnpryan/shelf_gzip/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/johnpryan/shelf_gzip?logo=github&logoColor=white)](https://github.com/johnpryan/shelf_gzip/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/johnpryan/shelf_gzip?logo=github&logoColor=white)](https://github.com/johnpryan/shelf_gzip)
[![License](https://img.shields.io/github/license/johnpryan/shelf_gzip?logo=open-source-initiative&logoColor=green)](https://github.com/johnpryan/shelf_gzip/blob/master/LICENSE)

Shelf middleware to GZIP encoding responses, with compression level and compression scope by content-type.

## Usage

```dart
import 'dart:async' show runZonedGuarded;
import 'dart:io';

import 'package:path/path.dart' show join, dirname;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_gzip/shelf_gzip.dart';
import 'package:shelf_static/shelf_static.dart';

void main() {
  // Assumes the server lives in bin/ and that `pub build` ran
  var pathToBuild =
  join(dirname(Platform.script.toFilePath()), '..', 'build/web');
  var staticHandler =
  createStaticHandler(pathToBuild, defaultDocument: 'index.html');

  var portEnv = Platform.environment['PORT'];
  var port = portEnv == null ? 9999 : int.parse(portEnv);

  runZonedGuarded(() async {
    var handler = const shelf.Pipeline()
            .addMiddleware(gzipMiddleware)
            .addHandler(staticHandler);

    await shelf_io.serve(handler, '0.0.0.0', port);

    print("Serving $pathToBuild on port $port");
  }, (e, stackTrace) => print('Server error: $e $stackTrace'));
}
```

## When not compress 

The `gzip` encoding won't be applied if:

- The `Content-Type` is for an already
compressed type. See `isAlreadyCompressedContentType`.


- A small response body (length < 512) will not benefit from being compressed.

## Compression Level

The default `gzip` encoder compression level is set to **4**,
since this is the recommended level for live compression
(not stored file compression). A level **4** compression
has the best trade off for text/code content and CPU usage.

- *The original default `gzip` encoder compression level is **6**.*

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/johnpryan/shelf_gzip

# Authors
- John Ryan: [johnpryan][github_johnpryan].
- Graciliano M. Passos: [gmpassos][github_gmpassos].

[github_johnpryan]: https://github.com/johnpryan
[github_gmpassos]: https://github.com/gmpassos


## License

[BSD-3-Clause License][license]

[license]: https://github.com/johnpryan/shelf_gzip/blob/master/LICENSE
