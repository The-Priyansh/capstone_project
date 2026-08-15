{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='product_history_key',
    on_schema_change='sync_all_columns'
) }}

WITH source_files AS (

    SELECT
        _SOURCE_FILE,
        RAW_DATA,

        TRY_TO_DATE(
            REGEXP_SUBSTR(
                _SOURCE_FILE,
                '[0-9]{4}-[0-9]{2}-[0-9]{2}'
            )
        ) AS source_snapshot_date

    FROM {{ ref('bronze_products') }}

    {% if is_incremental() %}

        WHERE TRY_TO_DATE(
            REGEXP_SUBSTR(
                _SOURCE_FILE,
                '[0-9]{4}-[0-9]{2}-[0-9]{2}'
            )
        ) > (
            SELECT COALESCE(
                MAX(source_snapshot_date),
                '1900-01-01'::DATE
            )
            FROM {{ this }}
        )

    {% endif %}

),

flattened AS (

    SELECT

        _SOURCE_FILE,

        source_snapshot_date,

        product.value AS product_data

    FROM source_files,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:products_data
    ) product

),

cleaned AS (

    SELECT

        /*
            HISTORY KEY
            One product per source snapshot.
        */

        MD5(
            CONCAT(
                COALESCE(
                    TRIM(product_data:product_id::VARCHAR),
                    ''
                ),
                '|',
                COALESCE(
                    source_snapshot_date::VARCHAR,
                    ''
                )
            )
        )::VARCHAR AS product_history_key,


        
        --SOURCE METADATA


        _SOURCE_FILE,
        source_snapshot_date,


        
        --PRODUCT ID

        NULLIF(
            TRIM(product_data:product_id::VARCHAR),
            ''
        )::VARCHAR AS product_id,


        /*
            PRODUCT NAME
            Trim + remove unwanted characters + Title Case
        */

        INITCAP(
            REGEXP_REPLACE(
                TRIM(product_data:name::VARCHAR),
                '[^A-Za-z0-9 ''-]',
                ''
            )
        )::VARCHAR AS product_name,

        --DESCRIPTION COMPONENTS


        TRIM(
            product_data:short_description::VARCHAR
        )::VARCHAR AS short_description,

        TRIM(
            product_data:technical_specs::VARCHAR
        )::VARCHAR AS technical_specs,


        
        --PRODUCT HIERARCHY
        

        INITCAP(
            TRIM(product_data:category::VARCHAR)
        )::VARCHAR AS category,

        INITCAP(
            TRIM(product_data:subcategory::VARCHAR)
        )::VARCHAR AS subcategory,

        INITCAP(
            TRIM(product_data:product_line::VARCHAR)
        )::VARCHAR AS product_line,


        
        --PRODUCT FULL DESCRIPTION
        

        TRIM(
            CONCAT_WS(
                ' - ',

                NULLIF(
                    TRIM(product_data:name::VARCHAR),
                    ''
                ),

                NULLIF(
                    TRIM(product_data:short_description::VARCHAR),
                    ''
                ),

                NULLIF(
                    TRIM(product_data:technical_specs::VARCHAR),
                    ''
                )

            )
        )::VARCHAR AS full_description,


        --PRODUCT ATTRIBUTES

        INITCAP(
            TRIM(product_data:brand::VARCHAR)
        )::VARCHAR AS brand,

        INITCAP(
            TRIM(product_data:color::VARCHAR)
        )::VARCHAR AS color,

        INITCAP(
            TRIM(product_data:size::VARCHAR)
        )::VARCHAR AS size,


        /*
            MONEY
            Handles:
                599.08
                $599.08
                $1,599.08
                1,599.08
        */

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(product_data:unit_price::VARCHAR),
                '[$,]',
                ''
            ),
            18,
            2
        )::NUMBER(18,2) AS unit_price,

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(product_data:cost_price::VARCHAR),
                '[$,]',
                ''
            ),
            18,
            2
        )::NUMBER(18,2) AS cost_price,


        
        --INVENTORY VALUES
        

        TRY_TO_NUMBER(
            TRIM(product_data:stock_quantity::VARCHAR)
        )::NUMBER(18,0) AS stock_quantity,

        TRY_TO_NUMBER(
            TRIM(product_data:reorder_level::VARCHAR)
        )::NUMBER(18,0) AS reorder_level,


        
        --OTHER PRODUCT FIELDS
        

        NULLIF(
            TRIM(product_data:supplier_id::VARCHAR),
            ''
        )::VARCHAR AS supplier_id,

        TRIM(
            product_data:dimensions::VARCHAR
        )::VARCHAR AS dimensions,

        TRIM(
            product_data:warranty_period::VARCHAR
        )::VARCHAR AS warranty_period,

        /*
            Convert "8.78 kg" -> 8.78
            All sample weights are supplied in kg.
        */

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                LOWER(
                    TRIM(product_data:weight::VARCHAR)
                ),
                '[^0-9.\-]',
                ''
            ),
            10,
            2
        )::NUMBER(10,2) AS weight_kg,

        TRY_TO_DATE(
            NULLIF(
                TRIM(product_data:launch_date::VARCHAR),
                ''
            )
        )::DATE AS launch_date,

        COALESCE(
            product_data:is_featured::BOOLEAN,
            FALSE
        )::BOOLEAN AS is_featured,

        
        --SOURCE MODIFICATION DATE
        

        TRY_TO_DATE(
            NULLIF(
                TRIM(
                    product_data:last_modified_date::VARCHAR
                ),
                ''
            )
        )::DATE AS last_modified_date

    FROM flattened

),

derived AS (

    SELECT

        c.*,


        /*
            HIERARCHICAL CATEGORY

            category > subcategory > product_line
        */

        TRIM(
            CONCAT_WS(
                ' > ',
                NULLIF(c.category, ''),
                NULLIF(c.subcategory, ''),
                NULLIF(c.product_line, '')
            )
        )::VARCHAR AS product_hierarchy,


        /*
            PROFIT MARGIN %

            (unit_price - cost_price) / unit_price * 100

            Protected against divide-by-zero.
        */

        CASE

            WHEN c.unit_price > 0

            THEN (
                (c.unit_price - c.cost_price)
                / c.unit_price
            ) * 100

            ELSE NULL

        END::NUMBER(18,2) AS profit_margin_percentage,


        /*
            LOW STOCK

            PS requirement:
            stock_quantity < reorder_level
        */

        CASE

            WHEN c.stock_quantity IS NULL
                OR c.reorder_level IS NULL
                THEN NULL

            WHEN c.stock_quantity < c.reorder_level
                THEN TRUE

            ELSE FALSE

        END::BOOLEAN AS low_stock_flag

    FROM cleaned c

),

deduplicated AS (

    SELECT *

    FROM derived

    
    --One row per product per source snapshot.
    

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY
            product_id,
            source_snapshot_date

        ORDER BY
            _SOURCE_FILE DESC

    ) = 1

)

SELECT

    product_history_key,

    _SOURCE_FILE,
    source_snapshot_date,

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
    last_modified_date

FROM deduplicated