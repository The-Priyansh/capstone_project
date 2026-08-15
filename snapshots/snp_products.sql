{% snapshot snp_products %}

{{
    config(
        unique_key='product_id',
        strategy='timestamp',
        updated_at='last_modified_date'
    )
}}

WITH source_files AS (

    SELECT
        RAW_DATA,
        _SOURCE_FILE,

        TRY_TO_DATE(
            REGEXP_SUBSTR(
                _SOURCE_FILE,
                '[0-9]{4}-[0-9]{2}-[0-9]{2}'
            )
        ) AS source_snapshot_date

    FROM {{ ref('bronze_products') }}

),

latest_source_date AS (

    SELECT
        MAX(source_snapshot_date) AS max_source_snapshot_date
    FROM source_files

),

latest_source AS (

    SELECT
        s.RAW_DATA,
        s._SOURCE_FILE,
        s.source_snapshot_date

    FROM source_files s
    CROSS JOIN latest_source_date d

    WHERE s.source_snapshot_date = d.max_source_snapshot_date

),

flattened AS (

    SELECT
        product.value:product_id::VARCHAR AS product_id,

        product.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        product.value AS raw_product_data,

        _SOURCE_FILE

    FROM latest_source,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:products_data
    ) AS product

),

latest_product AS (

    SELECT
        product_id,
        last_modified_date,
        raw_product_data

    FROM flattened

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY product_id
        ORDER BY _SOURCE_FILE DESC
    ) = 1

)

SELECT
    product_id,
    last_modified_date,
    raw_product_data

FROM latest_product

{% endsnapshot %}