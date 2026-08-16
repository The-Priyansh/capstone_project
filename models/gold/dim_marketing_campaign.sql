{{ config(
    materialized='table'
) }}

WITH source_campaigns AS (

    SELECT
        campaign_id,
        campaign_name,
        campaign_type,
        target_audience,
        audience_segment,
        budget,
        total_cost,
        total_revenue,
        source_roi,
        start_date,
        end_date

    FROM {{ ref('silver_campaigns') }}

),

final AS (

    SELECT

        /* Surrogate key */
        {{ dbt_utils.generate_surrogate_key(['campaign_id']) }}
            AS campaign_key,

        /* Natural key */
        campaign_id,

        /* Campaign attributes */
        INITCAP(TRIM(campaign_name))
            AS campaign_name,

        INITCAP(TRIM(campaign_type))
            AS campaign_type,

        TRIM(target_audience)
            AS target_audience,

        INITCAP(TRIM(audience_segment))
            AS target_audience_segment,

        /* Already numeric in Silver */
        budget
            AS budget,

        total_cost
            AS total_campaign_cost,

        total_revenue
            AS source_total_revenue,

        /* Source-provided ROI */
        source_roi
            AS source_roi,

        /* Dates */
        start_date,
        end_date,

        /* Derive duration */
        CASE
            WHEN start_date IS NOT NULL
             AND end_date IS NOT NULL
             AND end_date >= start_date
            THEN DATEDIFF(day, start_date, end_date) + 1
            ELSE NULL
        END AS duration_days

    FROM source_campaigns

)

SELECT *
FROM final