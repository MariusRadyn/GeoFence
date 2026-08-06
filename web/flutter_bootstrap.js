{{flutter_js}}
{{flutter_build_config}}

// Do not register a service worker — it intercepts /delete-*.html and serves
// the Flutter app shell instead of the standalone account-management pages.
_flutter.loader.load();
