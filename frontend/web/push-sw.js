// Service Worker de Web Push (VAPID) — Nivra no usa Firebase/FCM.
//
// Este NO reemplaza a flutter_service_worker.js (ese lo genera
// `flutter build web` y cachea los assets de la app); es un segundo
// Service Worker registrado aparte por `WebPushService`, dedicado solo a
// recibir eventos `push` y mostrar la notificación del sistema — incluso
// con la pestaña cerrada.

// La app usa rutas con "#" (p. ej. /#/chat/25): un deepLink "/chat/25" se
// convierte a la URL real dentro de la app.
function appUrl(deepLink) {
  const link = deepLink || '/';
  if (link.startsWith('http') || link.startsWith('/#')) return link;
  return link === '/' ? '/' : '/#' + (link.startsWith('/') ? link : '/' + link);
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'Nivra', body: event.data ? event.data.text() : '' };
  }

  const title = data.title || 'Nivra';
  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // Un mismo chat reemplaza su aviso anterior en lugar de apilarse.
    tag: data.tag || undefined,
    renotify: Boolean(data.tag),
    data: { deepLink: data.deepLink || '/' },
  };

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      // Si el usuario ya está mirando la app, la bandeja se actualiza sola
      // (tiempo real): no se muestra un aviso del sistema duplicado.
      const watching = list.some(
        (c) => c.visibilityState === 'visible' && c.focused,
      );
      if (watching) return undefined;
      return self.registration.showNotification(title, options);
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = appUrl(event.notification.data && event.notification.data.deepLink);

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async (list) => {
      for (const client of list) {
        if ('focus' in client) {
          await client.focus();
          if ('navigate' in client) {
            try { await client.navigate(url); } catch (e) { /* mismo origen: ignorar */ }
          }
          return;
        }
      }
      if (clients.openWindow) return clients.openWindow(url);
    }),
  );
});
