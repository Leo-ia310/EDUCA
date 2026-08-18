// Service Worker de Web Push (VAPID) — Educa360 no usa Firebase/FCM.
//
// Este NO reemplaza a flutter_service_worker.js (ese lo genera
// `flutter build web` y cachea los assets de la app); es un segundo
// Service Worker registrado aparte por `WebPushService`, dedicado solo a
// recibir eventos `push` y mostrar la notificación del sistema — incluso
// con la pestaña cerrada.

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'Educa360', body: event.data ? event.data.text() : '' };
  }

  const title = data.title || 'Educa360';
  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { deepLink: data.deepLink || '/' },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const deepLink = (event.notification.data && event.notification.data.deepLink) || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(deepLink);
    }),
  );
});
