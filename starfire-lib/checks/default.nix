{
  core-inputs,
  user-inputs,
  starfire-lib,
  starfire-config,
}: let
  inherit (core-inputs.flake-utils-plus.lib) filterPackages;
  inherit (core-inputs.nixpkgs.lib) assertMsg foldl mapAttrs callPackageWith;

  user-checks-root = starfire-lib.fs.get-starfire-file "checks";
in {
  check = {
    ## Create flake output packages.
    ## Example Usage:
    ## ```nix
    ## create-checks { inherit channels; src = ./my-checks; overrides = { inherit another-check; }; alias = { default = "another-check"; }; }
    ## ```
    ## Result:
    ## ```nix
    ## { another-check = ...; my-check = ...; default = ...; }
    ## ```
    #@ Attrs -> Attrs
    create-checks = {
      channels,
      src ? user-checks-root,
      pkgs ? channels.nixpkgs,
      overrides ? {},
      alias ? {},
    }: let
      user-checks = starfire-lib.fs.get-default-nix-files-recursive src;
      create-check-metadata = check: let
        extra-inputs =
          pkgs
          // {
            inherit channels;
            lib = starfire-lib.internal.system-lib;
            inputs = starfire-lib.flake.without-src user-inputs;
            namespace = starfire-config.namespace;
          };
      in {
        name = builtins.unsafeDiscardStringContext (starfire-lib.path.get-parent-directory check);
        drv = callPackageWith extra-inputs check {};
      };
      checks-metadata = builtins.map create-check-metadata user-checks;
      merge-checks = checks: metadata:
        checks
        // {
          ${metadata.name} = metadata.drv;
        };
      checks-without-aliases = foldl merge-checks {} checks-metadata;
      aliased-checks = mapAttrs (name: value: checks-without-aliases.${value}) alias;
      checks = checks-without-aliases // aliased-checks // overrides;
    in
      filterPackages pkgs.system checks;
  };
}
