import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/env.dart';

@JS('ceevoraBackend.request')
external JSPromise<JSString> _request(
  JSString method,
  JSString url,
  JSString headers,
  JSString? body,
);
@JS('ceevoraBackend.ready')
external JSPromise<JSAny?> _ready();
@JS('location.reload')
external void _reload();
@JS('ceevoraBackend.reset')
external JSPromise<JSAny?> _reset();

/// Routes Dio requests to the FastAPI app running in a Web Worker (web/backend/worker.js) instead of the network.
class _InBrowserAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String? body;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        [],
        (a, b) => a..addAll(b),
      );
      body = utf8.decode(bytes);
    }
    final headers = {for (final e in o.headers.entries) e.key: '${e.value}'};
    final raw = (await _request(
      o.method.toJS,
      o.uri.toString().toJS,
      jsonEncode(headers).toJS,
      body?.toJS,
    ).toDart).toDart;
    final res = jsonDecode(raw) as Map<String, dynamic>;
    return ResponseBody.fromString(
      res['body'] as String,
      res['status'] as int,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HttpClientAdapter? browserAdapter() =>
    Env.inBrowserBackend ? _InBrowserAdapter() : null;
Future<void> browserBackendReady() async {
  if (Env.inBrowserBackend) await _ready().toDart;
}

Future<void> resetBrowserBackend() async {
  if (!Env.inBrowserBackend) return;
  await _reset().toDart;
  _reload(); // restart the worker so it loads the original demo database
}
