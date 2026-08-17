{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        campaign_id,
        last_modified_date,
        raw_campaign_data,
        dbt_scd_id,
        dbt_updated_at,
        dbt_valid_from,
        dbt_valid_to

    FROM {{ ref('snp_campaigns') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        --CAMPAIGN ID

        NULLIF(
            TRIM(campaign_id),
            ''
        )::VARCHAR AS campaign_id,


        --CAMPAIGN ATTRIBUTES

        INITCAP(
            TRIM(raw_campaign_data:campaign_name::VARCHAR)
        )::VARCHAR AS campaign_name,

        INITCAP(
            TRIM(raw_campaign_data:campaign_type::VARCHAR)
        )::VARCHAR AS campaign_type,

        INITCAP(
            TRIM(raw_campaign_data:channel::VARCHAR)
        )::VARCHAR AS channel,

        TRIM(
            raw_campaign_data:description::VARCHAR
        )::VARCHAR AS description,


        --TARGET AUDIENCE

        TRIM(
            raw_campaign_data:target_audience::VARCHAR
        )::VARCHAR AS target_audience,


        --DATES
        

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(
                TRIM(raw_campaign_data:start_date::VARCHAR),
                ''
            )
        ) AS start_date,

        TRY_TO_TIMESTAMP_NTZ(
            NULLIF(
                TRIM(raw_campaign_data:end_date::VARCHAR),
                ''
            )
        ) AS end_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_campaign_data:last_modified_date::VARCHAR),
                ''
            )
        )::DATE AS last_modified_date,


        /*  CURRENCY VALUES
           USD only in this dataset

           Handles:
             $24,005.75
             24,005.75
             $ 24,005.75
        */

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(raw_campaign_data:budget::VARCHAR),
                '[$,]',
                ''
            ),
            18,
            2
        )::NUMBER(18,2) AS budget,

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(raw_campaign_data:total_cost::VARCHAR),
                '[$,]',
                ''
            ),
            18,
            2
        )::NUMBER(18,2) AS total_cost,

        TRY_TO_DECIMAL(
            REGEXP_REPLACE(
                TRIM(raw_campaign_data:total_revenue::VARCHAR),
                '[$,]',
                ''
            ),
            18,
            2
        )::NUMBER(18,2) AS total_revenue,


        /*  SOURCE ROI

           PS says ROI validation belongs
           in Gold because attributed sales
           do not exist until Gold.

           Therefore:
           parse only, don't validate here.
        */

        TRY_TO_DECIMAL(
            NULLIF(
                TRIM(raw_campaign_data:roi_calculation::VARCHAR),
                ''
            ),
            10,
            2
        )::NUMBER(10,2) AS source_roi,


        --SNAPSHOT METADATA


        dbt_scd_id::VARCHAR AS dbt_scd_id,

        dbt_updated_at::TIMESTAMP_NTZ
            AS dbt_updated_at,

        dbt_valid_from::TIMESTAMP_NTZ
            AS dbt_valid_from,

        dbt_valid_to::TIMESTAMP_NTZ
            AS dbt_valid_to

    FROM source_data

),

derived AS (

    SELECT

        c.*,

        /* CAMPAIGN DURATION

           Endpoints expressed as dates.
           DATEDIFF gives the elapsed day
           difference.*/

        CASE
            WHEN c.start_date IS NOT NULL
             AND c.end_date IS NOT NULL
             AND c.end_date >= c.start_date
            THEN DATEDIFF(
                DAY,
                CAST(c.start_date AS DATE),
                CAST(c.end_date AS DATE)
            )
            ELSE NULL
        END::NUMBER(10,0) AS campaign_duration_days,


        /* AUDIENCE SEGMENT

           Derived from the demographic
           portion of target_audience. */

        CASE

            WHEN UPPER(c.target_audience)
                 LIKE '%STUDENTS%'
                THEN 'Student'

            WHEN UPPER(c.target_audience)
                 LIKE '%FAMILIES%'
                THEN 'Family'

            WHEN UPPER(c.target_audience)
                 LIKE '%PROFESSIONALS%'
                THEN 'Professional'

            WHEN UPPER(c.target_audience)
                 LIKE '%SENIORS%'
                THEN 'Senior'

            ELSE 'Other'

        END::VARCHAR AS audience_segment

    FROM cleaned c

),

deduplicated AS (

    SELECT *

    FROM derived

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY campaign_id

        ORDER BY
            last_modified_date DESC NULLS LAST,
            dbt_valid_from DESC NULLS LAST,
            dbt_updated_at DESC NULLS LAST,
            dbt_scd_id DESC

    ) = 1

)

SELECT

    campaign_id,

    campaign_name,
    campaign_type,
    channel,
    description,

    target_audience,
    audience_segment,

    budget,
    total_cost,
    total_revenue,
    source_roi,

    start_date,
    end_date,
    campaign_duration_days,
    last_modified_date,

    dbt_scd_id,
    dbt_updated_at,
    dbt_valid_from,
    dbt_valid_to

FROM deduplicated