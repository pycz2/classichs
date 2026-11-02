// The web build always runs the newest published version. The PWA service worker serves
// the page and the game from its cache (named after the build), so a new release used to
// show only after Ctrl-Shift-R. Before the engine starts, this asks version.json past every
// cache; when its build is not this page's, the new build's service worker takes over (its
// install skips waiting, its activation claims the page and deletes the old caches) and the
// page reloads once. Offline, or with no answer in 5 s, the cached build just starts.
// tools/web_finish.sh writes the build in and makes index.html start the engine through chsGate.
(function () {
	const BUILD = '1793656752|3402146';
	const sw = navigator.serviceWorker;
	const old = sw && sw.controller;
	const changed = sw && new Promise((resolve) => sw.addEventListener('controllerchange', resolve));
	const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

	async function check() {
		let v;
		try {
			const r = await fetch('version.json?t=' + Date.now(), { cache: 'no-store', signal: AbortSignal.timeout(5000) });
			v = await r.json();
		} catch (e) {
			return;  // offline: the cached build
		}
		if (!v.build || v.build === BUILD) return;
		const key = 'chs-reloaded-for-' + v.build;  // once per build: never a reload loop
		if (sessionStorage.getItem(key)) return;
		sessionStorage.setItem(key, '1');
		const reg = sw && await sw.getRegistration();
		try {
			if (!reg) throw new Error('no service worker');
			await reg.update();
			if (sw.controller === old) await Promise.race([changed, wait(15000).then(() => Promise.reject(new Error('no new service worker')))]);
		} catch (e) {  // drop the worker and every cache: the reload takes everything from the network
			console.warn('update:', e);
			if (reg) await reg.unregister();
			if (window.caches) for (const k of await caches.keys()) await caches.delete(k);
		}
		location.reload();
		await new Promise(() => {});  // this page never starts the old build
	}

	const ready = check().catch((e) => console.warn('update check:', e));
	window.chsBuild = BUILD;
	window.chsGate = function (engine) {  // engine.startGame waits for the check
		const start = engine.startGame.bind(engine);
		engine.startGame = (o) => ready.then(() => start(o));
	};
})();
