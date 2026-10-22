
BEGIN;

-- =====================================================
-- 1. REINICIAR RESULTADOS DE SILVER
-- =====================================================

TRUNCATE TABLE silver.dq_log RESTART IDENTITY;
TRUNCATE TABLE silver.trips_clean;


-- =====================================================
-- 2. REGISTRAR RC-01 Y RC-02 POR ARCHIVO
-- =====================================================

WITH base AS (
    SELECT
        source_file,
        substring(
            source_file FROM '([0-9]{4}-[0-9]{2})'
        ) AS periodo,
        tpep_pickup_datetime,
        tpep_dropoff_datetime,
        EXTRACT(
            EPOCH FROM (
                tpep_dropoff_datetime - tpep_pickup_datetime
            )
        ) / 60.0 AS duracion_min
    FROM public.yellow_tripdata
),
resumen AS (
    SELECT
        source_file,
        periodo,
        COUNT(*) AS total_origen,
        COUNT(*) FILTER (
            WHERE tpep_pickup_datetime IS NULL
               OR periodo IS NULL
               OR to_char(tpep_pickup_datetime, 'YYYY-MM') <> periodo
        ) AS rc01,
        COUNT(*) FILTER (
            WHERE duracion_min < 0
        ) AS rc02
    FROM base
    GROUP BY source_file, periodo
),
log_datos AS (
    SELECT
        periodo,
        total_origen,
        'RC-01'::text AS regla,
        rc01 AS afectados
    FROM resumen

    UNION ALL

    SELECT
        periodo,
        total_origen,
        'RC-02_DURACION_NEGATIVA',
        rc02
    FROM resumen
)
INSERT INTO silver.dq_log (
    regla,
    anio_origen,
    mes_origen,
    total_origen,
    registros_afectados,
    porcentaje_afectado,
    tipo_resultado
)
SELECT
    regla,
    split_part(periodo, '-', 1)::integer,
    split_part(periodo, '-', 2)::integer,
    total_origen,
    afectados,
    100.0 * afectados / NULLIF(total_origen, 0),
    'DESCARTADO'
FROM log_datos;


-- =====================================================
-- 3. CARGAR VIAJES ELEGIBLES EN SILVER
-- =====================================================

INSERT INTO silver.trips_clean (
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
    loaded_at,
    fecha_recogida,
    hora_recogida,
    duracion_min,
    velocidad_mph,
    flag_distancia_no_positiva,
    flag_tarifa_no_positiva,
    flag_duracion_negativa,
    flag_distancia_extrema
)
SELECT
    b.vendorid,
    b.tpep_pickup_datetime,
    b.tpep_dropoff_datetime,
    b.passenger_count,
    b.trip_distance,
    b.ratecodeid,
    b.store_and_fwd_flag,
    b.pulocationid,
    b.dolocationid,
    b.payment_type,
    b.fare_amount,
    b.extra,
    b.mta_tax,
    b.tip_amount,
    b.tolls_amount,
    b.improvement_surcharge,
    b.total_amount,
    b.congestion_surcharge,
    b.airport_fee,
    b.cbd_congestion_fee,
    b.request_source,
    b.source_file,
    b.loaded_at,
    b.tpep_pickup_datetime::date,
    EXTRACT(HOUR FROM b.tpep_pickup_datetime)::smallint,
    EXTRACT(
        EPOCH FROM (
            b.tpep_dropoff_datetime - b.tpep_pickup_datetime
        )
    ) / 60.0,
    CASE
        WHEN b.tpep_dropoff_datetime > b.tpep_pickup_datetime
         AND b.trip_distance >= 0
        THEN b.trip_distance /
             (
                 EXTRACT(
                     EPOCH FROM (
                         b.tpep_dropoff_datetime
                         - b.tpep_pickup_datetime
                     )
                 ) / 3600.0
             )
        ELSE NULL
    END,
    b.trip_distance <= 0,
    b.fare_amount <= 0,
    b.tpep_dropoff_datetime < b.tpep_pickup_datetime,
    b.trip_distance > 100
FROM public.yellow_tripdata b
WHERE
    -- RC-01: fecha de recogida válida y coincidente
    -- con el año y mes del archivo de origen.
    b.tpep_pickup_datetime IS NOT NULL
    AND substring(
        b.source_file FROM '([0-9]{4}-[0-9]{2})'
    ) IS NOT NULL
    AND to_char(b.tpep_pickup_datetime, 'YYYY-MM')
        = substring(
            b.source_file FROM '([0-9]{4}-[0-9]{2})'
        )

    -- RC-02: excluir duraciones negativas.
    AND b.tpep_dropoff_datetime IS NOT NULL
    AND b.tpep_dropoff_datetime >= b.tpep_pickup_datetime;


-- =====================================================
-- 4. VALIDACION ANTES DE CONFIRMAR
-- =====================================================


DO $$
DECLARE
    total_silver bigint;
    total_esperado bigint;
BEGIN
    SELECT COUNT(*)
    INTO total_esperado
    FROM public.yellow_tripdata b
    WHERE b.tpep_pickup_datetime IS NOT NULL
      AND substring(
          b.source_file FROM '([0-9]{4}-[0-9]{2})'
      ) IS NOT NULL
      AND to_char(b.tpep_pickup_datetime, 'YYYY-MM')
          = substring(
              b.source_file FROM '([0-9]{4}-[0-9]{2})'
          )
      AND b.tpep_dropoff_datetime IS NOT NULL
      AND b.tpep_dropoff_datetime >= b.tpep_pickup_datetime;

    SELECT COUNT(*)
    INTO total_silver
    FROM silver.trips_clean;

    IF total_silver <> total_esperado THEN
        RAISE EXCEPTION
            'Conteo incorrecto en Silver: %; esperado según Bronze: %',
            total_silver, total_esperado;
    END IF;
END $$;


COMMIT;
