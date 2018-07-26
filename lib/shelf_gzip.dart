// Copyright (c) 2016, John Ryan. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Support for doing something awesome.
///
/// More dartdocs go here.
library shelf_gzip;

import 'package:shelf/shelf.dart';
import 'dart:io' show HttpHeaders, ZLibEncoder;

final _gzip = new ZLibEncoder(gzip: true);

final Middleware gzipMiddleware =
createMiddleware(responseHandler: (response) async {
  var newHeaders = new Map<String, String>.from(response.headers);

  // Read the bytes from the file and use GZIP compression.
  var b = _gzip.convert(await response
      .read()
      .fold(<int>[], (result, bytes) => result..addAll(bytes)));

  newHeaders[HttpHeaders.contentEncodingHeader] = 'gzip';
  newHeaders[HttpHeaders.contentLengthHeader] = b.length.toString();
  return response.change(headers: newHeaders, body: b);
});
