-- ============================================
--  Ejemplos de consultas con DuckDB + Iceberg
--  Reemplaza CLIENT_ID y CLIENT_SECRET con
--  los valores que aparecen en los logs de
--  docker compose del servicio polaris-setup
--
--  Para simplificar, usa en su lugar:
--    bash scripts/run-duckdb.sh
-- ============================================

-- Instalar y cargar extensiones
INSTALL iceberg;
INSTALL httpfs;
LOAD iceberg;
LOAD httpfs;

-- Secreto S3 para acceso directo a Floci
CREATE SECRET floci_s3 (
    TYPE S3,
    KEY_ID 'test',
    SECRET 'test',
    REGION 'us-east-1',
    ENDPOINT 'localhost:4566',
    URL_STYLE 'path',
    USE_SSL false
);

-- Secreto de autenticacion para Polaris
CREATE SECRET polaris_secret (
    TYPE iceberg,
    CLIENT_ID '04ae30cecc5ba435',
    CLIENT_SECRET 'af3038ce628f7094d9ebacda9098c2be',
    ENDPOINT 'http://localhost:8181/api/catalog'
);

-- Adjuntar el catalogo de Polaris
-- IMPORTANTE: ACCESS_DELEGATION_MODE 'none' evita que DuckDB
-- solicite credenciales vending a Polaris (no disponible con Floci)
ATTACH 'lakehouse_catalog' AS ls_cat (
    TYPE iceberg,
    SECRET polaris_secret,
    ENDPOINT 'http://localhost:8181/api/catalog',
    ACCESS_DELEGATION_MODE 'none'
);

-- Ver datos escritos por Trino
SELECT * FROM ls_cat.demo.ventas;

-- Crear un schema (namespace)
CREATE SCHEMA IF NOT EXISTS ls_cat.demo;
CREATE SCHEMA IF NOT EXISTS ls_cat.analytics;

-- Crear tu propia tabla
CREATE TABLE IF NOT EXISTS ls_cat.analytics.ventas (
    id          INTEGER,
    producto    VARCHAR,
    cantidad    INTEGER,
    precio      DECIMAL(10,2),
    fecha       DATE
);

INSERT INTO ls_cat.analytics.ventas VALUES
    (1, 'Laptop',    2, 1500.00, DATE '2025-01-15'),
    (2, 'Mouse',    10,   25.50, DATE '2025-01-16'),
    (3, 'Teclado',   5,   89.99, DATE '2025-01-17'),
    (4, 'Monitor',   3,  350.00, DATE '2025-01-18');

SELECT * FROM ls_cat.analytics.ventas;
