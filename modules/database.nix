{ pkgs, utils, options }:
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
      service = composeConfig.services."${serviceName}";

      creds = {
        user = service.environment.POSTGRES_USER or "postgres";
        password = service.environment.POSTGRES_PASSWORD or "postgres";
        host = "localhost";
        port = service.environment.POSTGRES_PORT or "5432";
        database = service.environment.POSTGRES_DB or "postgres";
      };
    in pkgs.lib.mapAttrsToList
    (name: script: pkgs.writeShellScriptBin "${options.name}-${name}" script)
    (scripts creds);
}
