{ choose
, pname
, desktopName
, description
, chooseLicense
, }:

{ lib
, stdenv
, fetchurl
, patchelf
, makeWrapper
, makeDesktopItem
, copyDesktopItems
, coreutils
, findutils
, unzip
, gnused
, gnugrep
, file
, libxcrypt
, libsecret
, libnotify
, cups
, libdbusmenu
, lldb
, e2fsprogs
, pam
, graphviz
, wrapGAppsHook
, autoPatchelfHook
, jetbrainsruntime
, fsnotifier }:

let

  jbPackages = import ../../data/packages.nix;
  latest = builtins.head (choose jbPackages."IntelliJ IDEA");

  src = fetchurl {
    url = latest.downloadUri;
    sha256 = latest.sha256;
  };

  version = builtins.replaceStrings [" "] ["+"] latest.build.version;

  longDescription = ''
    IDE for Java SE, Groovy & Scala development Powerful
    environment for building Google Android apps Integration
    with JUnit, TestNG, popular SCMs, Ant & Maven. Also known
    as IntelliJ.
  '';

  desktopItem = makeDesktopItem {
    name = pname;
    inherit desktopName;
    genericName = "Integrated Development Environment";
    exec = pname;
    icon = pname;
    comment = lib.replaceStrings ["\n"] [" "] longDescription;
    categories = [ "Development" "IDE" "Java" ];
    mimeTypes = [
      "text/x-kotlin"
      "text/x-java-source"
      "text/x-scala"
      "application/xml"
      "application/json"
    ];
    startupNotify = true;
    startupWMClass = "jetbrains-idea";
  };


  remote-dev-server = stdenv.mkDerivation {
    pname = "remote-dev-server";
    inherit version src;

    dontStrip = true;
    dontBuild = true;
    dontPatchShebangs = true;

    installPhase = ''
      runHook preInstall
      mv plugins/remote-dev-server $out
      runHook postInstall
    '';
  };

in

stdenv.mkDerivation {
  inherit pname version src;

  postUnpack = ''
    pushd idea-*
    rm -fr jbr
    grep -Ev '^\s+"javaExecutablePath":' product-info.json > product-info.json.new
    mv product-info.json.new product-info.json
    popd
  '';

  dontStrip = true;

  nativeBuildInputs = [ makeWrapper patchelf unzip gnused file autoPatchelfHook wrapGAppsHook copyDesktopItems ];

  buildInputs = [ stdenv.cc.cc.lib libxcrypt cups libdbusmenu lldb pam ];

  patches = [ ./launcher.patch ];

  postPatch = ''
    substituteInPlace bin/idea.sh \
      --subst-var-by PATH                '${lib.makeBinPath [ coreutils gnugrep graphviz ]}' \
      --subst-var-by NOTIFY_SEND         '${libnotify}/bin/notify-send' \
      --subst-var-by NATIVE_LIBRARY_PATH '${lib.makeLibraryPath [ libsecret libnotify e2fsprogs ]}'
  '';

  preFixup = ''
    gappsWrapperArgs+=(--set IDEA_JDK ${jetbrainsruntime.passthru.home})
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{lib/$pname,bin,share/pixmaps,libexec/$pname}

    # Remove binaries that are incompatible with x86_64-linux so that
    # autopatchelf doesn’t get confused.
    rm -r plugins/maven/lib/maven3/lib/jansi-native/{freebsd32,freebsd64,linux32,osx,windows32,windows64}

    rm plugins/webp/lib/libwebp/linux/libwebp_jni.so # 32-bit x86

    rm -r plugins/cwm-plugin/quiche-native/{darwin-aarch64,darwin-x86-64,linux-aarch64,win32-x86-64}

    rm -r plugins/android/resources/native/{mac,mac_arm,win}

    rm -f plugins/tailwindcss/server/fsevents* # macOS

    # Windows, macOS and musl alternatives
    rm -f plugins/tailwindcss/server/node.napi.musl-*.node
    file -i ./plugins/tailwindcss/server/node.napi.* \
      | grep -v application/x-sharedlib | cut -f1 -d: | xargs -r rm

    rm -r plugins/remote-dev-server
    ln -s ${remote-dev-server} plugins/remote-dev-server

    cp -a . $out/lib/$pname/
    ln -s $out/lib/$pname/bin/idea.svg $out/share/pixmaps/$pname.svg
    ln -s $out/lib/$pname/bin/idea.png $out/share/pixmaps/$pname.png
    ln -s $out/lib/$pname/bin/idea.sh $out/bin/$pname
    ln -sf ${fsnotifier}/bin/fsnotifier $out/lib/$pname/bin

    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

  meta = with lib; {
    homepage = "https://www.jetbrains.com/idea/";
    inherit description longDescription;
    maintainers = with maintainers; [ liff ];
    license = chooseLicense lib.licenses;
    platforms = [ "x86_64-linux" ];
  };
}
