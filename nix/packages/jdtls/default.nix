{ stdenv, fetchzip, lib, pkgs }:
stdenv.mkDerivation rec {
  pname = "jdtls";
  version = "1.9.0";
  version_date = "202203031534";

  src = fetchzip {
    url =
      "https://download.eclipse.org/jdtls/milestones/${version}/jdt-language-server-${version}-${version_date}.tar.gz";
    #sha256 = "0pq3njzl8knp1jsgp6rd9gyippzb6wrwdif6rjjqw9q2bjbi2xz0";
    sha256 = "sha256-q1zBsMtAUEQLpWyf2g3F6W3ZMtKm5Yu1QW5TcW3+prY=";
    stripRoot = false;
  };

  buildInputs = with pkgs; [ rsync ];
  installPhase = ''
    mkdir -p $out
    rsync -av --no-group $src/ $out
  '';

  meta = with lib; {
    description = "Java Langauge Server";
    homepage = "https://github.com/eclipse/eclipse.jdt.ls";
    license = licenses.epl20;
    maintainers = with maintainers; [ trevorwhitney ];
    platforms = platforms.linux ++ platforms.darwin;
  };
}
