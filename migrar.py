
from pathlib import Path
from datetime import datetime, timezone
import time
import math

import pyarrow.parquet as pq
import psycopg
from psycopg import sql


# ============================================================
# CONFIGURACION
# ============================================================

CARPETA_DATOS = Path("data")
LOTE = 50_000

DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 5432,
    "dbname": "nyc_taxi",
    "user": "postgres",
    "password": "Postgres2026!",
}

TABLA = "yellow_tripdata"
STAGING = "yellow_tripdata_stage"

COLUMNAS = [
    "vendorid",
    "tpep_pickup_datetime",
    "tpep_dropoff_datetime",
    "passenger_count",
    "trip_distance",
    "ratecodeid",
    "store_and_fwd_flag",
    "pulocationid",
    "dolocationid",
    "payment_type",
    "fare_amount",
    "extra",
    "mta_tax",
    "tip_amount",
    "tolls_amount",
    "improvement_surcharge",
    "total_amount",
    "congestion_surcharge",
    "airport_fee",
    "cbd_congestion_fee",
    "request_source",
]

COLUMNAS_TECNICAS = ["source_file", "loaded_at"]
TODAS_COLUMNAS = COLUMNAS + COLUMNAS_TECNICAS


# ============================================================
# VALIDAR ARCHIVOS
# ============================================================

def obtener_archivos():
    esperados = {
        f"yellow_tripdata_{anio}-{mes:02d}.parquet"
        for anio, ultimo_mes in [(2024, 12), (2025, 12), (2026, 8)]
        for mes in range(1, ultimo_mes + 1)
    }

    archivos = sorted(
        CARPETA_DATOS.glob("yellow_tripdata_*.parquet")
    )

    encontrados = {archivo.name for archivo in archivos}

    faltantes = sorted(esperados - encontrados)
    adicionales = sorted(encontrados - esperados)

    if faltantes or adicionales:
        raise RuntimeError(
            "Los archivos no coinciden con el conjunto esperado.\n"
            f"Faltantes: {faltantes}\n"
            f"Adicionales: {adicionales}"
        )

    return archivos


# ============================================================
# NORMALIZAR COLUMNAS Y VALORES
# ============================================================

def normalizar_lote(tabla):
    tabla = tabla.rename_columns(
        [nombre.lower() for nombre in tabla.schema.names]
    )

    nombres = set(tabla.schema.names)
    presentes = [columna for columna in COLUMNAS if columna in nombres]
    datos = tabla.select(presentes).to_pydict()

    for i in range(tabla.num_rows):
        fila = []

        for columna in COLUMNAS:
            if columna not in datos:
                fila.append(None)
                continue

            valor = datos[columna][i]

            if valor is None:
                fila.append(None)
            elif isinstance(valor, float) and math.isnan(valor):
                fila.append(None)
            else:
                fila.append(valor)

        yield tuple(fila)


# ============================================================
# CREAR TABLA DE PREPARACION
# ============================================================


def preparar_staging(conn):
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("DROP TABLE IF EXISTS public.{}").format(
                    sql.Identifier(STAGING)
                )
            )

            cur.execute(
                sql.SQL(
                    "CREATE TABLE public.{} "
                    "(LIKE public.{} INCLUDING DEFAULTS)"
                ).format(
                    sql.Identifier(STAGING),
                    sql.Identifier(TABLA),
                )
            )
# ============================================================
# CARGAR UN ARCHIVO
# ============================================================

def migrar_archivo(conn, archivo):
    parquet = pq.ParquetFile(archivo)
    total_archivo = parquet.metadata.num_rows
    cargados = 0
    fecha_carga = datetime.now(timezone.utc)

    print(f"\nArchivo: {archivo.name}")
    print(f"Registros de origen: {total_archivo:,}")

    consulta = sql.SQL(
        "COPY public.{} ({}) FROM STDIN"
    ).format(
        sql.Identifier(STAGING),
        sql.SQL(", ").join(
            sql.Identifier(columna)
            for columna in TODAS_COLUMNAS
        ),
    )

    # Si falla un archivo, su transaccion se revierte.
    with conn.transaction():
        with conn.cursor() as cur:
            with cur.copy(consulta) as copia:
                for lote in parquet.iter_batches(batch_size=LOTE):
                    for fila in normalizar_lote(lote):
                        copia.write_row(
                            fila + (archivo.name, fecha_carga)
                        )
                        cargados += 1

                    print(
                        f"\rProcesados: {cargados:,} / "
                        f"{total_archivo:,}",
                        end="",
                        flush=True,
                    )

            if cargados != total_archivo:
                raise RuntimeError(
                    f"Conteo incorrecto en {archivo.name}: "
                    f"{cargados:,} frente a {total_archivo:,}"
                )

    print(f"\nCarga confirmada: {cargados:,}")
    return cargados


# ============================================================
# VALIDAR Y REEMPLAZAR TABLA ACTUAL
# ============================================================

def reemplazar_tabla(conn, total_esperado):
    # Todo el reemplazo se realiza en una sola transaccion.
    # Si la validacion falla, PostgreSQL revierte el TRUNCATE
    # y el INSERT, preservando los datos anteriores.
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("SELECT COUNT(*) FROM public.{}").format(
                    sql.Identifier(STAGING)
                )
            )
            total_staging = cur.fetchone()[0]

            if total_staging != total_esperado:
                raise RuntimeError(
                    f"Staging tiene {total_staging:,} filas; "
                    f"se esperaban {total_esperado:,}. "
                    "No se reemplazara la tabla original."
                )

            # Agregar columnas tecnicas sin eliminar las existentes.
            cur.execute(
                """
                ALTER TABLE public.yellow_tripdata
                ADD COLUMN IF NOT EXISTS source_file text,
                ADD COLUMN IF NOT EXISTS loaded_at timestamptz
                """
            )

            # Conserva el nombre y la identidad de la tabla actual.
            cur.execute(
                "TRUNCATE TABLE public.yellow_tripdata"
            )

            # Las columnas de INSERT y SELECT tienen el mismo orden.
            cur.execute(
                """
                INSERT INTO public.yellow_tripdata (
                    vendorid,
                    tpep_pickup_datetime,
                    tpep_dropoff_datetime,
                    passenger_count,
                    trip_distance,
                    ratecodeid,
                    store_and_fwd_flag,
                    pulocationid,
                    dolocationid,
                    payment_type,
                    fare_amount,
                    extra,
                    mta_tax,
                    tip_amount,
                    tolls_amount,
                    improvement_surcharge,
                    total_amount,
                    congestion_surcharge,
                    airport_fee,
                    cbd_congestion_fee,
                    request_source,
                    source_file,
                    loaded_at
                )
                SELECT
                    vendorid,
                    tpep_pickup_datetime,
                    tpep_dropoff_datetime,
                    passenger_count,
                    trip_distance,
                    ratecodeid,
                    store_and_fwd_flag,
                    pulocationid,
                    dolocationid,
                    payment_type,
                    fare_amount,
                    extra,
                    mta_tax,
                    tip_amount,
                    tolls_amount,
                    improvement_surcharge,
                    total_amount,
                    congestion_surcharge,
                    airport_fee,
                    cbd_congestion_fee,
                    request_source,
                    source_file,
                    loaded_at
                FROM public.yellow_tripdata_stage
                """
            )

            # Validar antes de confirmar la transaccion.
            cur.execute(
                "SELECT COUNT(*) FROM public.yellow_tripdata"
            )
            total_final = cur.fetchone()[0]

            if total_final != total_esperado:
                raise RuntimeError(
                    f"La tabla final tiene {total_final:,} filas; "
                    f"se esperaban {total_esperado:,}. "
                    "Se revertira el reemplazo."
                )

            # Solo se elimina staging cuando la validacion coincide.
            cur.execute(
                sql.SQL("DROP TABLE public.{}").format(
                    sql.Identifier(STAGING)
                )
            )

    return total_final


# ============================================================
# PROCESO PRINCIPAL
# ============================================================

def main():
    archivos = obtener_archivos()

    # Consultar metadatos: no carga todos los registros en memoria.
    conteos_origen = {
        archivo.name: pq.ParquetFile(archivo).metadata.num_rows
        for archivo in archivos
    }
    total_esperado = sum(conteos_origen.values())

    print("=" * 65)
    print("INGESTA COMPLETA YELLOW TAXI")
    print("=" * 65)
    print(f"Archivos encontrados: {len(archivos)}")
    print(f"Registros esperados: {total_esperado:,}")
    print("Periodo: enero de 2024 a agosto de 2026")
    print("La tabla actual se conservara durante la carga.")
    print("=" * 65)

    inicio = time.time()
    total_cargado = 0

    with psycopg.connect(**DB_CONFIG) as conn:
        # Crear staging. Si ya existia por una ejecucion anterior,
        # se recrea; la tabla original no se modifica.
        preparar_staging(conn)

        for archivo in archivos:
            cantidad = migrar_archivo(conn, archivo)

            if cantidad != conteos_origen[archivo.name]:
                raise RuntimeError(
                    f"El conteo de {archivo.name} no coincide."
                )

            total_cargado += cantidad

        if total_cargado != total_esperado:
            raise RuntimeError(
                f"Total cargado {total_cargado:,}; "
                f"esperado {total_esperado:,}. "
                "La tabla original no se reemplazara."
            )

        print("\nValidando carga completa...")
        total_final = reemplazar_tabla(conn, total_esperado)

        # Comprobacion adicional despues del reemplazo.
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM public.yellow_tripdata"
            )
            total_final = cur.fetchone()[0]

            cur.execute(
                """
                SELECT source_file, COUNT(*)
                FROM public.yellow_tripdata
                GROUP BY source_file
                ORDER BY source_file
                """
            )
            conteos_finales = dict(cur.fetchall())

        if total_final != total_esperado:
            raise RuntimeError(
                f"Conteo final incorrecto: {total_final:,}"
            )

        for nombre, esperado in conteos_origen.items():
            obtenido = conteos_finales.get(nombre, 0)

            if obtenido != esperado:
                raise RuntimeError(
                    f"Conteo incorrecto para {nombre}: "
                    f"{obtenido:,} frente a {esperado:,}"
                )

    print("\n" + "=" * 65)
    print("INGESTA COMPLETADA Y VALIDADA")
    print(f"Archivos procesados: {len(archivos)}")
    print(f"Registros esperados: {total_esperado:,}")
    print(f"Registros cargados:  {total_cargado:,}")
    print(f"Registros finales:   {total_final:,}")
    print(f"Tiempo total: {(time.time() - inicio) / 60:.2f} minutos")
    print("=" * 65)

    print("\nConteo por archivo:")
    for nombre in sorted(conteos_origen):
        print(f"{nombre}: {conteos_finales[nombre]:,}")


if __name__ == "__main__":
    main()
