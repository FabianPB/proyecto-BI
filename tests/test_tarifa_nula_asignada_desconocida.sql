SELECT *
FROM {{ ref('fct_trips_validation') }}
WHERE source_file LIKE '%2026-08%'
  AND ratecodeid IS NULL
  AND tarifa_key <> -1