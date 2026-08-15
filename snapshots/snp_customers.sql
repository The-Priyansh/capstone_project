{% snapshot snp_customers %}

{{
    config(
        unique_key='customer_id',
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

    FROM {{ ref('bronze_customers') }}

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
        customer.value:customer_id::VARCHAR AS customer_id,

        customer.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        customer.value AS raw_customer_data,

        _SOURCE_FILE

    FROM latest_source,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:customers_data
    ) AS customer

),

latest_customer AS (

    SELECT
        customer_id,
        last_modified_date,
        raw_customer_data

    FROM flattened

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY _SOURCE_FILE DESC
    ) = 1

)

SELECT
    customer_id,
    last_modified_date,
    raw_customer_data

FROM latest_customer

{% endsnapshot %}