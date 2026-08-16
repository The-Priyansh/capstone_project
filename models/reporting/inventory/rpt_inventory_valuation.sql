SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.subcategory,

    SUM(f.ending_stock) AS total_ending_stock,

    ROUND(
        SUM(f.inventory_value),
        2
    ) AS total_inventory_value,

    ROUND(
        AVG(f.inventory_value),
        2
    ) AS avg_daily_inventory_value,

    ROUND(
        AVG(p.cost_price),
        2
    ) AS avg_cost_price,

    SUM(f.purchased_quantity) AS total_purchased_quantity,

    SUM(f.sold_quantity) AS total_sold_quantity,

    COUNT_IF(
        f.low_stock_flag = TRUE
    ) AS low_stock_days,

    COUNT_IF(
        f.negative_stock_flag = TRUE
    ) AS negative_stock_days,

    COUNT_IF(
        f.stale_product_snapshot_flag = TRUE
    ) AS stale_snapshot_days

FROM {{ ref('fact_inventory') }} AS f

INNER JOIN {{ ref('dim_product') }} AS p
    ON f.product_key = p.product_key

GROUP BY
    p.product_id,
    p.product_name,
    p.category,
    p.subcategory

ORDER BY
    total_inventory_value DESC