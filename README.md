# shelf_gzip

Shelf middleware that compresses responses with GZIP

## Usage

```dart
import 'dart:io';
import 'dart:async' show runZoned;
import 'package:path/path.dart' show join, dirname;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_gzip/shelf_gzip.dart';

void main() {
  // Assumes the server lives in bin/ and that `pub build` ran
  var pathToBuild =
      join(dirname(Platform.script.toFilePath()), '..', 'build/web');
  var staticHandler =
      createStaticHandler(pathToBuild, defaultDocument: 'index.html');

  var portEnv = Platform.environment['PORT'];
  var port = portEnv == null ? 9999 : int.parse(portEnv);

  runZoned(() async {
    var handler = const shelf.Pipeline()
        .addMiddleware(gzipMiddleware)
        .addHandler(staticHandler);

    await shelf_io.serve(handler, '0.0.0.0', port);

    print("Serving $pathToBuild on port $port");
  }, onError: (e, stackTrace) => print('Server error: $e $stackTrace'));
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/johnpryan/shelf_gzip
