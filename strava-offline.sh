# strava-offline.sh — sourced by strava-render-pages.sh (My Activities / HealthSync)
# and by strava-leaderboard-html.sh (club leaderboard).
# Writes $WEB_DIR/sw.js (service worker) and $WEB_DIR/offline.js (shared client
# script) so the pages stay readable when the router is unreachable (phone off
# the home Wi-Fi). Service workers need a secure context, so this only takes
# effect when the pages are opened over https:// (see README "Offline access").
# Quoted heredocs: nothing is shell-expanded.
# Variable required from caller: WEB_DIR.

cat > "$WEB_DIR/sw.js" <<'JS'
/* StatsServiceBook offline service worker. Bump CACHE when this file's logic changes. */
var CACHE = 'ssb-offline-v1', TILES = 'ssb-tiles-v1', TIMEOUT = 4000, SOFT = 1500, MAX_TILES = 600;
var LEAFLET = [
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js',
  'https://unpkg.com/leaflet.heat@0.2.0/dist/leaflet-heat.js'
];
// Same-origin shell; entries that do not exist for this scope (e.g. activity.html
// in the club leaderboard dir) are simply skipped.
var SHELL = ['./', 'index.html', 'activity.html', 'bike.html', 'stats.html', 'heatmap.html',
  'data-quality.html', 'offline.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'activities.json', 'heatmap.json', 'drive-status.json',
  '/cgi-bin/bike-service', '/cgi-bin/bike-assign', '/cgi-bin/ride-goals'];
// My Activities (/strava/me/) links to the club leaderboard one level up. That page is
// outside this worker's scope, so pre-cache it here (shared cache) for the offline link.
if (/\/me\/sw\.js$/.test(self.location.pathname)) SHELL.push('../');
var CGI_READ =/^\/cgi-bin\/(bike-service|bike-assign|ride-goals)$/;
var SKIP = /\.(log)$|-running$|sync-status\.json$|sync-live/;
var CROSS = /(^|\.)(unpkg\.com|tile\.openstreetmap\.org|basemaps\.cartocdn\.com)$/;

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) {
    var jobs = SHELL.map(function (u) {
      return fetch(u, { cache: 'reload' }).then(function (r) { if (r.ok) return c.put(u, r); }).catch(function () {});
    }).concat(LEAFLET.map(function (u) {
      return fetch(u, { mode: 'cors' }).then(function (r) { if (r.ok) return c.put(u, r); }).catch(function () {});
    }));
    return Promise.all(jobs);
  }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (ks) {
    return Promise.all(ks.filter(function (k) { return /^ssb-/.test(k) && k !== CACHE && k !== TILES; })
      .map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

// Tell open pages the router answered, so they can drop a false "offline" banner.
var lastOnlineMsg = 0;
function notifyOnline() {
  var now = Date.now();
  if (now - lastOnlineMsg < 5000) return;
  lastOnlineMsg = now;
  self.clients.matchAll().then(function (cs) {
    cs.forEach(function (c) { c.postMessage({ ssb: 'online' }); });
  });
}

// Once the router has failed to answer, serve straight from the cache for a while
// instead of making every request wait out TIMEOUT. One throttled background
// request keeps checking whether the router is back.
var offlineUntil = 0, lastProbe = 0, OFFLINE_FOR = 20000;
function markOffline() { offlineUntil = Date.now() + OFFLINE_FOR; }
function routerLooksDown() { return self.navigator.onLine === false || Date.now() < offlineUntil; }

function fetchFresh(req, c, hard) {
  var ctl = new AbortController(), t = setTimeout(function () { ctl.abort(); }, hard || TIMEOUT);
  return fetch(req.url, { signal: ctl.signal, cache: 'no-cache', credentials: 'same-origin' })
    .then(function (r) {
      clearTimeout(t); offlineUntil = 0; notifyOnline();
      if (r.ok) c.put(req.url, r.clone());
      return r;
    }, function (err) { clearTimeout(t); markOffline(); throw err; });
}

function networkFirst(req) {
  return caches.open(CACHE).then(function (c) {
    if (routerLooksDown()) {
      return c.match(req.url, { ignoreSearch: true }).then(function (m) {
        if (!m) return fetchFresh(req, c);
        var now = Date.now();
        if (now - lastProbe > 8000) { lastProbe = now; fetchFresh(req, c).catch(function () {}); }
        return m;
      });
    }
    return c.match(req.url, { ignoreSearch: true }).then(function (m) {
      if (!m) return fetchFresh(req, c, 8000);   // nothing cached: must wait for the router
      // Cached copy exists: give the router SOFT ms, then answer from the cache while
      // the request keeps running in the background and refreshes the cache.
      return new Promise(function (resolve) {
        var done = false;
        function finish(r) { if (!done) { done = true; clearTimeout(soft); resolve(r); } }
        var soft = setTimeout(function () { finish(m); }, SOFT);
        fetchFresh(req, c, 6000).then(finish, function () { finish(m); });
      });
    });
  });
}

function cacheFirst(req, name) {
  return caches.open(name).then(function (c) {
    return c.match(req).then(function (m) {
      if (m) return m;
      return fetch(req).then(function (r) {
        if (r.ok || r.type === 'opaque') {
          c.put(req, r.clone());
          if (name === TILES) c.keys().then(function (ks) {
            for (var i = 0; i < ks.length - MAX_TILES; i++) c.delete(ks[i]);
          });
        }
        return r;
      });
    });
  });
}

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var u = new URL(req.url);
  if (u.origin !== self.location.origin) {
    if (CROSS.test(u.hostname)) e.respondWith(cacheFirst(req, /unpkg/.test(u.hostname) ? CACHE : TILES));
    return;
  }
  if (u.pathname.indexOf('/cgi-bin/') === 0 && !CGI_READ.test(u.pathname)) return;
  if (SKIP.test(u.pathname) || /\/sw\.js$/.test(u.pathname)) return;
  e.respondWith(networkFirst(req));
});
JS

cat > "$WEB_DIR/offline.js" <<'JS'
/* StatsServiceBook offline helper: registers the service worker, detects whether
   the router is reachable, shows a banner and disables write controls while it is
   not. Pages may set window.OFFLINE_CFG = { rw: "<selector of write controls>",
   keep: "<selector of rw matches that stay enabled>" } before loading this file. */
(function () {
  var cfg = window.OFFLINE_CFG || {}, off = false, bar = null, timer = null;
  var rawFetch = window.fetch ? window.fetch.bind(window) : null;
  if (!rawFetch || location.protocol === 'file:') return;

  // Installable web app: add manifest + theme + iOS icon tags once per page.
  if (!document.querySelector('link[rel="manifest"]') && document.head) {
    [['link', { rel: 'manifest', href: 'manifest.webmanifest' }],
     ['link', { rel: 'apple-touch-icon', href: 'icon-192.png' }],
     ['meta', { name: 'theme-color', content: '#fc4c02' }],
     ['meta', { name: 'mobile-web-app-capable', content: 'yes' }],
     ['meta', { name: 'apple-mobile-web-app-capable', content: 'yes' }]].forEach(function (t) {
      var el = document.createElement(t[0]);
      for (var k in t[1]) el.setAttribute(k, t[1][k]);
      document.head.appendChild(el);
    });
  }

  if ('serviceWorker' in navigator && window.isSecureContext)
    navigator.serviceWorker.register('sw.js').catch(function () {});

  // Safety net: while offline, writes fail immediately and visibly.
  window.fetch = function (input, init) {
    var m = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    if (off && m !== 'GET' && m !== 'HEAD')
      return Promise.reject(new Error('Offline: router unreachable, changes are disabled'));
    return rawFetch(input, init).catch(function (e) { if (m === 'GET') probeSoon(); throw e; });
  };

  var css = document.createElement('style');
  css.textContent = '#offline-bar{position:fixed;left:0;right:0;bottom:0;z-index:99999;background:#b45309;color:#fff;' +
    'font:600 .85rem system-ui,Arial,sans-serif;padding:.5rem .8rem;text-align:center}' +
    '.offline-disabled{opacity:.45;cursor:not-allowed!important}';
  (document.head || document.documentElement).appendChild(css);

  function showBar(v) {
    if (v && !bar && document.body) {
      bar = document.createElement('div');
      bar.id = 'offline-bar';
      bar.textContent = 'Offline – router unreachable. Showing saved data; saving is disabled.';
      document.body.appendChild(bar);
      // Reserve room so the fixed banner never covers the last lines of the page.
      document.body.style.paddingBottom = (bar.offsetHeight + 8) + 'px';
    } else if (!v && bar) { bar.remove(); bar = null; document.body.style.paddingBottom = ''; }
  }

  function apply() {
    var els = [];
    if (cfg.rw) {
      els = [].filter.call(document.querySelectorAll(cfg.rw), function (el) {
        return !(cfg.keep && el.matches(cfg.keep));
      });
    }
    if (off) {
      els.forEach(function (el) {
        if (el.hasAttribute('data-off')) return;
        el.setAttribute('data-off', el.disabled ? '1' : '0');
        el.disabled = true;
        el.classList.add('offline-disabled');
      });
    } else {
      [].forEach.call(document.querySelectorAll('[data-off]'), function (el) {
        el.disabled = el.getAttribute('data-off') === '1';
        el.removeAttribute('data-off');
        el.classList.remove('offline-disabled');
      });
    }
  }

  // The pages reveal #leaderboard-link after a HEAD request to ../, which the service
  // worker never intercepts, so it fails offline. Show the link when the club page is cached.
  function showClubLink() {
    var el = document.getElementById('leaderboard-link');
    if (!el || el.style.display === '' || !window.caches) return;
    caches.match(new URL('../', location.href).href, { ignoreSearch: true })
      .then(function (m) { if (m) el.style.display = ''; });
  }

  function setOffline(v) {
    if (v === off) return;
    off = v;
    document.documentElement.classList.toggle('offline', v);
    showBar(v);
    apply();
    if (v && document.readyState !== 'loading') showClubLink();
    window.dispatchEvent(new CustomEvent('routerstatus', { detail: { offline: v } }));
  }
  window.isRouterOffline = function () { return off; };

  // A slow router must not look offline: allow a generous timeout and only declare
  // offline after two failed probes in a row (navigator.onLine === false is trusted).
  var fails = 0;
  function probe() {
    if (navigator.onLine === false) { fails = 2; setOffline(true); return; }
    var ctl = new AbortController(), t = setTimeout(function () { ctl.abort(); }, 8000);
    // HEAD is never intercepted by the service worker, so this reflects the real network.
    rawFetch('offline.js', { method: 'HEAD', cache: 'no-store', signal: ctl.signal })
      .then(function (r) { clearTimeout(t); fails = r.ok ? 0 : fails + 1; if (r.ok || fails >= 2) setOffline(!r.ok); else setTimeout(probe, 2000); })
      .catch(function () { clearTimeout(t); if (++fails >= 2) setOffline(true); else setTimeout(probe, 2000); });
  }
  if ('serviceWorker' in navigator)
    navigator.serviceWorker.addEventListener('message', function (e) {
      if (e.data && e.data.ssb === 'online') { fails = 0; setOffline(false); }
    });
  function probeSoon() { clearTimeout(timer); timer = setTimeout(probe, 300); }

  window.addEventListener('online', probe);
  window.addEventListener('offline', function () { setOffline(true); });
  document.addEventListener('visibilitychange', function () { if (!document.hidden) probe(); });
  setInterval(function () { if (!document.hidden) probe(); }, 20000);

  // Auto-refresh: pages that define window.onDataChanged get called when a sync has
  // rewritten activities.json. Detected with a cheap HEAD (ETag / Last-Modified / size),
  // every 60 s while the tab is visible and again when it becomes visible. The first
  // check only records the baseline; coming back online after being offline counts as a
  // change because the page may have been rendered from the cache.
  var dataSig = null, wasOff = false, POLL_MS = 60000, toast = null;
  function showToast(msg) {
    if (!document.body) return;
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'data-toast';
      toast.style.cssText = 'position:fixed;right:.8rem;top:.8rem;z-index:99998;background:#166534;color:#fff;' +
        'font:600 .8rem system-ui,Arial,sans-serif;padding:.4rem .7rem;border-radius:6px;opacity:0;transition:opacity .3s';
      document.body.appendChild(toast);
    }
    toast.textContent = msg;
    toast.style.opacity = '1';
    setTimeout(function () { if (toast) toast.style.opacity = '0'; }, 4000);
  }
  function fireDataChanged() {
    try { Promise.resolve(window.onDataChanged()).then(function () { showToast('Data updated'); }, function () {}); }
    catch (e) {}
  }
  function checkData() {
    if (off || document.hidden || typeof window.onDataChanged !== 'function') return;
    rawFetch('activities.json', { method: 'HEAD', cache: 'no-store' })
      .then(function (r) {
        if (!r.ok) return;
        var s = (r.headers.get('ETag') || '') + '|' + (r.headers.get('Last-Modified') || '') + '|' + (r.headers.get('Content-Length') || '');
        var changed = dataSig !== null && s !== dataSig;
        if (wasOff) { wasOff = false; changed = true; }
        dataSig = s;
        if (changed) fireDataChanged();
      }).catch(function () {});
  }
  window.addEventListener('routerstatus', function (e) { if (e.detail.offline) wasOff = true; else checkData(); });
  document.addEventListener('visibilitychange', function () { if (!document.hidden) checkData(); });
  setInterval(checkData, POLL_MS);

  document.addEventListener('DOMContentLoaded', function () {
    setTimeout(checkData, 3000);   // record the baseline signature
    if (off) showBar(true);
    showClubLink();   // don't wait for the offline probe: a cached club page is enough
    if (cfg.rw && window.MutationObserver) {
      var pend = false;
      new MutationObserver(function () {
        if (!off || pend) return;
        pend = true;
        requestAnimationFrame(function () { pend = false; apply(); });
      }).observe(document.body, { childList: true, subtree: true });
    }
    // First probe after the page's own requests have had a chance to finish.
    setTimeout(probe, 2000);
  });
})();
JS

# --- Installable web app (PWA): manifest + icons ----------------------------------
# offline.js injects <link rel="manifest"> so the pages need no per-file edits.
# Caller may set PWA_NAME / PWA_SHORT_NAME / PWA_THEME (leaderboard does); defaults suit My Activities.
_pwa_name="${PWA_NAME:-My Activities}"
_pwa_theme="${PWA_THEME:-#fc4c02}"
_pwa_short="${PWA_SHORT_NAME:-Activities}"
jq -n --arg n "$_pwa_name" --arg s "$_pwa_short" --arg c "$_pwa_theme" '{
  name: $n, short_name: $s, start_url: "./", scope: "./", display: "standalone",
  background_color: "#111111", theme_color: $c,
  icons: [
    {src: "icon-192.png", sizes: "192x192", type: "image/png", purpose: "any"},
    {src: "icon-512.png", sizes: "512x512", type: "image/png", purpose: "any"},
    {src: "icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable"}
  ]
}' > "$WEB_DIR/manifest.webmanifest"

# Chrome/Android only accepts PNG icons (192 + 512) for installability. These are
# 1-bit palette PNGs (orange square, three white bars; full-bleed, glyph inside the
# maskable safe zone) written byte-exact with printf octal escapes: no extra tools.
printf '\211\120\116\107\015\012\032\012\000\000\000\015\111\110\104\122\000\000\000\300\000\000\000\300\001\003\000\000\000\150\022\376\104\000\000\000\006\120\114\124\105\374\114\002\377\377\377\360\203\073\174\000\000\000\061\111\104\101\124\170\332\355\311\061\022\000\020\020\004\101\367\163\136\276\002\271\000\211\252\356\160\246\065\000\270\125\111\067\214\223\121\311\060\214\315\130\325\060\214\067\003\340\133\023\131\060\245\347\034\210\203\112\000\000\000\000\111\105\116\104\256\102\140\202' > "$WEB_DIR/icon-192.png"
printf '\211\120\116\107\015\012\032\012\000\000\000\015\111\110\104\122\000\000\002\000\000\000\002\000\001\003\000\000\000\316\266\106\271\000\000\000\006\120\114\124\105\374\114\002\377\377\377\360\203\073\174\000\000\000\153\111\104\101\124\170\332\355\314\261\011\000\100\010\300\100\367\137\132\341\373\027\354\004\357\372\044\002\000\000\000\000\000\000\000\000\000\000\356\312\307\300\300\300\300\300\300\300\300\300\300\300\300\300\300\340\027\032\030\030\030\030\030\030\030\030\030\030\030\030\030\030\364\241\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\201\301\356\001\000\000\000\000\000\000\000\000\023\005\207\040\202\013\012\256\353\072\000\000\000\000\111\105\116\104\256\102\140\202' > "$WEB_DIR/icon-512.png"

log "wrote $WEB_DIR/sw.js, offline.js, manifest.webmanifest and icon-192.png/icon-512.png"
