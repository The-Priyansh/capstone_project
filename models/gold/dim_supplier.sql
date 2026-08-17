{{ config(
    materialized='table'
) }}

WITH supplier_source AS (

    SELECT
        supplier_id,
        supplier_name,
        supplier_type,
        contact_person,
        contact_email,
        phone,
        contact_address,
        payment_terms
    FROM {{ ref('silver_suppliers') }}

),

supplier_cleaned AS (

    SELECT
        supplier_id,

        INITCAP(
            TRIM(supplier_name)
        ) AS supplier_name,

        INITCAP(
            TRIM(supplier_type)
        ) AS supplier_type,

        CONCAT_WS(
            ' | ',

            NULLIF(
                INITCAP(TRIM(contact_person)),
                ''
            ),

            NULLIF(
                LOWER(TRIM(contact_email)),
                ''
            ),

            NULLIF(
                TRIM(phone),
                ''
            ),

            NULLIF(
                INITCAP(TRIM(contact_address)),
                ''
            )

        ) AS contact_information,

        INITCAP(
            TRIM(payment_terms)
        ) AS payment_terms

    FROM supplier_source

),

final AS (

    SELECT
        SHA2(
            CONCAT(
                'SUPPLIER|',
                supplier_id
            ),
            256
        ) AS supplier_key,

        supplier_id,
        supplier_name,
        contact_information,
        payment_terms,
        supplier_type

    FROM supplier_cleaned

    WHERE supplier_id IS NOT NULL

)

SELECT
    supplier_key,
    supplier_id,
    supplier_name,
    contact_information,
    payment_terms,
    supplier_type

FROM final