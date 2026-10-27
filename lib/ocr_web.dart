import 'dart:js_interop';
import 'dart:typed_data';

@JS('extractPdfTextWithOcr')
external JSPromise<JSString> _extractPdfTextWithOcr(JSUint8Array bytes);

Future<String> extractPdfTextWithOcr(Uint8List bytes) {
  return _extractPdfTextWithOcr(bytes.toJS)
      .toDart
      .then((value) => value.toDart);
}
