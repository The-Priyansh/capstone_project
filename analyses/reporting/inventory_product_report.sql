WITH inventory_reporting AS (

    SELECT
        f.date_key,
        d.full_date,

        f.product_key,
        p.product_id,
        p.product_name,
        p.category,
        p.subcategory,
        p.brand,

        f.supplier_key,
        s.supplier_id,
        s.supplier_name,

        f.beginning_stock,
        f.purchased_quantity,
        f.sold_quantity,
        f.ending_stock,

        f.inventory_value,
        f.stock_turnover_ratio,
        f.supplier_contribution_percentage,

        f.reorder_level,
        f.low_stock_flag,
        f.negative_stock_flag,
        f.negative_inferred_purchase_flag,

        f.snapshot_gap_flag,
        f.snapshot_gap_days,
        f.stale_product_snapshot_flag,
        f.stale_days

    FROM {{ ref('fact_inventory') }} AS f

    LEFT JOIN {{ ref('dim_date') }} AS d
        ON f.date_key = d.date_key

    LEFT JOIN {{ ref('dim_product') }} AS p
        ON f.product_key = p.product_key

    LEFT JOIN {{ ref('dim_supplier') }} AS s
        ON f.supplier_key = s.supplier_key

)

SELECT *
FROM inventory_reporting

ORDER BY
    date_key,
    product_id