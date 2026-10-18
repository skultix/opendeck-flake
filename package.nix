{
	lib,
	stdenv,
	stdenvNoCC,
	fetchFromGitHub,
	rustPlatform,
	cargo-tauri,
	deno,
	pkg-config,
	wrapGAppsHook3,
	glib-networking,
	openssl,
	webkitgtk_4_1,
	libsoup_3,
	libayatana-appindicator,
	udev,
	dbus,
	fontconfig,
	freetype,
	libgit2,
	zlib,
	libxkbcommon,
	libx11,
	libxcb,
	libxtst,
	libxi,
	libei,
	wayland,
}:

let
version = "2.14.1";

src = fetchFromGitHub {
	owner = "nekename";
	repo = "OpenDeck";
	tag = "v${version}";
	hash = "sha256-pI2duQ1xc72Bp0DMqBeUtrNeywL81UhSUooy5Op1qRc=";
};

rustTarget = stdenv.hostPlatform.rust.rustcTarget;

# Built-in "Starter Pack" plugin. Upstream builds this from build.rs by
# shelling out to deno + `cargo install`, which can't work offline, so it is
# built as its own package and laid out the way build.ts would.
starterpack = rustPlatform.buildRustPackage {
	pname = "opendeck-starterpack";
	inherit version src;

	sourceRoot = "${src.name}/plugins/com.amansprojects.starterpack.sdPlugin";

	cargoHash = "sha256-maCwWfZzsko2t4BtwJJiIBqK4lZYuUZgz4MR7YvWAy4=";

	nativeBuildInputs = [ pkg-config ];

	buildInputs = [
		libxkbcommon
		libx11
		libxcb
		libxtst
		libxi
		libei
		wayland
	];

	postInstall = ''
	plugin=$out/share/opendeck/plugins/com.amansprojects.starterpack.sdPlugin
	mkdir -p $plugin/${rustTarget}
	cp -r assets/. $plugin/
	mv $out/bin $plugin/${rustTarget}/bin
	'';

	meta.mainProgram = "opendeck-starterpack";
};

# npm dependencies for the SvelteKit frontend, fetched by deno.
# Native modules (rollup, lightningcss, tailwind oxide) are platform
# specific, so the hash differs per system.
denoDeps = stdenvNoCC.mkDerivation {
	pname = "opendeck-deno-deps";
	inherit version src;

	nativeBuildInputs = [ deno ];

	dontConfigure = true;
	dontFixup = true;

	buildPhase = ''
	runHook preBuild
	export HOME=$TMPDIR
	export DENO_DIR=$TMPDIR/deno
	export DENO_NO_UPDATE_CHECK=1
	deno install --frozen
	runHook postBuild
	'';

	installPhase = ''
	runHook preInstall
	# drop non-deterministic caches
	rm -f node_modules/.deno/.setup-cache.bin node_modules/.deno/.deno.lock*
	find node_modules -name '.deno.lock*' -delete
	cp -r node_modules $out
	runHook postInstall
	'';

	outputHashMode = "recursive";
	outputHashAlgo = "sha256";
	outputHash =
	{
		x86_64-linux = "sha256-yFZIWVJPaqaj8F2HB8LGJSj20I9bQTQ+ahtkRzHPL/Q=";
		aarch64-linux = lib.fakeHash;
	}
	.${stdenvNoCC.hostPlatform.system}
	or (throw "opendeck: no deno deps hash for ${stdenvNoCC.hostPlatform.system}");
};
in
rustPlatform.buildRustPackage {
	pname = "opendeck";
	inherit version src;

	cargoRoot = "src-tauri";
	buildAndTestSubdir = "src-tauri";

	cargoHash = "sha256-4cKyjYHNQ/2tw8QGGINehtcj23Ey22S7ZKJpvLs7IBI=";

	postPatch = ''
	# Plugins are pre-built (see `starterpack`); leave build.rs nothing to do.
	rm -rf plugins/*
	mkdir -p src-tauri/target/plugins
	cp -r ${starterpack}/share/opendeck/plugins/. src-tauri/target/plugins/
	chmod -R u+w src-tauri/target/plugins

	# The frontend is built in preBuild from the pre-fetched node_modules.
	substituteInPlace src-tauri/tauri.conf.json \
	--replace-fail '"beforeBuildCommand": "deno task build"' '"beforeBuildCommand": ""'
	'';

	nativeBuildInputs = [
		cargo-tauri.hook
		deno
		pkg-config
		wrapGAppsHook3
	];

	buildInputs = [
		glib-networking
		openssl
		webkitgtk_4_1
		libsoup_3
		libayatana-appindicator
		udev
		dbus
		fontconfig
		freetype
		libgit2
		zlib
	];

	env = {
		OPENSSL_NO_VENDOR = 1;
		LIBGIT2_NO_VENDOR = 1;
	};

	preBuild = ''
	cp -r ${denoDeps} node_modules
	chmod -R u+w node_modules
	export HOME=$TMPDIR
	export DENO_DIR=$TMPDIR/deno
	export DENO_NO_UPDATE_CHECK=1
	deno task build
	'';

	postInstall = ''
	install -Dm444 src-tauri/bundle/40-streamdeck.rules -t $out/lib/udev/rules.d
	install -Dm444 src-tauri/bundle/opendeck.metainfo.xml -t $out/share/metainfo
	'';

	preFixup = ''
	gappsWrapperArgs+=(
	# tray icon support is dlopen()ed
	--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]}
	)
	'';

	passthru = { inherit starterpack denoDeps; };

	meta = {
		description = "Linux software for your Elgato Stream Deck and other stream controllers";
		homepage = "https://github.com/nekename/OpenDeck";
		license = lib.licenses.gpl3Plus;
		mainProgram = "opendeck";
		platforms = [
			"x86_64-linux"
			"aarch64-linux"
		];
	};
}
