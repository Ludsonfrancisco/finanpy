const CACHE_NAME = 'finanpy-v1';
const STATIC_ASSETS = [
  '/',
  '/offline/',
  '/static/css/custom.css',
  '/static/manifest.json',
  'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap',
  'https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js'
];

// Instalação do Service Worker e Cache do App Shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[Service Worker] Caching App Shell');
      // Usando addAll para ativos essenciais, mas tratando falhas individuais se necessário
      return cache.addAll(STATIC_ASSETS).catch(err => {
        console.error('[Service Worker] Precaching failed, but continuing...', err);
        // Opcional: tentar carregar um por um para não falhar tudo
      });
    })
  );
  self.skipWaiting();
});

// Ativação e limpeza de caches antigos
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('[Service Worker] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  self.clients.claim();
});

// Interceptador de fetch com estratégias Network First e Cache First
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Estratégia Cache First para estáticos (imagens, estilos, scripts, fontes)
  if (
    event.request.destination === 'style' ||
    event.request.destination === 'script' ||
    event.request.destination === 'image' ||
    event.request.destination === 'font' ||
    STATIC_ASSETS.includes(url.pathname)
  ) {
    event.respondWith(
      caches.match(event.request).then((response) => {
        return response || fetch(event.request).then((fetchResponse) => {
          return caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, fetchResponse.clone());
            return fetchResponse;
          });
        });
      })
    );
    return;
  }

  // Estratégia Network First para dados e páginas (HTML, navegação)
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Se a resposta for válida, armazena no cache
        if (response.status === 200) {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return response;
      })
      .catch(() => {
        // Fallback para o cache se a rede falhar
        return caches.match(event.request).then((response) => {
          if (response) {
            return response;
          }
          // Se for uma navegação e não houver no cache, retorna a página offline
          if (event.request.mode === 'navigate') {
            return caches.match('/offline/');
          }
        });
      })
  );
});
