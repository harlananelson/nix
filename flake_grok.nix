{
  description = "Secure Polyglot Data Science Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        rPkgs = with pkgs.rPackages; [ ggplot2 dplyr odbc keyring ];
      in
      {
        packages.default = pkgs.buildFHSUserEnv {
          name = "data-science-env";
          targetPkgs = pkgs: with pkgs; [
            R rPkgs python3 python3Packages.pandas python3Packages.pyodbc
            python3Packages.databricks-connect python3Packages.keyring
            spark unixODBC msodbcsql18 shadow libsecret
          ];
          multiPkgs = pkgs: with pkgs; [ zlib openssl ];
          profile = ''
            export TMPDIR=/tmp/user_data_science
            mkdir -p $TMPDIR
            export GIO_MODULE_DIR=${pkgs.libsecret}/lib/gio/modules
            export R_HOME=${pkgs.R}/lib/R
            mkdir -p ~/.local/share/jupyter/kernels/r_kernel
            cat > ~/.local/share/jupyter/kernels/r_kernel/kernel.json <<EOF
            {
              "argv": [
                "${pkgs.R}/bin/R",
                "--slave",
                "-e",
                "IRkernel::main()",
                "--args",
                "{connection_file}"
              ],
              "display_name": "R",
              "language": "R",
              "env": {
                "LD_LIBRARY_PATH": "${pkgs.lib.makeLibraryPath [ pkgs.unixODBC pkgs.msodbcsql18 ]}",
                "PATH": "${pkgs.lib.makeBinPath [ pkgs.R pkgs.unixODBC ]}"
              }
            }
            EOF
            ${pkgs.R}/bin/R -e "install.packages('languageserver', repos='https://cloud.r-project.org')"
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            R rPkgs python3 python3Packages.pandas python3Packages.pyodbc
            python3Packages.databricks-connect python3Packages.keyring
            spark unixODBC msodbcsql18 shadow libsecret
          ];
          shellHook = ''
            export TMPDIR=/tmp/user_data_science
            mkdir -p $TMPDIR
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.unixODBC pkgs.msodbcsql18 ]}
            export GIO_MODULE_DIR=${pkgs.libsecret}/lib/gio/modules
          '';
        };
      });
}