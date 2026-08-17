{{ config(
    materialized='table'
) }}

WITH current_products AS (

    SELECT *

    FROM {{ ref('silver_product_history') }}

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY product_id

        ORDER BY
            source_snapshot_date DESC,
            last_modified_date DESC,
            _SOURCE_FILE DESC

    ) = 1

)

SELECT

    product_id,

    product_name,

    full_description,
    short_description,
    technical_specs,

    category,
    subcategory,
    product_line,
    product_hierarchy,

    brand,
    color,
    size,

    unit_price,
    cost_price,
    profit_margin_percentage,

    stock_quantity,
    reorder_level,
    low_stock_flag,

    supplier_id,

    dimensions,
    weight_kg,
    warranty_period,

    is_featured,
    launch_date,
    last_modified_date,

    source_snapshot_date

FROM current_products