WITH marketing_reporting AS (

    SELECT

        f.campaign_key,

        c.campaign_id,
        c.campaign_name,
        c.campaign_type,
        c.target_audience,

        f.date_key,
        d.full_date,

        f.total_sales_influenced,
        f.new_customers_acquired,
        f.repeat_purchase_rate,
        f.roi

    FROM {{ ref('fact_marketing_performance') }} AS f

    LEFT JOIN {{ ref('dim_marketing_campaign') }} AS c
        ON f.campaign_key = c.campaign_key

    LEFT JOIN {{ ref('dim_date') }} AS d
        ON f.date_key = d.date_key

)

SELECT *
FROM marketing_reporting

ORDER BY
    date_key,
    campaign_id