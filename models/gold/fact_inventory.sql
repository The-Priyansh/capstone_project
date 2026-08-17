{{ config(
    materialized = 'table'
) }}

WITH inventory AS (

    SELECT
        *
    FROM {{ ref('silver_inventory') }}

),

product_dim AS (

    SELECT
        product_key,
        product_id,
        effective_from,
        effective_to
    FROM {{ ref('dim_product') }}

),

supplier_dim AS (

    SELECT
        supplier_key,
        supplier_id
    FROM {{ ref('dim_supplier') }}

),

date_dim AS (

    SELECT
        date_key,
        full_date
    FROM {{ ref('dim_date') }}

),

joined AS (

    SELECT
        i.inventory_date,
        i.product_id,
        i.supplier_id,

        p.product_key,
        s.supplier_key,
        d.date_key,

        i.beginning_stock,
        i.purchased_quantity,
        i.sold_quantity,
        i.ending_stock,

        i.inventory_value,
        i.average_inventory,
        i.stock_turnover_ratio,
        i.supplier_contribution_percentage,

        i.reorder_level,
        i.low_stock_flag,
        i.negative_stock_flag,
        i.negative_inferred_purchase_flag,

        i.previous_snapshot_date,
        i.snapshot_gap_days,
        i.snapshot_gap_flag,

        i.analysis_end_date,
        i.stale_product_snapshot_flag,
        i.stale_days

    FROM inventory i

    LEFT JOIN product_dim p
        ON i.product_id = p.product_id
       AND i.inventory_date >= p.effective_from
       AND (
            p.effective_to IS NULL
            OR i.inventory_date <= p.effective_to
       )

    LEFT JOIN supplier_dim s
        ON i.supplier_id = s.supplier_id

    LEFT JOIN date_dim d
        ON i.inventory_date = d.full_date

)

SELECT
    MD5(
        CONCAT(
            COALESCE(product_key, 'UNKNOWN'),
            '|',
            TO_VARCHAR(inventory_date, 'YYYY-MM-DD')
        )
    ) AS inventory_key,

    product_key,
    date_key,
    supplier_key,

    inventory_date,

    beginning_stock,
    purchased_quantity,
    sold_quantity,
    ending_stock,

    inventory_value,
    average_inventory,

    stock_turnover_ratio,
    supplier_contribution_percentage,

    reorder_level,
    low_stock_flag,

    negative_stock_flag,
    negative_inferred_purchase_flag,

    previous_snapshot_date,
    snapshot_gap_days,
    snapshot_gap_flag,

    analysis_end_date,
    stale_product_snapshot_flag,
    stale_days

FROM joined