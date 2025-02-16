{ pkgs, ... }:
pkgs.runCommand "get-keys" {
  src = ./package.xml;
  buildInputs = [ pkgs.xmlstarlet ];
} 
''
    build_depend=$(xmlstarlet sel -t -v /package/build_depend $src)
    run_depend=$(xmlstarlet sel -t -v /package/run_depend $src)

    mkdir -p $out
    echo $build_depend > $out/txt
''
