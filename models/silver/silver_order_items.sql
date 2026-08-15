{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        _SOURCE_FILE,
        _FILE_ROW_NUMBER,
        _LOADED_AT,
        _BATCH_ID,
        RAW_DATA

    FROM {{ ref('bronze_orders') }}

),

orders_flattened AS (

    SELECT

        _SOURCE_FILE,
        _FILE_ROW_NUMBER,
        _LOADED_AT,
        _BATCH_ID,

        order_data.value AS order_data

    FROM source_data,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:orders_data
    ) order_data

),

order_items_flattened AS (

    SELECT

        _SOURCE_FILE,
        _FILE_ROW_NUMBER,
        _LOADED_AT,
        _BATCH_ID,

        NULLIF(
            TRIM(order_data:order_id::VARCHAR),
            ''
        )::VARCHAR AS order_id,

        TRY_TO_TIMESTAMP_NTZ(
            order_data:order_date::VARCHAR
        ) AS order_date,

        LOWER(
            TRIM(order_data:order_status::VARCHAR)
        )::VARCHAR AS order_status,

        NULLIF(
            TRIM(order_data:customer_id::VARCHAR),
            ''
        )::VARCHAR AS customer_id,

        NULLIF(
            TRIM(order_data:store_id::VARCHAR),
            ''
        )::VARCHAR AS store_id,

        item.index::NUMBER AS item_number,

        NULLIF(
            TRIM(item.value:product_id::VARCHAR),
            ''
        )::VARCHAR AS product_id,

        TRY_TO_NUMBER(
            item.value:quantity::VARCHAR
        )::NUMBER(18,0) AS quantity,

        TRY_TO_DECIMAL(
            item.value:unit_price::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS unit_price,

        TRY_TO_DECIMAL(
            item.value:cost_price::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS cost_price,

        TRY_TO_DECIMAL(
            item.value:discount_amount::VARCHAR,
            10,
            4
        )::NUMBER(10,4) AS discount_percentage,

        (
            COALESCE(
                TRY_TO_DECIMAL(
                    item.value:discount_amount::VARCHAR,
                    10,
                    4
                ),
                0
            ) / 100
        )::NUMBER(12,8) AS discount_rate

    FROM orders_flattened,

    LATERAL FLATTEN(
        INPUT => order_data:order_items
    ) item

)

SELECT

    MD5(
        CONCAT(
            COALESCE(order_id, ''),
            '|',
            COALESCE(item_number::VARCHAR, '')
        )
    )::VARCHAR AS order_item_key,

    _SOURCE_FILE,
    _FILE_ROW_NUMBER,
    _LOADED_AT,
    _BATCH_ID,

    order_id,
    item_number,

    order_date,
    order_status,

    customer_id,
    store_id,
    product_id,

    quantity,
    unit_price,
    cost_price,

    discount_percentage,
    discount_rate

FROM order_items_flattened