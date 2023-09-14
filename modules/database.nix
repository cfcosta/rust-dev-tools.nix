{ pkgs, utils, packageName }:
let
  scripts = creds:
    with pkgs; {
      psql = ''
        export PGHOST="${creds.host}"
        export PGUSER="${creds.user}"
        export PGPASSWD="${creds.password}"
        export PGPORT="${creds.port}"

        ${pgcli}/bin/pgcli "${creds.database}"
      '';
    };
in {
  fromDockerCompose = file: serviceName:
    let
      composeConfig = utils.fromYAML file;

      creds = {
        user =
          composeConfig.services."${serviceName}".environment.POSTGRES_USER or "postgres";
        password =
          composeConfig.services."${serviceName}".environment.POSTGRES_PASSWORD or "postgres";
        host = "localhost";
        port =
          composeConfig.services."${serviceName}".environment.POSTGRES_PORT or "5432";
        database =
          composeConfig.services."${serviceName}".environment.POSTGRES_DB or "postgres";
      };
    in pkgs.lib.mapAttrsToList
    (name: script: pkgs.writeShellScriptBin "${packageName}-${name}" script)
    (scripts creds);
}
