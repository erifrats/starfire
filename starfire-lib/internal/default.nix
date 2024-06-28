{
  core-inputs,
  user-inputs,
  starfire-lib,
  starfire-config,
}: let
  inherit (core-inputs.nixpkgs.lib) fix filterAttrs callPackageWith isFunction;

  core-inputs-libs = starfire-lib.flake.get-libs (starfire-lib.flake.without-self core-inputs);
  user-inputs-libs = starfire-lib.flake.get-libs (starfire-lib.flake.without-self user-inputs);

  starfire-top-level-lib = filterAttrs (name: value: !builtins.isAttrs value) starfire-lib;

  base-lib = starfire-lib.attrs.merge-shallow [
    core-inputs.nixpkgs.lib
    core-inputs-libs
    user-inputs-libs
    starfire-top-level-lib
    {starfire = starfire-lib;}
  ];

  user-lib-root = starfire-lib.fs.get-starfire-file "lib";
  user-lib-modules = starfire-lib.fs.get-default-nix-files-recursive user-lib-root;

  user-lib = fix (
    user-lib: let
      attrs = {
        inherit (user-inputs) src;
        inputs = starfire-lib.flake.without-starfire-inputs user-inputs;
        starfire-inputs = core-inputs;
        namespace = starfire-config.namespace;
        lib = starfire-lib.attrs.merge-shallow [
          base-lib
          {"${starfire-config.namespace}" = user-lib;}
        ];
      };
      libs =
        builtins.map
        (
          path: let
            imported-module = import path;
          in
            if isFunction imported-module
            then callPackageWith attrs path {}
            # the only difference is that there is no `override` and `overrideDerivation` on returned value
            else imported-module
        )
        user-lib-modules;
    in
      starfire-lib.attrs.merge-deep libs
  );

  system-lib = starfire-lib.attrs.merge-shallow [
    base-lib
    {"${starfire-config.namespace}" = user-lib;}
  ];
in {
  internal = {
    inherit system-lib user-lib;
  };
}
