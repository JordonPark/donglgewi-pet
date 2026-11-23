export 'pet_platform_stub.dart'
    if (dart.library.io) 'pet_platform_native.dart'
    if (dart.library.js_interop) 'pet_platform_web.dart';
