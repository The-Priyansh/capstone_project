SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.subcategory,

    ROUND(
        AVG(f.stock_turnover_ratio),
        4
    ) AS avg_stock_turnover_ratio,

    SUM(f.sold_quantity) AS total_sold_quantity,

    SUM(f.ending_stock) AS total_ending_stock,

    ROUND(
        AVG(f.average_inventory),
        2
    ) AS avg_inventory,

    SUM(f.inventory_value) AS total_inventory_value,

    COUNT_IF(
        f.low_stock_flag = TRUE
    ) AS low_stock_days,

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
    avg_stock_turnover_ratio DESC