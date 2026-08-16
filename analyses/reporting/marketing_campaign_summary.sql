SELECT

    c.campaign_id,
    c.campaign_name,
    c.campaign_type,

    SUM(
        f.total_sales_influenced
    ) AS total_sales_influenced,

    SUM(
        f.new_customers_acquired
    ) AS new_customers_acquired,

    ROUND(
        AVG(f.repeat_purchase_rate),
        2
    ) AS avg_repeat_purchase_rate,

    ROUND(
        AVG(f.roi),
        2
    ) AS avg_roi,

    MIN(d.full_date) AS first_reporting_date,

    MAX(d.full_date) AS last_reporting_date,

    COUNT(
        DISTINCT f.date_key
    ) AS reporting_days

FROM {{ ref('fact_marketing_performance') }} AS f

LEFT JOIN {{ ref('dim_marketing_campaign') }} AS c
    ON f.campaign_key = c.campaign_key

LEFT JOIN {{ ref('dim_date') }} AS d
    ON f.date_key = d.date_key

GROUP BY
    c.campaign_id,
    c.campaign_name,
    c.campaign_type

ORDER BY
    total_sales_influenced DESC