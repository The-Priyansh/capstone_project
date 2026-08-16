SELECT
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,

    ROUND(
        SUM(f.total_sales_influenced),
        2
    ) AS total_sales_influenced,

    SUM(f.new_customers_acquired) AS new_customers_acquired,

    COUNT(
        DISTINCT f.date_key
    ) AS active_reporting_days,

    MIN(d.full_date) AS first_reporting_date,

    MAX(d.full_date) AS last_reporting_date

FROM {{ ref('fact_marketing_performance') }} AS f

INNER JOIN {{ ref('dim_marketing_campaign') }} AS c
    ON f.campaign_key = c.campaign_key

INNER JOIN {{ ref('dim_date') }} AS d
    ON f.date_key = d.date_key

GROUP BY
    c.campaign_id,
    c.campaign_name,
    c.campaign_type

ORDER BY
    total_sales_influenced DESC