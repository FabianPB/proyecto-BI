{{ config(materialized='view') }}

with base as (
    select *
    from {{ ref('stg_yellow_tripdata') }}
),

preparacion as (
    select
        b.*,
        substring(
            b.source_file from '([0-9]{4}-[0-9]{2})'
        ) as periodo_archivo,
        extract(
            epoch from (
                b.tpep_dropoff_datetime - b.tpep_pickup_datetime
            )
        ) / 60.0 as duracion_min
    from base b
),

elegibles as (
    select *
    from preparacion
    where
        tpep_pickup_datetime is not null
        and periodo_archivo is not null
        and to_char(tpep_pickup_datetime, 'YYYY-MM') = periodo_archivo
        and tpep_dropoff_datetime is not null
        and tpep_dropoff_datetime >= tpep_pickup_datetime
)

select
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
    tpep_pickup_datetime::date as fecha_recogida,
    extract(hour from tpep_pickup_datetime)::smallint as hora_recogida,
    duracion_min,
    case
        when tpep_dropoff_datetime > tpep_pickup_datetime
         and trip_distance >= 0
        then trip_distance / (duracion_min / 60.0)
        else null
    end as velocidad_mph,
    trip_distance <= 0 as flag_distancia_no_positiva,
    fare_amount <= 0 as flag_tarifa_no_positiva,
    tpep_dropoff_datetime < tpep_pickup_datetime as flag_duracion_negativa,
    trip_distance > 100 as flag_distancia_extrema
from elegibles