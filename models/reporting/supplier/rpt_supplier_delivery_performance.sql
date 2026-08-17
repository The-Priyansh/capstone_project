SELECT
    d.supplier_key,
    d.supplier_id,
    d.supplier_name,

    s.supplier_type,
    s.is_active,
    s.contract_status,

    s.lead_time_days,
    s.average_delay_days,
    s.on_time_delivery_rate,

    CASE
        WHEN s.on_time_delivery_rate >= 95
            THEN 'ON_TIME'

        WHEN s.on_time_delivery_rate >= 85
            THEN 'MOSTLY_ON_TIME'

        ELSE 'DELAYED'
    END AS delivery_performance_category,

    s.quality_rating,
    s.defect_rate,
    s.response_time_hours

FROM {{ ref('dim_supplier') }} AS d

INNER JOIN {{ ref('silver_suppliers') }} AS s
    ON d.supplier_id = s.supplier_id