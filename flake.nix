{
	description = "OpenDeck - software for Elgato Stream Deck and other stream controllers";

	inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

	outputs =
	{ self, nixpkgs }:
	let
	systems = [
		"x86_64-linux"
		"aarch64-linux"
	];
	forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
	in
	{
		packages = forAllSystems (pkgs: rec {
			opendeck = pkgs.callPackage ./package.nix { };
			default = opendeck;
		});

		overlays.default = final: _prev: {
			opendeck = final.callPackage ./package.nix { };
		};

		nixosModules.default =
		{
			config,
			lib,
			pkgs,
			...
		}:
		let
		cfg = config.programs.opendeck;
		in
		{
			options.programs.opendeck = {
				enable = lib.mkEnableOption "OpenDeck, with udev rules for Stream Deck devices";
				package = lib.mkOption {
					type = lib.types.package;
					default = self.packages.${pkgs.stdenv.hostPlatform.system}.opendeck;
					defaultText = lib.literalExpression "opendeck.packages.\${system}.opendeck";
					description = "The OpenDeck package to use.";
				};
				systemd.enable = lib.mkOption {
					type = lib.types.bool;
					default = true;
					description = "Run OpenDeck as a systemd user service, started hidden in the tray with the graphical session.";
				};
			};

			config = lib.mkIf cfg.enable {
				environment.systemPackages = [ cfg.package ];
				# Installs lib/udev/rules.d/40-streamdeck.rules (uaccess for the logged-in user)
				services.udev.packages = [ cfg.package ];

				systemd.user.services.opendeck = lib.mkIf cfg.systemd.enable {
					description = "OpenDeck stream controller software";
					partOf = [ "graphical-session.target" ];
					after = [ "graphical-session.target" ];
					wantedBy = [ "graphical-session.target" ];
					# Plugins spawn node/wine etc. from PATH, so expose the system and user profiles
					path = [
						"/run/wrappers"
						"/etc/profiles/per-user/%u"
						"/run/current-system/sw"
					];
					serviceConfig = {
						ExecStart = "${lib.getExe cfg.package} --hide";
						Restart = "on-failure";
						RestartSec = 3;
					};
				};
			};
		};

		formatter = forAllSystems (pkgs: pkgs.nixfmt);
	};
}
