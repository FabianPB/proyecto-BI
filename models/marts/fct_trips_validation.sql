{{ config(materialized='view') }}

SELECT
    f.fecha_key,
    COALESCE(h.hora_key, -1) AS hora_key,
    COALESCE(zr.zona_key, -1) AS zona_recogida_key,
    COALESCE(zd.zona_key, -1) AS zona_destino_key,
    COALESCE(v.vendor_key, -1) AS vendor_key,
    COALESCE(r.tarifa_key, -1) AS tarifa_key,
    COALESCE(p.pago_key, -1) AS pago_key,
    t.tpep_pickup_datetime AS fecha_hora_recogida,
    t.tpep_dropoff_datetime AS fecha_hora_destino,
    t.passenger_count AS pasajeros,
    t.ratecodeid AS ratecodeid,
    t.trip_distance AS distancia_millas,
    t.duracion_min,
    t.velocidad_mph,
    t.fare_amount AS tarifa_base,
    t.extra,
    t.mta_tax AS impuesto_mta,
    t.tip_amount AS propina,
    t.tolls_amount AS peajes,
    t.improvement_surcharge AS recargo_mejora,
    t.congestion_surcharge AS recargo_congestion,
    t.airport_fee AS tarifa_aeropuerto,
    t.cbd_congestion_fee AS recargo_zona_central,
    t.total_amount AS importe_total,
    t.flag_distancia_no_positiva,
    t.flag_tarifa_no_positiva,
    t.flag_duracion_negativa,
    t.flag_distancia_extrema,
    t.source_file
FROM {{ source('silver', 'trips_clean') }} t
JOIN {{ source('gold', 'dim_fecha') }} f
    ON f.fecha = t.fecha_recogida
LEFT JOIN {{ source('gold', 'dim_hora') }} h
    ON h.hora_24 = t.hora_recogida
LEFT JOIN {{ source('gold', 'dim_zona') }} zr
    ON zr.zona_key = t.pulocationid
LEFT JOIN {{ source('gold', 'dim_zona') }} zd
    ON zd.zona_key = t.dolocationid
LEFT JOIN {{ source('gold', 'dim_vendor') }} v
    ON v.vendor_key = t.vendorid
LEFT JOIN {{ source('gold', 'dim_tarifa') }} r
    ON r.tarifa_key = t.ratecodeid
LEFT JOIN {{ source('gold', 'dim_pago') }} p
    ON p.pago_key = t.payment_type