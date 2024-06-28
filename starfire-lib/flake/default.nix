{
  core-inputs,
  user-inputs,
  starfire-lib,
  starfire-config,
}: let
  inherit (core-inputs.nixpkgs.lib) assertMsg foldl filterAttrs const;
in rec {
  flake = rec {
    ## Remove the `self` attribute from an attribute set.
    ## Example Usage:
    ## ```nix
    ## without-self { self = {}; x = true; }
    ## ```
    ## Result:
    ## ```nix
    ## { x = true; }
    ## ```
    #@ Attrs -> Attrs
    without-self = flake-inputs: builtins.removeAttrs flake-inputs ["self"];

    ## Remove the `src` attribute from an attribute set.
    ## Example Usage:
    ## ```nix
    ## without-src { src = ./.; x = true; }
    ## ```
    ## Result:
    ## ```nix
    ## { x = true; }
    ## ```
    #@ Attrs -> Attrs
    without-src = flake-inputs: builtins.removeAttrs flake-inputs ["src"];

    ## Remove the `src` and `self` attributes from an attribute set.
    ## Example Usage:
    ## ```nix
    ## without-starfire-inputs { self = {}; src = ./.; x = true; }
    ## ```
    ## Result:
    ## ```nix
    ## { x = true; }
    ## ```
    #@ Attrs -> Attrs
    without-starfire-inputs = starfire-lib.fp.compose without-self without-src;

    ## Remove Starfire-specific attributes so the rest can be safely passed to flake-utils-plus.
    ## Example Usage:
    ## ```nix
    ## without-starfire-options { src = ./.; x = true; }
    ## ```
    ## Result:
    ## ```nix
    ## { x = true; }
    ## ```
    #@ Attrs -> Attrs
    without-starfire-options = flake-options:
      builtins.removeAttrs
      flake-options
      [
        "systems"
        "modules"
        "overlays"
        "packages"
        "outputs-builder"
        "outputsBuilder"
        "packagesPrefix"
        "hosts"
        "homes"
        "channels-config"
        "templates"
        "checks"
        "alias"
        "starfire"
      ];

    ## Transform an attribute set of inputs into an attribute set where the values are the inputs' `lib` attribute. Entries without a `lib` attribute are removed.
    ## Example Usage:
    ## ```nix
    ## get-lib { x = nixpkgs; y = {}; }
    ## ```
    ## Result:
    ## ```nix
    ## { x = nixpkgs.lib; }
    ## ```
    #@ Attrs -> Attrs
    get-libs = attrs: let
      # @PERF(jakehamilton): Replace filter+map with a fold.
      attrs-with-libs =
        filterAttrs
        (name: value: builtins.isAttrs (value.lib or null))
        attrs;
      libs =
        builtins.mapAttrs (name: input: input.lib) attrs-with-libs;
    in
      libs;
  };

  mkFlake = full-flake-options: let
    namespace = starfire-config.namespace or "internal";
    custom-flake-options = flake.without-starfire-options full-flake-options;
    alias = full-flake-options.alias or {};
    homes = starfire-lib.home.create-homes (full-flake-options.homes or {});
    systems = starfire-lib.system.create-systems {
      systems = full-flake-options.systems or {};
      homes = full-flake-options.homes or {};
    };
    hosts = starfire-lib.attrs.merge-shallow [(full-flake-options.systems.hosts or {}) systems homes];
    templates = starfire-lib.template.create-templates {
      overrides = full-flake-options.templates or {};
      alias = alias.templates or {};
    };
    nixos-modules = starfire-lib.module.create-modules {
      src = starfire-lib.fs.get-starfire-file "modules/nixos";
      overrides = full-flake-options.modules.nixos or {};
      alias = alias.modules.nixos or {};
    };
    darwin-modules = starfire-lib.module.create-modules {
      src = starfire-lib.fs.get-starfire-file "modules/darwin";
      overrides = full-flake-options.modules.darwin or {};
      alias = alias.modules.darwin or {};
    };
    home-modules = starfire-lib.module.create-modules {
      src = starfire-lib.fs.get-starfire-file "modules/home";
      overrides = full-flake-options.modules.home or {};
      alias = alias.modules.home or {};
    };
    overlays = starfire-lib.overlay.create-overlays {
      inherit namespace;
      extra-overlays = full-flake-options.extra-exported-overlays or {};
    };

    outputs-builder = channels: let
      user-outputs-builder =
        full-flake-options.outputs-builder
        or full-flake-options.outputsBuilder
        or (const {});
      user-outputs = user-outputs-builder channels;
      packages = starfire-lib.package.create-packages {
        inherit channels namespace;
        overrides = (full-flake-options.packages or {}) // (user-outputs.packages or {});
        alias = alias.packages or {};
      };
      shells = starfire-lib.shell.create-shells {
        inherit channels;
        overrides = (full-flake-options.shells or {}) // (user-outputs.devShells or {});
        alias = alias.shells or {};
      };
      checks = starfire-lib.check.create-checks {
        inherit channels;
        overrides = (full-flake-options.checks or {}) // (user-outputs.checks or {});
        alias = alias.checks or {};
      };

      outputs = {
        inherit packages checks;

        devShells = shells;
      };
    in
      starfire-lib.attrs.merge-deep [user-outputs outputs];

    flake-options =
      custom-flake-options
      // {
        inherit hosts templates;
        inherit (user-inputs) self;

        lib = starfire-lib.internal.user-lib;
        inputs = starfire-lib.flake.without-src user-inputs;

        nixosModules = nixos-modules;
        darwinModules = darwin-modules;
        homeModules = home-modules;

        channelsConfig = full-flake-options.channels-config or {};

        channels.nixpkgs.overlaysBuilder = starfire-lib.overlay.create-overlays-builder {
          inherit namespace;
          extra-overlays = full-flake-options.overlays or [];
        };

        outputsBuilder = outputs-builder;

        starfire = {
          config = starfire-config;
          raw-config = full-flake-options.starfire or {};
          user-lib = starfire-lib.internal.user-lib;
        };
      };

    flake-utils-plus-outputs =
      core-inputs.flake-utils-plus.lib.mkFlake flake-options;

    flake-outputs =
      flake-utils-plus-outputs
      // {
        inherit overlays;
      };
  in
    flake-outputs;
}
