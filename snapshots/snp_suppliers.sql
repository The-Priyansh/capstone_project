{% snapshot snp_suppliers %}

{{
    config(
        unique_key='supplier_id',
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

    FROM {{ ref('bronze_suppliers') }}

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
        supplier.value:supplier_id::VARCHAR AS supplier_id,

        supplier.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        supplier.value AS raw_supplier_data,

        _SOURCE_FILE

    FROM latest_source,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:suppliers_data
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
        ORDER BY _SOURCE_FILE DESC
    ) = 1

)

SELECT
    supplier_id,
    last_modified_date,
    raw_supplier_data

FROM latest_supplier

{% endsnapshot %}