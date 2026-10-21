const V="rrs-v1";const SHELL=["./","index.html","manifest.webmanifest","icon-192.png","icon-512.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(SHELL)));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{const u=new URL(e.request.url);if(e.request.method!=="GET")return;
  if(/supabase\.co$/.test(u.hostname))return; // live data is never cached here
  if(u.origin===location.origin&&(e.request.mode==="navigate"||u.pathname.endsWith("/index.html"))){
    e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(V).then(x=>x.put("index.html",c));return r}).catch(()=>caches.match("index.html")));return}
  if(u.origin===location.origin||/cdnjs\.cloudflare\.com|cdn\.jsdelivr\.net|fonts\.(googleapis|gstatic)\.com/.test(u.hostname)){
    e.respondWith(caches.match(e.request).then(hit=>{const net=fetch(e.request).then(r=>{if(r.ok||r.type==="opaque"){const c=r.clone();caches.open(V).then(x=>x.put(e.request,c))}return r}).catch(()=>hit);return hit||net}))}
});