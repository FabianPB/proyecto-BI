{{ config(materialized='view') }}

with base as (
    select
        source_file,
        substring(source_file from '([0-9]{4}-[0-9]{2})') as periodo,
        tpep_pickup_datetime,
        tpep_dropoff_datetime,
        extract(
            epoch from (tpep_dropoff_datetime - tpep_pickup_datetime)
        ) / 60.0 as duracion_min
    from {{ source('bronze', 'yellow_tripdata') }}
),

resumen as (
    select
        source_file,
        periodo,
        count(*) as total_origen,
        count(*) filter (
            where tpep_pickup_datetime is null
               or periodo is null
               or to_char(tpep_pickup_datetime, 'YYYY-MM') <> periodo
        ) as rc01,
        count(*) filter (
            where duracion_min < 0
        ) as rc02
    from base
    group by source_file, periodo
)

select
    source_file,
    periodo,
    total_origen,
    rc01 as rc01_afectados,
    rc02 as rc02_duracion_negativa
from resumen