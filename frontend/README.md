# Lakehouse Local — Frontend Web

Interfaz web minimalista para el lakehouse local. Permite subir/descargar archivos de Floci
S3 y ejecutar consultas SQL vía Trino desde el navegador.

## Stack

- **Python 3 + Flask** — backend HTTP
- **Boto3** — cliente S3 para Floci
- **Trino Python client** — consultas SQL al catálogo Iceberg
- **HTML + vanilla JS** — sin build step, sin frameworks

## Requisitos

- Python 3.12+
- Servicios del lakehouse corriendo (`docker compose up -d` desde la raíz del proyecto)
- Puertos 4566 (Floci), 8080 (Trino), 8181 (Polaris) accesibles desde el host

## Instalación

```bash
# Crear entorno virtual e instalar dependencias
python3 -m venv .venv
source .venv/bin/activate

cd frontend
.venv/bin/pip install -r requirements.txt
```

## Uso

```bash
.venv/bin/python app.py
```

La app arranca en `http://localhost:5001` con autorecarga en modo desarrollo.

## URLs

| Página    | URL                            | Descripción                   |
| --------- | ------------------------------ | ----------------------------- |
| Inicio    | `http://localhost:5001/`       | Bienvenida y enlaces          |
| Subir     | `http://localhost:5001/upload` | Subir archivos a Floci S3     |
| Archivos  | `http://localhost:5001/files`  | Explorar archivos en Floci S3 |
| Consultas | `http://localhost:5001/query`  | Editor SQL vía Trino          |

## API REST

| Método | Ruta                  | Descripción                                    |
| ------ | --------------------- | ---------------------------------------------- |
| GET    | `/api/files`          | Lista archivos en el bucket `lakehouse`        |
| POST   | `/api/upload`         | Sube un archivo (multipart/form-data)          |
| GET    | `/api/files/<key>`    | Descarga un archivo (redirect a presigned URL) |
| POST   | `/api/query`          | Ejecuta SQL (`{"sql": "..."}`)                 |
| GET    | `/api/schemas`        | Lista schemas del catálogo Iceberg             |
| GET    | `/api/tables?schema=` | Lista tablas de un schema                      |

## Estructura

```
frontend/
├── README.md              # Este archivo
├── requirements.txt       # Dependencias Python
├── app.py                 # Servidor Flask + API
└── templates/
    ├── base.html          # Layout común (nav + CSS)
    ├── index.html         # Página de inicio
    ├── upload.html        # Subida de archivos
    ├── files.html         # Explorador de archivos
    └── query.html         # Editor SQL
```

## Notas

- La app usa las credenciales fijas `test`/`test` para Floci (sin STS).
- Las consultas SQL se ejecutan contra el catálogo `iceberg` de Trino con `user=admin`.
- El bucket S3 (`lakehouse`) debe existir; lo crea `bucket-setup` al iniciar el compose.
- Para producción no uses el servidor de desarrollo de Flask.

---

_Este proyecto fue generado con asistencia de inteligencia artificial (IA).
Verifica y valida la configuración antes de usarlo en producción._
