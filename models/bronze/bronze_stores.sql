with 

source as (

    select * from {{ source('external', 'EXT_STORES') }}

),

renamed as (

    select
        SOURCE_FILE AS _SOURCE_FILE,
        FILE_ROW_NUMBER AS _FILE_ROW_NUMBER,
        RAW_DATA,

        CURRENT_TIMESTAMP() AS _LOADED_AT,
        '{{ invocation_id }}' AS _BATCH_ID
    from source

)

select * from renamed