{
  core-inputs,
  user-inputs,
  starfire-lib,
  starfire-config,
}: let
  inherit (core-inputs.flake-utils-plus.lib) filterPackages allSystems;
  inherit (core-inputs.nixpkgs.lib) assertMsg foldl mapAttrs filterAttrs callPackageWith;

  user-packages-root = starfire-lib.fs.get-starfire-file "packages";
in {
  package = rec {
    ## Create flake output packages.
    ## Example Usage:
    ## ```nix
    ## create-packages { inherit channels; src = ./my-packages; overrides = { inherit another-package; }; alias.default = "another-package"; }
    ## ```
    ## Result:
    ## ```nix
    ## { another-package = ...; my-package = ...; default = ...; }
    ## ```
    #@ Attrs -> Attrs
    create-packages = {
      channels,
      src ? user-packages-root,
      pkgs ? channels.nixpkgs,
      overrides ? {},
      alias ? {},
      namespace ? starfire-config.namespace,
    }: let
      user-packages = starfire-lib.fs.get-default-nix-files-recursive src;
      create-package-metadata = package: let
        namespaced-packages = {
          ${namespace} = packages-without-aliases;
        };
        extra-inputs =
          pkgs
          // namespaced-packages
          // {
            inherit channels namespace;
            lib = starfire-lib.internal.system-lib;
            pkgs = pkgs // namespaced-packages;
            inputs = user-inputs;
          };
      in {
        name = builtins.unsafeDiscardStringContext (starfire-lib.path.get-parent-directory package);
        drv = let
          pkg = callPackageWith extra-inputs package {};
        in
          pkg
          // {
            meta =
              (pkg.meta or {})
              // {
                starfire = {
                  path = package;
                };
              };
          };
      };
      packages-metadata = builtins.map create-package-metadata user-packages;
      merge-packages = packages: metadata:
        packages
        // {
          ${metadata.name} = metadata.drv;
        };
      packages-without-aliases = foldl merge-packages {} packages-metadata;
      aliased-packages = mapAttrs (name: value: packages-without-aliases.${value}) alias;
      packages = packages-without-aliases // aliased-packages // overrides;
    in
      filterPackages pkgs.system packages;
  };
}
