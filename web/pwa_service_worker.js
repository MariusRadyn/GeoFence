/* Lightweight pass-through service worker used only for PWA installability.
 * No app-shell caching, no route interception.
 */
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', () => {
  // Pass-through: browser/network handles all requests.
});

