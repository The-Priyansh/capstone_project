WITH supplier_purchase AS (

    SELECT
        s.supplier_id,
        s.supplier_name,

        SUM(f.purchased_quantity) AS supplier_purchased_quantity

    FROM {{ ref('fact_inventory') }} AS f

    INNER JOIN {{ ref('dim_supplier') }} AS s
        ON f.supplier_key = s.supplier_key

    GROUP BY
        s.supplier_id,
        s.supplier_name
),

totals AS (

    SELECT
        SUM(supplier_purchased_quantity)
            AS total_purchased_quantity
    FROM supplier_purchase
)

SELECT
    sp.supplier_id,
    sp.supplier_name,

    sp.supplier_purchased_quantity,

    ROUND(
        100.0 * sp.supplier_purchased_quantity
        / NULLIF(t.total_purchased_quantity, 0),
        2
    ) AS purchase_share_percentage,

    DENSE_RANK() OVER (
        ORDER BY sp.supplier_purchased_quantity DESC
    ) AS supplier_rank

FROM supplier_purchase sp

CROSS JOIN totals t

ORDER BY
    purchase_share_percentage DESC