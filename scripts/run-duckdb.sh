#!/bin/sh
set -e

CREDS=$(docker compose logs polaris-setup 2>/dev/null | grep -A2 "USUARIO (DuckDB)")
USER_CLIENT_ID=$(echo "$CREDS" | grep "Client ID" | awk '{print $NF}')
USER_CLIENT_SECRET=$(echo "$CREDS" | grep "Client Secret" | awk '{print $NF}')

if [ -z "$USER_CLIENT_ID" ] || [ -z "$USER_CLIENT_SECRET" ]; then
  echo "ERROR: No se pudieron obtener las credenciales de los logs de polaris-setup."
  echo "Asegurate de que 'docker compose up -d' se haya ejecutado correctamente."
  exit 1
fi

echo "Usando CLIENT_ID: $USER_CLIENT_ID"

duckdb -c "
CREATE SECRET floci_s3 (
    TYPE S3,
    KEY_ID 'test',
    SECRET 'test',
    REGION 'us-east-1',
    ENDPOINT 'localhost:4566',
    URL_STYLE 'path',
    USE_SSL false
);

CREATE SECRET polaris_secret (
    TYPE iceberg,
    CLIENT_ID '$USER_CLIENT_ID',
    CLIENT_SECRET '$USER_CLIENT_SECRET',
    ENDPOINT 'http://localhost:8181/api/catalog'
);

ATTACH 'lakehouse_catalog' AS ls_cat (
    TYPE iceberg,
    SECRET polaris_secret,
    ENDPOINT 'http://localhost:8181/api/catalog',
    ACCESS_DELEGATION_MODE 'none'
);

SELECT * FROM ls_cat.demo.ventas;
"
