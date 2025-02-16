{

  description = "builds package.xml based ros packages as nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nix-ros-overlay = {
      url = "github:lopsided98/nix-ros-overlay/develop";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rosdistro-src = { url = "github:ros/rosdistro"; flake = false; };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-ros-overlay, rosdistro-src, flake-utils } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-ros-overlay.overlays.default ];
      };
      
      # derivations are from ros2nix
      
      # rosdistro with offline package list
      rosdistro = pkgs.stdenv.mkDerivation {
        pname = "rosdistro";
        version = rosdistro-src.lastModifiedDate;
        src = rosdistro-src;
        postPatch = ''
          substituteInPlace rosdep/sources.list.d/20-default.list \
            --replace-fail https://raw.githubusercontent.com/ros/rosdistro/master/ file://${placeholder "out"}/
        '';
        postInstall = ''
          mkdir -p $out
          cp -r * $out
        '';
      };

      # rosdep with offline package list
      rosdep-unwrapped = pkgs.python3Packages.rosdep.overrideAttrs ({ postPatch ? "", ...}: {
        postPatch = postPatch + ''
          substituteInPlace src/rosdep2/rep3.py \
            --replace-fail https://raw.githubusercontent.com/ros/rosdistro/master/ file://${rosdistro}/
        '';
      });

      # run rosdep update to cache packages
      rosdep-cache = pkgs.stdenv.mkDerivation {
        pname = "rosdep-cache";
        version = rosdistro-src.lastModifiedDate;
        nativeBuildInputs = [
          rosdep-unwrapped
        ];
        ROSDEP_SOURCE_PATH = "${rosdistro}/rosdep/sources.list.d";
        ROSDISTRO_INDEX_URL = "file://${rosdistro}/index-v4.yaml";
        ROS_HOME = placeholder "out";
        buildCommand = ''
          mkdir -p $out
          rosdep update
        '';
      };

      # rosdep with offline database
      rosdep = pkgs.python3Packages.rosdep.overrideAttrs ({ postFixup ? "", ...}: {
        postFixup = postFixup + ''
          wrapProgram $out/bin/rosdep --set-default ROS_HOME ${rosdep-cache}
        '';
      });

      get-packages = key: distro:
        let cmd = pkgs.runCommand "get-packages" {
          src = ./.;
          env = {
            ROS_HOME = "${rosdep-cache}";
            ROSDEP_SOURCE_PATH = "{rosdistro}/rosdep/sources.list.d";
            ROSDISTRO_INDEX_URL = "file://${rosdistro}/index-v4.yaml";
            ROS_OS_OVERRIDE = "nixos";
            ROS_PYTHON_VERSION = 3;
          };
          buildInputs = [ rosdep pkgs.xmlstarlet ];
        }
        ''
            for key in $(xml sel -t -v "/package/${key}" $src/package.xml); do
              if dep="$(rosdep resolve "$key" 2>/dev/null)"; then
                printf '%s\n' "$dep" | sed '/^#/d' | tr ' ' '\n' >> $out
              else
                echo "''${key//_/-}" >> $out
              fi
            done
        '';
        pkg-list = with pkgs.lib; splitString "\n" (trim (builtins.readFile cmd));
        # rospkg-str-to-deriv = with pkgs.lib; str: attrByPath (splitString "." str) null pkgs.rosPackages.${distro};
        rospkg-str-to-deriv = with pkgs.lib; str: attrByPath (splitString "." str) null pkgs.rosPackages.${distro};
        pkg-str-to-deriv = with pkgs.lib; str: attrByPath (splitString "." str) (rospkg-str-to-deriv str) pkgs;
        deriv-list = map pkg-str-to-deriv pkg-list;
        in deriv-list;

      build-legacy-package = src: distro: pkgs.stdenv.mkDerivation {};
      # deriv = pkgs.stdenv.mkDerivation {
      #   buildInputs = builtins.readFile ./;
      # };
      in
      {
        lib = { inherit build-legacy-package; };
        packages.default = get-packages;
        devShells.default = with pkgs; mkShell {
          inputsFrom = [ get-packages ];
          packages = [ rosdep superflore pyright ];
        };
      }
    );
    # let pkgs = nixpkgs.legacyPackages."x86_64-linux";
    # in
    # {
    # packages."x86_64-linux".default = import ./default.nix pkgs;
  # };
}
