// A download in the browser (file_download_web.dart); off the web nothing
// calls it and this is a stub.
export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
