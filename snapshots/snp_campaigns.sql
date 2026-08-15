{% snapshot snp_campaigns %}

{{
    config(
        unique_key='campaign_id',
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

    FROM {{ ref('bronze_campaigns') }}

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
        campaign.value:campaign_id::VARCHAR AS campaign_id,

        campaign.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        campaign.value AS raw_campaign_data,

        _SOURCE_FILE

    FROM latest_source,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:campaigns_data
    ) AS campaign

),

latest_campaign AS (

    SELECT
        campaign_id,
        last_modified_date,
        raw_campaign_data

    FROM flattened

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY campaign_id
        ORDER BY _SOURCE_FILE DESC
    ) = 1

)

SELECT
    campaign_id,
    last_modified_date,
    raw_campaign_data

FROM latest_campaign

{% endsnapshot %}