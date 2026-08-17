{{ config(
    materialized='table'
) }}

WITH date_spine AS (

    {{
        dbt_utils.date_spine(
            datepart='day',
            start_date="cast('2024-04-01' as date)",
            end_date="dateadd(day, 1, current_date())"
        )
    }}

),

calendar AS (

    SELECT
        TO_DATE(date_day) AS full_date,

        TO_NUMBER(
            TO_CHAR(TO_DATE(date_day), 'YYYYMMDD')
        ) AS date_key,

        YEAR(TO_DATE(date_day)) AS year,

        QUARTER(TO_DATE(date_day)) AS quarter,

        MONTH(TO_DATE(date_day)) AS month,

        WEEKOFYEAR(TO_DATE(date_day)) AS week,

        DAYOFWEEKISO(TO_DATE(date_day)) AS day_of_week

    FROM date_spine

),

/* ============================================================
   US HOLIDAYS
   ============================================================ */

holidays AS (

    /* New Year's Day */
    SELECT
        year,
        CASE
            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 1, 1)) = 6
                THEN DATEADD(day, -1, DATE_FROM_PARTS(year, 1, 1))

            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 1, 1)) = 7
                THEN DATEADD(day, 1, DATE_FROM_PARTS(year, 1, 1))

            ELSE DATE_FROM_PARTS(year, 1, 1)
        END AS holiday_date
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Martin Luther King Jr. Day - 3rd Monday of January */
    SELECT
        year,
        DATEADD(
            day,
            MOD(
                8 - DAYOFWEEKISO(DATE_FROM_PARTS(year, 1, 1)),
                7
            ) + 14,
            DATE_FROM_PARTS(year, 1, 1)
        )
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Presidents' Day - 3rd Monday of February */
    SELECT
        year,
        DATEADD(
            day,
            MOD(
                8 - DAYOFWEEKISO(DATE_FROM_PARTS(year, 2, 1)),
                7
            ) + 14,
            DATE_FROM_PARTS(year, 2, 1)
        )
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Memorial Day - Last Monday of May */
    SELECT
        year,
        DATEADD(
            day,
            -MOD(
                DAYOFWEEKISO(DATE_FROM_PARTS(year, 6, 1)) - 1,
                7
            ),
            DATE_FROM_PARTS(year, 6, 1)
        )
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Juneteenth */
    SELECT
        year,
        CASE
            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 6, 19)) = 6
                THEN DATEADD(day, -1, DATE_FROM_PARTS(year, 6, 19))

            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 6, 19)) = 7
                THEN DATEADD(day, 1, DATE_FROM_PARTS(year, 6, 19))

            ELSE DATE_FROM_PARTS(year, 6, 19)
        END
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Independence Day */
    SELECT
        year,
        CASE
            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 7, 4)) = 6
                THEN DATEADD(day, -1, DATE_FROM_PARTS(year, 7, 4))

            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 7, 4)) = 7
                THEN DATEADD(day, 1, DATE_FROM_PARTS(year, 7, 4))

            ELSE DATE_FROM_PARTS(year, 7, 4)
        END
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Labor Day - First Monday of September */
    SELECT
        year,
        DATEADD(
            day,
            MOD(
                8 - DAYOFWEEKISO(DATE_FROM_PARTS(year, 9, 1)),
                7
            ),
            DATE_FROM_PARTS(year, 9, 1)
        )
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Columbus Day - 2nd Monday of October */
    SELECT
        year,
        DATEADD(
            day,
            MOD(
                8 - DAYOFWEEKISO(DATE_FROM_PARTS(year, 10, 1)),
                7
            ) + 7,
            DATE_FROM_PARTS(year, 10, 1)
        )
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Veterans Day */
    SELECT
        year,
        CASE
            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 11, 11)) = 6
                THEN DATEADD(day, -1, DATE_FROM_PARTS(year, 11, 11))

            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 11, 11)) = 7
                THEN DATEADD(day, 1, DATE_FROM_PARTS(year, 11, 11))

            ELSE DATE_FROM_PARTS(year, 11, 11)
        END
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Thanksgiving - 4th Thursday of November */
    SELECT
        year,
        DATEADD(
            day,
            MOD(
                4 - DAYOFWEEKISO(DATE_FROM_PARTS(year, 11, 1)),
                7
            ) + 21,
            DATE_FROM_PARTS(year, 11, 1)
        )
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

    UNION ALL

    /* Christmas Day */
    SELECT
        year,
        CASE
            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 12, 25)) = 6
                THEN DATEADD(day, -1, DATE_FROM_PARTS(year, 12, 25))

            WHEN DAYOFWEEKISO(DATE_FROM_PARTS(year, 12, 25)) = 7
                THEN DATEADD(day, 1, DATE_FROM_PARTS(year, 12, 25))

            ELSE DATE_FROM_PARTS(year, 12, 25)
        END
    FROM (
        SELECT DISTINCT year
        FROM calendar
    )

),

final AS (

    SELECT

        c.date_key,

        c.full_date,

        c.year,

        c.quarter,

        c.month,

        c.week,

        c.day_of_week,

        CASE
            WHEN h.holiday_date IS NOT NULL
                THEN TRUE
            ELSE FALSE
        END AS holiday_flag,

        CASE
            WHEN c.month IN (12, 1, 2)
                THEN 'Winter'

            WHEN c.month IN (3, 4, 5)
                THEN 'Spring'

            WHEN c.month IN (6, 7, 8)
                THEN 'Summer'

            WHEN c.month IN (9, 10, 11)
                THEN 'Fall'
        END AS season

    FROM calendar c

    LEFT JOIN holidays h
        ON c.full_date = h.holiday_date

)

SELECT
    date_key,
    full_date,
    year,
    quarter,
    month,
    week,
    day_of_week,
    holiday_flag,
    season

FROM final