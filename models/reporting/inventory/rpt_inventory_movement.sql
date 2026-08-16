WITH product_velocity AS (

    SELECT
        p.product_id,
        p.product_name,
        p.category,
        p.subcategory,

        SUM(f.sold_quantity) AS total_sold_quantity,

        ROUND(
            AVG(f.stock_turnover_ratio),
            4
        ) AS avg_stock_turnover_ratio,

        ROUND(
            AVG(f.average_inventory),
            2
        ) AS avg_inventory,

        SUM(f.ending_stock) AS total_ending_stock,

        SUM(f.inventory_value) AS total_inventory_value

    FROM {{ ref('fact_inventory') }} AS f

    INNER JOIN {{ ref('dim_product') }} AS p
        ON f.product_key = p.product_key

    GROUP BY
        p.product_id,
        p.product_name,
        p.category,
        p.subcategory
),

classified AS (

    SELECT
        *,
        CASE
            WHEN avg_stock_turnover_ratio >= 1
                THEN 'FAST_MOVING'

            WHEN avg_stock_turnover_ratio < 0.25
                THEN 'SLOW_MOVING'

            ELSE 'MEDIUM_MOVING'
        END AS movement_class

    FROM product_velocity
)

SELECT
    product_id,
    product_name,
    category,
    subcategory,
    total_sold_quantity,
    avg_stock_turnover_ratio,
    avg_inventory,
    total_ending_stock,
    total_inventory_value,
    movement_class

FROM classified

ORDER BY
    CASE movement_class
        WHEN 'FAST_MOVING' THEN 1
        WHEN 'MEDIUM_MOVING' THEN 2
        WHEN 'SLOW_MOVING' THEN 3
    END,
    avg_stock_turnover_ratio DESC