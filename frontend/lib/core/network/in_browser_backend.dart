// In-browser demo backend (GitHub Pages build). On non-web platforms these are no-ops.
export 'in_browser_backend_stub.dart'
    if (dart.library.js_interop) 'in_browser_backend_web.dart';
