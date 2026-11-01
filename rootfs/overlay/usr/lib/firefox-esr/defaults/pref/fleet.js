// FleetOS: Firefox tuned for a 2 GB dual-core Cortex-A15 with no usable GPU video decoding.
// YouTube picks VP9/AV1 when the browser claims to support them; those are software-decoded and far too heavy
// here. With them off it serves H.264 (avc1), which the CPU can play at 360p-720p.
pref("media.mediasource.vp9.enabled", false);
pref("media.av1.enabled", false);
pref("media.mediasource.webm.enabled", false);
// Fewer content processes = less RAM (default 8)
pref("dom.ipc.processCount", 2);
pref("dom.ipc.processPrelaunch.enabled", false);
// Cache in RAM, not on the eMMC
pref("browser.cache.disk.enable", false);
pref("browser.cache.memory.enable", true);
pref("browser.cache.memory.capacity", 65536);
pref("browser.sessionstore.interval", 120000);
pref("browser.tabs.unloadOnLowMemory", true);
// No animations: pages that honour "reduced motion" (YouTube included) skip transitions, and the UI paints less
pref("ui.prefersReducedMotion", 1);
pref("toolkit.cosmeticAnimations.enabled", false);
pref("browser.tabs.animate", false);
pref("browser.fullscreen.animate", false);
pref("browser.download.animateNotifications", false);
// No speculative network/CPU work, no push or notification machinery, no blocked-autoplay surprises
pref("network.prefetch-next", false);
pref("network.dns.disablePrefetch", true);
pref("network.predictor.enabled", false);
pref("dom.push.enabled", false);
pref("permissions.default.desktop-notification", 2);
pref("media.autoplay.default", 5);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
pref("browser.search.suggest.enabled", false);
// Plain new tab and start page (the default one loads sponsored tiles and thumbnails)
pref("browser.newtabpage.enabled", false);
pref("browser.startup.homepage", "about:blank");
pref("extensions.screenshots.disabled", true);
pref("browser.translations.enable", false);
// Less background work
pref("general.smoothScroll", false);
pref("toolkit.telemetry.enabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("extensions.pocket.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
pref("browser.newtabpage.activity-stream.telemetry", false);
