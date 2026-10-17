# NYC Taxi - Validación con dbt

## Objetivo
Validar reglas de calidad y preparar una vista de consulta para análisis
de viajes NYC Yellow Taxi, sin modificar las tablas productivas existentes.

## Entorno
- PostgreSQL: base de datos `nyc_taxi`
- Proyecto dbt: `nyc_taxi_dbt`
- Perfil dbt: `nyc_taxi_dbt`
- Esquema de validación: `dbt_validation`

## Fuentes de datos
- Bronze: `public.yellow_tripdata`
- Silver: `silver.trips_clean`
- Dimensiones Gold: `gold.dim_fecha`, `gold.dim_hora`,
  `gold.dim_zona`, `gold.dim_vendor`, `gold.dim_tarifa`,
  `gold.dim_pago`

## Modelos dbt
- `stg_yellow_tripdata`: acceso de lectura a Bronze.
- `int_trips_clean_validation`: lógica de validación de viajes.
- `int_dq_rules_validation`: resumen de reglas de calidad.
- `fct_trips_validation`: vista de viajes con claves dimensionales,
  creada en `dbt_validation`.

## Pruebas ejecutadas
- `test_tarifa_nula_asignada_desconocida`: PASS.
- `test_dq_agosto_2026`: PASS. Compara los totales y las reglas
  RC-01 y RC-02 de agosto de 2026 con `silver.dq_log`.

Estas pruebas cubren las condiciones indicadas; no equivalen a una
validación exhaustiva de todos los meses y dimensiones.

## Comandos
Desde la carpeta `PostgreSQL-Docker`:

```powershell
.\.venv-dbt\Scripts\dbt.exe parse --project-dir .\nyc_taxi_dbt
.\.venv-dbt\Scripts\dbt.exe test --project-dir .\nyc_taxi_dbt --select test_tarifa_nula_asignada_desconocida
.\.venv-dbt\Scripts\dbt.exe test --project-dir .\nyc_taxi_dbt --select test_dq_agosto_2026
```

## Consulta para Grafana
Vista disponible:
`dbt_validation.fct_trips_validation`

El equipo de Grafana debe conectarse a PostgreSQL usando credenciales
autorizadas y consultar esta vista para sus paneles. Se recomienda
seleccionar periodos concretos y limitar los datos de cada panel.

## Precauciones
- No ejecutar `transformar_silver.sql`: trunca tablas productivas.
- No ejecutar `cargar_fact_trips.py`: carga Gold.
- Evitar `dbt run` o `dbt build` sin seleccionar explícitamente
  los modelos que se desean ejecutar.
- No incluir contraseñas en este archivo ni en el repositorio.