{% snapshot snp_stores %}

{{
    config(
        unique_key='store_id',
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

    FROM {{ ref('bronze_stores') }}

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
        store.value:store_id::VARCHAR AS store_id,

        store.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        store.value AS raw_store_data,

        _SOURCE_FILE

    FROM latest_source,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:stores_data
    ) AS store

),

latest_store AS (

    SELECT
        store_id,
        last_modified_date,
        raw_store_data

    FROM flattened

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY store_id
        ORDER BY _SOURCE_FILE DESC
    ) = 1

)

SELECT
    store_id,
    last_modified_date,
    raw_store_data

FROM latest_store

{% endsnapshot %}