## 4.1.0

- `createGzipMiddleware` and `gzipEncodeResponse`:
  - Added parameters `addServerTiming` and `serverTimingEntryName`. 

- lints: ^1.0.1

## 4.0.1

- `X-Compression-Ratio`: truncate ratio precision `> 4`.
- Update `.gitignore`

## 4.0.0

- Null Safety compliant.
- Added:
  - `createGzipMiddleware`: can create a `Middleware` with a custom `compressionLevel`.
  - `acceptsGzipEncoding`: checks if a `Request` accepts `gzip` encoding.
  - `gzipEncodeResponse`: converts a `Response` to a `gzip` encoding response.
  - `isAlreadyCompressedContentType` and `isAlreadyCompressedExtension`: checks if is already compressed.
- Optimized bytes reading and compression.
- Added an example.
- Improved API documentation.
- lints: ^1.0.0
  - Using `lints/recommended.yaml`
- test: ^1.16.0
  - Added basic tests.
- CI: Added GitHub action.

## 1.0.0

- Initial version
