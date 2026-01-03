use master;
set nocount on
 
declare
    @set_full_safety_off_on_mirror_databases    varchar(max) = ''
select
    @set_full_safety_off_on_mirror_databases    = @set_full_safety_off_on_mirror_databases  + 
    'alter database [' + cast(DB_NAME(database_id) as varchar(255)) + '] set safety off;'       + char(10)
from
    sys.database_mirroring
where
    mirroring_guid is not null
    and mirroring_role_desc = 'PRINCIPAL'
 
exec (@set_full_safety_off_on_mirror_databases)
