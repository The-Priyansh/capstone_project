{{ config(
    materialized='table'
) }}

WITH store_source AS (

    SELECT
        store_id,
        store_name,
        standardized_address,
        region,
        store_type,
        opening_date,
        size_category
    FROM {{ ref('silver_stores') }}

),

store_cleaned AS (

    SELECT

        SHA2(
            CONCAT(
                'STORE|',
                store_id
            ),
            256
        ) AS store_key,

        store_id,

        INITCAP(
            TRIM(store_name)
        ) AS store_name,

        TRIM(standardized_address) AS address,

        INITCAP(
            TRIM(region)
        ) AS region,

        INITCAP(
            TRIM(store_type)
        ) AS store_type,

        opening_date,

        INITCAP(
            TRIM(size_category)
        ) AS size_category

    FROM store_source

)

SELECT
    store_key,
    store_id,
    store_name,
    address,
    region,
    store_type,
    opening_date,
    size_category

FROM store_cleaned

WHERE store_id IS NOT NULL