with dbt_result as (
    select
        periodo,
        max(total_origen) as total_origen,
        sum(rc01_afectados) as rc01,
        sum(rc02_duracion_negativa) as rc02
    from {{ ref('int_dq_rules_validation') }}
    where periodo = '2026-08'
    group by periodo
),
silver_result as (
    select
        max(total_origen) as total_origen,
        sum(registros_afectados) filter (
            where regla = 'RC-01'
        ) as rc01,
        sum(registros_afectados) filter (
            where regla = 'RC-02_DURACION_NEGATIVA'
        ) as rc02
    from silver.dq_log
    where anio_origen = 2026
      and mes_origen = 8
)
select *
from dbt_result d
cross join silver_result s
where d.total_origen is distinct from s.total_origen
   or d.rc01 is distinct from s.rc01
   or d.rc02 is distinct from s.rc02