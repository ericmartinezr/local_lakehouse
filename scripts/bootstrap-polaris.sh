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

# Helper: check if a Polaris resource exists via GET
_exists() {
  curl -s -S -o /dev/null -w "%{http_code}" -X GET "$1" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Polaris-Realm: ${REALM}" | grep -q 200
}

API="http://polaris:8181/api/management/v1"

echo "[2/8] Creando catalogo 'lakehouse_catalog'..."
if _exists "$API/catalogs/lakehouse_catalog"; then
  echo "  Catalogo 'lakehouse_catalog' ya existe, saltando..."
else
  curl --fail-with-body -s -S -X POST "$API/catalogs" \
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
fi

echo "[3/8] Creando principal 'lakehouse_user'..."
if _exists "$API/principals/lakehouse_user"; then
  echo "  Principal 'lakehouse_user' ya existe (credenciales del primer inicio)."
  USER_CLIENT_ID="lakehouse_user"
  USER_CLIENT_SECRET="<misma que en el primer inicio>"
else
  PRINCIPAL_RESPONSE=$(curl --fail-with-body -s -S -X POST "$API/principals" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Polaris-Realm: ${REALM}" \
    -H "Content-Type: application/json" \
    -d '{"principal": {"name": "lakehouse_user", "properties": {}}}')

  USER_CLIENT_ID=$(echo "$PRINCIPAL_RESPONSE" | jq -r '.credentials.clientId')
  USER_CLIENT_SECRET=$(echo "$PRINCIPAL_RESPONSE" | jq -r '.credentials.clientSecret')
  echo "  Principal 'lakehouse_user' creado."
fi

echo "[4/8] Creando principal role 'lakehouse_role'..."
if _exists "$API/principal-roles/lakehouse_role"; then
  echo "  Principal role 'lakehouse_role' ya existe, saltando..."
else
  curl --fail-with-body -s -S -X POST "$API/principal-roles" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Polaris-Realm: ${REALM}" \
    -H "Content-Type: application/json" \
    -d '{"principalRole": {"name": "lakehouse_role", "properties": {}}}' > /dev/null
  echo "  Principal role 'lakehouse_role' creado."
fi

echo "[5/8] Creando catalog role 'lakehouse_catalog_role'..."
if _exists "$API/catalogs/lakehouse_catalog/catalog-roles/lakehouse_catalog_role"; then
  echo "  Catalog role 'lakehouse_catalog_role' ya existe, saltando..."
else
  curl --fail-with-body -s -S -X POST "$API/catalogs/lakehouse_catalog/catalog-roles" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Polaris-Realm: ${REALM}" \
    -H "Content-Type: application/json" \
    -d '{"catalogRole": {"name": "lakehouse_catalog_role", "properties": {}}}' > /dev/null
  echo "  Catalog role 'lakehouse_catalog_role' creado."
fi

echo "[6/8] Asignando principal role al principal..."
if curl -s -S "$API/principals/lakehouse_user/principal-roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" | jq -e '.roles[] | select(.name == "lakehouse_role")' > /dev/null 2>&1; then
  echo "  Principal role ya asignado, saltando..."
else
  curl --fail-with-body -s -S -X PUT "$API/principals/lakehouse_user/principal-roles" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Polaris-Realm: ${REALM}" \
    -H "Content-Type: application/json" \
    -d '{"principalRole": {"name": "lakehouse_role"}}' > /dev/null
  echo "  Principal role asignado a 'lakehouse_user'."
fi

echo "[7/8] Asignando catalog role al principal role..."
OUTPUT=$(curl -s -S -X PUT "$API/principal-roles/lakehouse_role/catalog-roles/lakehouse_catalog" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"catalogRole": {"name": "lakehouse_catalog_role"}}' 2>&1)
RC=$?
if [ $RC -eq 0 ] || echo "$OUTPUT" | grep -q "duplicate key"; then
  echo "  Catalog role asignado a 'lakehouse_role'."$([ $RC -ne 0 ] && echo " (ya existia)")
else
  echo "ERROR: No se pudo asignar el catalog role: $OUTPUT"
  exit 1
fi

echo "[8/8] Otorgando privilegio CATALOG_MANAGE_CONTENT..."
OUTPUT=$(curl -s -S -X PUT "$API/catalogs/lakehouse_catalog/catalog-roles/lakehouse_catalog_role/grants" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Polaris-Realm: ${REALM}" \
  -H "Content-Type: application/json" \
  -d '{"type": "catalog", "privilege": "CATALOG_MANAGE_CONTENT"}' 2>&1)
RC=$?
if [ $RC -eq 0 ] || echo "$OUTPUT" | grep -q "duplicate key"; then
  echo "  Privilegios otorgados."$([ $RC -ne 0 ] && echo " (ya existian)")
else
  echo "ERROR: No se pudo otorgar privilegio: $OUTPUT"
  exit 1
fi

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
echo "  PostgreSQL:      jdbc:postgresql://localhost:5432/polaris"
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
