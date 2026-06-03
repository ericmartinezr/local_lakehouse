#!/bin/sh
set -e

apk add --no-cache jq

echo ""
echo "=========================================="
echo "  Configurando Apache Polaris..."
echo "=========================================="
echo ""

echo "[1/8] Obteniendo token de acceso root..."
TOKEN_RESPONSE=$(curl --fail-with-body -s -S -X POST http://polaris:8181/api/catalog/v1/oauth/tokens \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=client_credentials&client_id=${ROOT_CLIENT_ID}&client_secret=${ROOT_CLIENT_SECRET}&scope=PRINCIPAL_ROLE:ALL") || {
  echo "ERROR: No se pudo obtener el token de acceso"
  exit 1
}

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: No se pudo extraer el token de la respuesta"
  echo "$TOKEN_RESPONSE"
  exit 1
fi
echo "  Token obtenido exitosamente."

echo "[2/8] Creando catalogo 'lakehouse_catalog'..."
curl --fail-with-body -s -S -X POST http://polaris:8181/api/management/v1/catalogs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Polaris-Realm: ${REALM}" \
  -d '{
    "catalog": {
      "name": "lakehouse_catalog",
      "type": "INTERNAL",
      "readOnly": false,
      "properties": {
        "default-base-location": "s3://lakehouse"
      },
      "storageConfigInfo": {
        "storageType": "S3",
        "allowedLocations": ["s3://lakehouse"],
        "stsUnavailable": true,
        "endpoint": "http://localhost:4566",
        "endpointInternal": "http://floci:4566",
        "pathStyleAccess": true,
        "region": "us-east-1"
      }
    }
  }' > /dev/null
echo "  Catalogo 'lakehouse_catalog' creado."

echo "[3/8] Creando principal 'lakehouse_user'..."
PRINCIPAL_RESPONSE=$(curl --fail-with-body -s -S -X POST http://polaris:8181/api/management/v1/principals \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"principal": {"name": "lakehouse_user", "properties": {}}}')

USER_CLIENT_ID=$(echo "$PRINCIPAL_RESPONSE" | jq -r '.credentials.clientId')
USER_CLIENT_SECRET=$(echo "$PRINCIPAL_RESPONSE" | jq -r '.credentials.clientSecret')
echo "  Principal 'lakehouse_user' creado."

echo "[4/8] Creando principal role 'lakehouse_role'..."
curl --fail-with-body -s -S -X POST http://polaris:8181/api/management/v1/principal-roles \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"principalRole": {"name": "lakehouse_role", "properties": {}}}' > /dev/null
echo "  Principal role 'lakehouse_role' creado."

echo "[5/8] Creando catalog role 'lakehouse_catalog_role'..."
curl --fail-with-body -s -S -X POST "http://polaris:8181/api/management/v1/catalogs/lakehouse_catalog/catalog-roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"catalogRole": {"name": "lakehouse_catalog_role", "properties": {}}}' > /dev/null
echo "  Catalog role 'lakehouse_catalog_role' creado."

echo "[6/8] Asignando principal role al principal..."
curl --fail-with-body -s -S -X PUT "http://polaris:8181/api/management/v1/principals/lakehouse_user/principal-roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"principalRole": {"name": "lakehouse_role"}}' > /dev/null
echo "  Principal role asignado a 'lakehouse_user'."

echo "[7/8] Asignando catalog role al principal role..."
curl --fail-with-body -s -S -X PUT "http://polaris:8181/api/management/v1/principal-roles/lakehouse_role/catalog-roles/lakehouse_catalog" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"catalogRole": {"name": "lakehouse_catalog_role"}}' > /dev/null
echo "  Catalog role asignado a 'lakehouse_role'."

echo "[8/8] Otorgando privilegio CATALOG_MANAGE_CONTENT..."
curl --fail-with-body -s -S -X PUT "http://polaris:8181/api/management/v1/catalogs/lakehouse_catalog/catalog-roles/lakehouse_catalog_role/grants" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}' > /dev/null
echo "  Privilegios otorgados."

echo ""
echo "========================================================"
echo "  Configuracion de Polaris completada exitosamente!"
echo "========================================================"
echo ""
echo "  Catalogo:        lakehouse_catalog"
echo "  Storage:         S3 (Floci emulado)"
echo "  Bucket:          s3://lakehouse"
echo "  S3 Endpoint:     http://localhost:4566"
echo ""
echo "  --- Credenciales ROOT (Trino) ---"
echo "  Client ID:       ${ROOT_CLIENT_ID}"
echo "  Client Secret:   ${ROOT_CLIENT_SECRET}"
echo ""
echo "  --- Credenciales USUARIO (DuckDB) ---"
echo "  Client ID:       ${USER_CLIENT_ID}"
echo "  Client Secret:   ${USER_CLIENT_SECRET}"
echo ""
echo "  --- Endpoints ---"
echo "  Polaris REST:    http://localhost:8181/api/catalog/v1"
echo "  Polaris Mgmt:    http://localhost:8181/api/management/v1"
echo "  Trino:           http://localhost:8080"
echo "  Trino JDBC:      jdbc:trino://localhost:8080"
echo "  Floci (S3):      http://localhost:4566"
echo ""
echo "  --- Comandos DuckDB de ejemplo ---"
echo ""
echo "  CREATE SECRET polaris_secret ("
echo "    TYPE iceberg,"
echo "    CLIENT_ID '${USER_CLIENT_ID}',"
echo "    CLIENT_SECRET '${USER_CLIENT_SECRET}',"
echo "    ENDPOINT 'http://localhost:8181/api/catalog'"
echo "  );"
echo ""
echo "  ATTACH 'lakehouse_catalog' AS ls_cat ("
echo "    TYPE iceberg,"
echo "    ENDPOINT 'http://localhost:8181/api/catalog'"
echo "  );"
echo ""
echo "========================================================"

touch /tmp/polaris-setup-done
tail -f /dev/null
