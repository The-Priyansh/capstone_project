{% snapshot snp_suppliers %}

{{
    config(
        unique_key='supplier_id',
        strategy='timestamp',
        updated_at='last_modified_date'
    )
}}

WITH flattened AS (

    SELECT
        supplier.value:supplier_id::VARCHAR AS supplier_id,

        supplier.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        supplier.value AS raw_supplier_data,

        b._SOURCE_FILE

    FROM {{ ref('bronze_suppliers') }} AS b,

    LATERAL FLATTEN(
        INPUT => b.RAW_DATA:suppliers_data
    ) AS supplier

),

latest_supplier AS (

    SELECT
        supplier_id,
        last_modified_date,
        raw_supplier_data

    FROM flattened

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY supplier_id
        ORDER BY
            last_modified_date DESC,
            _SOURCE_FILE DESC
    ) = 1

)

SELECT
    supplier_id,
    last_modified_date,
    raw_supplier_data

FROM latest_supplier

{% endsnapshot %}