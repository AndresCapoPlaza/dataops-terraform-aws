"""
Empaqueta la aplicacion de PyFlink para Amazon Managed Service for Apache Flink.

POR QUE NO SE USA Compress-Archive DE POWERSHELL
------------------------------------------------
Compress-Archive escribe las rutas internas del zip con el separador de
Windows (backslash). El estandar ZIP exige barra normal, y Managed Flink
busca el JAR por la ruta declarada en la propiedad `jarfile`
("lib/flink-sql-connector-kinesis-1.15.4.jar"). Con backslash, el servicio
responde:

    InvalidArgumentException: We couldn't find the configured file
    'lib/flink-sql-connector-kinesis-1.15.4.jar' in your zip file

Este script usa zipfile de la libreria estandar, que siempre normaliza a "/".

USO
---
    python scripts/build_flink_zip.py
"""

import pathlib
import sys
import zipfile

RAIZ = pathlib.Path(__file__).resolve().parent.parent
APP_DIR = RAIZ / "flink-app"
SALIDA = APP_DIR / "clicks_processor.zip"

# (ruta en disco, ruta dentro del zip)  -- siempre con "/" en el destino
CONTENIDO = [
    (APP_DIR / "clicks_processor.py", "clicks_processor.py"),
    (APP_DIR / "lib" / "flink-sql-connector-kinesis-1.15.4.jar",
     "lib/flink-sql-connector-kinesis-1.15.4.jar"),
]


def main() -> int:
    faltantes = [str(origen) for origen, _ in CONTENIDO if not origen.is_file()]
    if faltantes:
        print("ERROR: faltan archivos para empaquetar:")
        for f in faltantes:
            print("  -", f)
        print("\nDescargar el conector con:")
        print("  Invoke-WebRequest -Uri https://repo1.maven.org/maven2/org/apache/flink/"
              "flink-sql-connector-kinesis/1.15.4/flink-sql-connector-kinesis-1.15.4.jar "
              "-OutFile flink-app\\lib\\flink-sql-connector-kinesis-1.15.4.jar")
        return 1

    if SALIDA.exists():
        SALIDA.unlink()

    with zipfile.ZipFile(SALIDA, "w", zipfile.ZIP_DEFLATED) as z:
        for origen, destino in CONTENIDO:
            print(f"  + {destino}  ({origen.stat().st_size / 1_048_576:.1f} MB)")
            z.write(origen, destino)

    print(f"\nGenerado: {SALIDA}  ({SALIDA.stat().st_size / 1_048_576:.1f} MB)")

    # Verificacion: las rutas internas deben usar "/"
    with zipfile.ZipFile(SALIDA) as z:
        nombres = z.namelist()
    print("\nContenido del zip:")
    for n in nombres:
        print("   ", n)
    if any("\\" in n for n in nombres):
        print("\nERROR: hay rutas con backslash. Managed Flink no las va a encontrar.")
        return 1
    print("\nRutas normalizadas correctamente.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
