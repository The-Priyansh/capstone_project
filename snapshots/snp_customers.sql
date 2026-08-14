{% snapshot snp_customers %}

{{
    config(
        unique_key='customer_id',
        strategy='timestamp',
        updated_at='last_modified_date'
    )
}}

WITH flattened AS (

    SELECT
        customer.value:customer_id::VARCHAR AS customer_id,

        customer.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        customer.value AS raw_customer_data,

        b._SOURCE_FILE

    FROM {{ ref('bronze_customers') }} AS b,

    LATERAL FLATTEN(
        INPUT => b.RAW_DATA:customers_data
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
        ORDER BY
            last_modified_date DESC,
            _SOURCE_FILE DESC
    ) = 1

)

SELECT
    customer_id,
    last_modified_date,
    raw_customer_data

FROM latest_customer

{% endsnapshot %}