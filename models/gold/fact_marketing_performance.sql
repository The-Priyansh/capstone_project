{{ config(
    materialized = 'table'
) }}

WITH campaigns AS (

    SELECT
        campaign_key,
        campaign_id,
        start_date::DATE AS start_date,
        end_date::DATE AS end_date,
        total_campaign_cost
    FROM {{ ref('dim_marketing_campaign') }}

),

date_spine AS (

    SELECT
        date_key,
        full_date
    FROM {{ ref('dim_date') }}

),

/*
    One row per campaign per active date.

    This explicitly establishes the required fact grain:
    campaign + date.
*/
campaign_dates AS (

    SELECT
        c.campaign_key,
        c.campaign_id,
        c.start_date,
        c.end_date,
        c.total_campaign_cost,
        d.date_key,
        d.full_date
    FROM campaigns c
    INNER JOIN date_spine d
        ON d.full_date BETWEEN c.start_date AND c.end_date

),

/*
    Only completed orders participate in marketing attribution.
*/
completed_orders AS (

    SELECT
        order_id,
        customer_id,
        campaign_id,
        order_date_only,
        source_total_amount
    FROM {{ ref('silver_orders') }}
    WHERE UPPER(order_status) = 'COMPLETED'
      AND campaign_id IS NOT NULL
      AND order_date_only IS NOT NULL

),

/*
    First completed purchase date for each customer.
*/
customer_first_purchase AS (

    SELECT
        customer_id,
        MIN(order_date_only) AS first_purchase_date
    FROM completed_orders
    GROUP BY customer_id

),

/*
    Orders attributed to a campaign.

    Attribution rule:
    campaign_id must match and order date must fall
    inside the campaign active window.
*/
attributed_orders AS (

    SELECT
        c.campaign_key,
        c.campaign_id,
        c.start_date,
        c.end_date,
        c.total_campaign_cost,

        o.order_id,
        o.customer_id,
        o.order_date_only,
        o.source_total_amount,

        fp.first_purchase_date

    FROM campaigns c

    INNER JOIN completed_orders o
        ON o.campaign_id = c.campaign_id
       AND o.order_date_only BETWEEN c.start_date AND c.end_date

    LEFT JOIN customer_first_purchase fp
        ON o.customer_id = fp.customer_id

),

/*
    Daily campaign metrics.

    Grain:
        campaign_key + order_date_only
*/
daily_metrics AS (

    SELECT
        campaign_key,
        campaign_id,
        order_date_only,

        SUM(source_total_amount) AS total_sales_influenced,

        COUNT(DISTINCT customer_id) AS campaign_customers,

        /*
            A customer is newly acquired on the date of
            their first completed purchase.
        */
        COUNT(
            DISTINCT CASE
                WHEN first_purchase_date = order_date_only
                THEN customer_id
            END
        ) AS new_customers_acquired,

        /*
            A repeat customer has an earlier completed purchase.
        */
        COUNT(
            DISTINCT CASE
                WHEN first_purchase_date < order_date_only
                THEN customer_id
            END
        ) AS repeat_customers

    FROM attributed_orders

    GROUP BY
        campaign_key,
        campaign_id,
        order_date_only

),

/*
    Combine the complete campaign/date spine with metrics.

    Dates with no campaign orders are retained with zero metrics.
*/
final AS (

    SELECT
        cd.campaign_key,
        cd.campaign_id,
        cd.date_key,
        cd.full_date,
        cd.total_campaign_cost,

        COALESCE(dm.total_sales_influenced, 0) AS total_sales_influenced,

        COALESCE(dm.new_customers_acquired, 0)
            AS new_customers_acquired,

        COALESCE(
            ROUND(
                100.0
                * dm.repeat_customers
                / NULLIF(dm.campaign_customers, 0),
                2
            ),
            0
        ) AS repeat_purchase_rate

    FROM campaign_dates cd

    LEFT JOIN daily_metrics dm
        ON cd.campaign_key = dm.campaign_key
       AND cd.full_date = dm.order_date_only

)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'campaign_key',
        'date_key'
    ]) }} AS marketing_performance_key,

    campaign_key,
    date_key,

    total_sales_influenced,
    new_customers_acquired,
    repeat_purchase_rate,

    /*
        PS ROI formula:
        (Total Sales Influenced - Total Campaign Cost)
        / Total Campaign Cost * 100
    */
    ROUND(
        CASE
            WHEN total_campaign_cost > 0
            THEN
                (
                    total_sales_influenced
                    - total_campaign_cost
                )
                / total_campaign_cost * 100
            ELSE NULL
        END,
        2
    ) AS roi

FROM final