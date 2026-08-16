SELECT
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,

    SUM(f.new_customers_acquired) AS new_customers_acquired,

    ROUND(
        AVG(f.repeat_purchase_rate),
        2
    ) AS avg_repeat_purchase_rate,

    COUNT(
        DISTINCT f.date_key
    ) AS engagement_days,

    MIN(d.full_date) AS first_engagement_date,

    MAX(d.full_date) AS last_engagement_date

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
    new_customers_acquired DESC,
    avg_repeat_purchase_rate DESC