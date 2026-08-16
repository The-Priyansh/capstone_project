SELECT
    p.category,

    SUM(f.inventory_value) AS inventory_value,

    SUM(f.sold_quantity) AS units_sold,

    SUM(f.purchased_quantity) AS units_purchased,

    SUM(f.ending_stock) AS ending_stock,

    COUNT_IF(
        f.low_stock_flag = TRUE
    ) AS low_stock_days,

    COUNT_IF(
        f.negative_stock_flag = TRUE
    ) AS negative_stock_days,

    COUNT_IF(
        f.negative_inferred_purchase_flag = TRUE
    ) AS negative_inferred_purchase_days,

    COUNT_IF(
        f.stale_product_snapshot_flag = TRUE
    ) AS stale_snapshot_days,

    ROUND(
        AVG(f.stock_turnover_ratio),
        4
    ) AS avg_stock_turnover_ratio,

    ROUND(
        AVG(f.supplier_contribution_percentage),
        2
    ) AS avg_supplier_contribution_percentage

FROM {{ ref('fact_inventory') }} AS f

LEFT JOIN {{ ref('dim_product') }} AS p
    ON f.product_key = p.product_key

GROUP BY
    p.category

ORDER BY
    inventory_value DESC