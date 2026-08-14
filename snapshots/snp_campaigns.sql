{% snapshot snp_campaigns %}

{{
    config(
        unique_key='campaign_id',
        strategy='timestamp',
        updated_at='last_modified_date'
    )
}}

WITH flattened AS (

    SELECT
        campaign.value:campaign_id::VARCHAR AS campaign_id,

        campaign.value:last_modified_date::TIMESTAMP_NTZ
            AS last_modified_date,

        campaign.value AS raw_campaign_data,

        b._SOURCE_FILE

    FROM {{ ref('bronze_campaigns') }} AS b,

    LATERAL FLATTEN(
        INPUT => b.RAW_DATA:campaigns_data
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
        ORDER BY
            last_modified_date DESC,
            _SOURCE_FILE DESC
    ) = 1

)

SELECT
    campaign_id,
    last_modified_date,
    raw_campaign_data

FROM latest_campaign

{% endsnapshot %}