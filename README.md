# Lakehouse Local con Floci, Apache Iceberg, DuckDB y Trino

## ¿Qué es un Lakehouse?

Un **data lakehouse** combina la flexibilidad de un data lake (almacenamiento de datos en
formatos abiertos como Parquet) con las capacidades de gestion de un data warehouse
(transacciones ACID, evolucion de esquemas, control de versiones). Esto permite tener un
unico repositorio de datos que sirve tanto para cargas de trabajo de ciencia de datos/ML
como para analitica empresarial y BI.

## La pila (stack)

```
  +--------------------------------------------------+
  |            DuckDB (analitica local)               |
  |    Consultas SQL embebidas, sin servidor          |
  +-----------------------+--------------------------+
                          |
  +--------------------------------------------------+
  |            Trino (SQL distribuido)                |
  |    Motor de consultas federado, multi-engine      |
  +-----------------------+--------------------------+
                          |
  +--------------------------------------------------+
  |       Apache Polaris (Catalogo Iceberg)           |
  |  Almacena metadatos: esquemas, particiones,       |
  |  snapshots, permisos. Implementa la API REST      |
  |  de Iceberg para interoperabilidad multi-engine   |
  +-----------------------+--------------------------+
                          |
  +--------------------------------------------------+
  |   Floci (AWS S3 emulado)  |  Apache Iceberg       |
  |   Almacenamiento de       |  Formato de tabla     |
  |   archivos Parquet y      |  ACID, time travel,   |
  |   metadatos Iceberg       |  evolucion esquemas   |
  +---------------------------+----------------------+
```

## Componentes y por que cada uno

### Floci (`floci/floci:latest`)

- **Rol:** Almacenamiento de objetos compatible con S3
- **Que hace:** Actua como un bucket S3 local donde Iceberg guarda los archivos de datos
  (Parquet) y los archivos de metadatos (manifestos, snapshots). Floci es un emulador de
  AWS gratuito, rapido y sin necesidad de cuenta.
- **Alternativa:** MinIO (mas usado en produccion, interfaz web incluida)
- **Puerto:** 4566
- **Credenciales:** `test` / `test`

### Apache Iceberg

- **Rol:** Formato de tabla abierto para lagos de datos
- **Que hace:** Agrega capacidades de base de datos relacional a archivos Parquet:
  transacciones ACID, evolucion de esquema, time travel (viajes en el tiempo), particionado
  oculto, compactacion de archivos.
- **Como se usa:** Iceberg no es un servicio independiente. Es una libreria que los motores
  de consulta (Trino, DuckDB, Spark) incorporan para leer/escribir tablas en formato Iceberg.
- **Catalogo:** Iceberg necesita un catalogo para mantener los metadatos de las tablas.
  En esta pila usamos Apache Polaris.

### Apache Polaris (`apache/polaris:latest`)

- **Rol:** Catalogo Iceberg REST
- **Que hace:** Implementa la especificacion de API REST de Iceberg, permitiendo que
  multiples motores (Trino, DuckDB, Spark, Flink) compartan las mismas tablas Iceberg sin
  conflictos. Polaris gestiona:
  - Registro de tablas y esquemas
  - Control de acceso basado en roles
  - Vending de credenciales para acceso a S3
  - Multi-arrendamiento (realms)
- **Puertos:** 8181 (API REST), 8182 (health check y metricas)
- **Credenciales root:** `root` / `s3cr3t` (uso interno para Trino)
- **Credenciales usuario:** Auto-generadas al iniciar (para DuckDB)

### DuckDB

- **Rol:** Base de datos analitica embebida
- **Que hace:** Motor SQL que se ejecuta en el mismo proceso, sin necesidad de servidor.
  Ideal para analitica exploratoria, transformacion de datos y pruebas locales. Con la
  extension `iceberg` puede leer y escribir tablas Iceberg directamente desde archivos
  S3 o a traves del catalogo REST de Polaris.
- **Donde corre:** Se instala en tu maquina host (no corre como contenedor)
- **Extensiones necesarias:** `iceberg`, `httpfs`

### Trino (`trinodb/trino:latest`)

- **Rol:** Motor de consultas SQL distribuido
- **Que hace:** Permite consultar datos desde multiples fuentes (Iceberg, MySQL, Kafka,
  etc.) con SQL estandar. En esta pila actua como el "servidor SQL" del lakehouse,
  accesible desde cualquier cliente JDBC/HTTP.
- **Puerto:** 8080
- **Interfaz Web:** http://localhost:8080 (UI de Trino)

## Como se comunican

1. **Floci** almacena los archivos de datos Parquet y los metadatos de Iceberg
2. **Polaris** guarda el puntero a la version actual de cada tabla y su esquema
3. **Trino** se conecta a Polaris via REST para saber donde estan los datos, luego lee
   los archivos directamente de Floci via S3 API
4. **DuckDB** tambien se conecta a Polaris via REST y lee/escribe datos en Floci via S3
5. Como ambos motores apuntan al mismo catalogo (Polaris) y al mismo almacenamiento
   (Floci), los cambios hechos desde DuckDB son visibles inmediatamente en Trino y
   viceversa

## Requisitos

- Docker y Docker Compose (incluido en Docker Desktop)
- DuckDB >= 1.4.0 instalado localmente
  ```bash
  curl https://install.duckdb.org | sh
  ```
- Puerto 4566, 8080, 8181 libres en tu maquina

## Inicio rapido

```bash
# 1. Clonar o copiar este proyecto
cd local-lakehouse

# 2. Iniciar todos los servicios
docker compose up -d

# 3. Ver los logs de configuracion (esperar a que termine)
docker compose logs -f polaris-setup
# Espera hasta ver "Configuracion de Polaris completada exitosamente!"
# Copia las credenciales de USUARIO que aparecen

# 4. Verificar que todo esta funcionando
docker compose ps

# 5. Conectarse a Trino
docker compose exec trino trino --catalog iceberg
trino:> SHOW SCHEMAS;
trino:> CREATE SCHEMA demo;
trino:> CREATE TABLE demo.ventas AS SELECT 1 AS id, 'test' AS nombre;
trino:> SELECT * FROM demo.ventas;

# 6. Usar DuckDB (desde tu maquina, no dentro del contenedor)
duckdb -c ".read scripts/query-duckdb.sql"
# O entra a la consola interactiva:
duckdb
```

## URLs de acceso

| Servicio     | URL                                     |
| ------------ | --------------------------------------- |
| Trino UI     | http://localhost:8080                   |
| Trino JDBC   | `jdbc:trino://localhost:8080`           |
| Polaris REST | http://localhost:8181/api/catalog/v1    |
| Polaris Mgmt | http://localhost:8181/api/management/v1 |
| Floci S3     | http://localhost:4566                   |

## Credenciales

Estas credenciales se generan automaticamente al iniciar el proyecto. Puedes verlas en:

```bash
docker compose logs polaris-setup | grep -A2 "Credenciales"
```

**Root (usadas internamente por Trino):**

```
Client ID:     root
Client Secret: s3cr3t
```

**Usuario (para tus consultas desde DuckDB):**
Se generan aleatoriamente en cada `docker compose up`. Busca en los logs:

```
Client ID:     <lakehouse_user>
Client Secret: <auto-generado>
```

## Deteniendo el proyecto

```bash
# Detener sin borrar datos
docker compose stop

# Detener y borrar los contenedores (los datos persisten en volumes)
docker compose down

# Detener y borrar TODO (incluye datos de Floci y config de Polaris)
docker compose down -v
```

## Uso detallado

### Trino (servidor SQL)

```bash
# CLI interactiva dentro del contenedor
docker compose exec trino trino

# CLI con catalogo especifico
docker compose exec trino trino --catalog iceberg

# Ejecutar una consulta directa
docker compose exec trino trino --execute "SHOW SCHEMAS FROM iceberg;"
```

Comandos basicos en Trino:

```sql
-- Listar catalogos disponibles
SHOW CATALOGS;

-- Usar el catalogo Iceberg
USE iceberg;

-- Listar schemas (namespaces)
SHOW SCHEMAS FROM iceberg;

-- Crear un schema
CREATE SCHEMA IF NOT EXISTS iceberg.demo;

-- Crear tabla desde una consulta
CREATE TABLE iceberg.demo.numeros AS
SELECT n, n * 2 AS doble
FROM UNNEST(SEQUENCE(1, 10)) AS t(n);

-- Consultar
SELECT * FROM iceberg.demo.numeros;

-- Ver estructura de tabla
SHOW CREATE TABLE iceberg.demo.numeros;

-- Ver snapshots (time travel)
SELECT * FROM iceberg.demo."numeros$snapshots";

-- Limpiar
DROP TABLE IF EXISTS iceberg.demo.numeros;
```

### DuckDB (analitica local)

DuckDB corre en tu maquina host. Instalalo primero:

```bash
curl https://install.duckdb.org | sh
```

Luego configura las credenciales (reemplaza con las que aparecen en los logs):

```bash
# Entrar a DuckDB
duckdb
```

Dentro de DuckDB:

```sql
-- Instalar extensiones
INSTALL iceberg;
INSTALL httpfs;
LOAD iceberg;
LOAD httpfs;

-- Configurar secreto para Polaris
CREATE SECRET polaris_secret (
    TYPE iceberg,
    CLIENT_ID 'lakehouse_user',
    CLIENT_SECRET '<COLOCA_TU_CLIENT_SECRET>',
    ENDPOINT 'http://localhost:8181/api/catalog'
);

-- Adjuntar catalogo
ATTACH 'lakehouse_catalog' AS ls_cat (
    TYPE iceberg,
    ENDPOINT 'http://localhost:8181/api/catalog'
);

-- CREAR datos desde DuckDB
CREATE SCHEMA ls_cat.demo;
CREATE TABLE ls_cat.demo.ventas AS
    SELECT * FROM (VALUES
        (1, 'Laptop', 1500.00),
        (2, 'Mouse', 25.50),
        (3, 'Teclado', 89.99)
    ) AS t(id, producto, precio);

-- Leer los datos
SELECT * FROM ls_cat.demo.ventas;

-- Estos datos son visibles inmediatamente desde Trino:
-- docker compose exec trino trino --execute "SELECT * FROM iceberg.demo.ventas;"
```

### Verificar que los datos sobreviven a reinicios

Los datos de Floci persisten en el volumen `floci-data`. Puedes probar:

```bash
# Crear datos
docker compose exec trino trino --execute "CREATE TABLE iceberg.demo.persistente AS SELECT 1 AS x;"

# Reiniciar todo
docker compose down
docker compose up -d

# Verificar que los datos siguen ahi
docker compose exec trino trino --execute "SELECT * FROM iceberg.demo.persistente;"
```

## Arquitectura detallada

### Flujo de una consulta en Trino

```
Cliente (JDBC/HTTP)
    │
    ▼
Trino Coordinator (:8080)
    │
    ├── Pide metadatos de tabla a Polaris (:8181)
    │   └── Polaris devuelve: esquema, particiones, lista de archivos, credenciales S3
    │
    ├── Trino Worker lee archivos Parquet de Floci S3 (:4566)
    │   └── Aplica filtros, proyecciones, agregaciones
    │
    └── Resultado al cliente
```

### Flujo de una escritura desde DuckDB

```
DuckDB (host)
    │
    ├── Crea secreto y adjunta catalogo via Polaris REST API
    │
    ├── Escribe archivos Parquet en Floci S3 (s3://lakehouse/...)
    │
    └── Commitea el nuevo snapshot en Polaris
        └── Trino ve inmediatamente los nuevos datos
```

## Solucion de problemas

### El contenedor Floci no arranca

```bash
docker compose logs floci
# Verificar que el puerto 4566 no esta ocupado
sudo lsof -i :4566
```

### Polaris no responde

```bash
# Verificar salud
curl http://localhost:8182/q/health

# Ver logs
docker compose logs polaris
```

### Trino no encuentra tablas

```bash
# Verificar que polaris-setup termino
docker compose logs polaris-setup | tail -5

# Ver configuracion del catalogo
docker compose exec trino cat /etc/trino/catalog/iceberg.properties
```

### DuckDB no se conecta a Polaris

```bash
# Verificar que Polaris esta accesible desde el host
curl -s http://localhost:8181/api/catalog/v1/oauth/tokens \
  -d 'grant_type=client_credentials' \
  -d 'client_id=root' \
  -d 'client_secret=s3cr3t' \
  -d 'scope=PRINCIPAL_ROLE:ALL' | jq
```

### No encuentro las credenciales de usuario

```bash
docker compose logs polaris-setup | grep -E "(Client ID|Client Secret)"
```

## Estructura del proyecto

```
local-lakehouse/
├── compose.yaml                 # Servicios Docker
├── README.md                    # Este archivo
├── trino/
│   └── catalog/
│       └── iceberg.properties   # Config catalogo Iceberg para Trino
├── scripts/
│   ├── bootstrap-polaris.sh     # Script de bootstrap de Polaris
│   └── query-duckdb.sql         # Ejemplos de consultas DuckDB
└── volumes/                     # Datos persistentes (creado por Docker)
```

## Notas

- **Floci** almacena datos en un volumen Docker (`floci-data`). Los datos persisten entre
  reinicios a menos que uses `docker compose down -v`.
- **Polaris** en esta configuracion usa almacenamiento en memoria. Al reiniciar el
  contenedor, se pierde la configuracion del catalogo (pero NO los datos en Floci).
  El script `polaris-setup` re-crea el catalogo automaticamente.
- **Trino** no tiene almacenamiento propio; toda la configuracion se define en
  `trino/catalog/iceberg.properties`.
- **DuckDB** no corre como servicio, se ejecuta bajo demanda desde tu terminal.
- Los puertos expuestos (4566, 8080, 8181) son accesibles desde tu maquina host.
- Para un entorno productivo, considera usar MinIO en lugar de Floci para S3,
  y agregar PostgreSQL como backend persistente para Polaris.

---

_Este proyecto fue generado con asistencia de inteligencia artificial (IA).
Verifica y valida la configuracion antes de usarlo en produccion._
