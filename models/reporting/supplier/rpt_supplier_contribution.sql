SELECT
    s.supplier_id,
    s.supplier_name,

    p.category,

    SUM(f.purchased_quantity) AS total_purchased_quantity,

    ROUND(
        SUM(f.inventory_value),
        2
    ) AS total_inventory_value,

    ROUND(
        AVG(f.supplier_contribution_percentage),
        2
    ) AS avg_supplier_contribution_percentage,

    COUNT(DISTINCT p.product_id) AS products_supplied

FROM {{ ref('fact_inventory') }} AS f

INNER JOIN {{ ref('dim_supplier') }} AS s
    ON f.supplier_key = s.supplier_key

INNER JOIN {{ ref('dim_product') }} AS p
    ON f.product_key = p.product_key

GROUP BY
    s.supplier_id,
    s.supplier_name,
    p.category

ORDER BY
    total_purchased_quantity DESC