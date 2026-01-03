use master;
set nocount on
 
declare
    @failover_mirror_databases  varchar(max) = ''
select
    @failover_mirror_databases  = @failover_mirror_databases + 
    'alter database [' + cast(DB_NAME(database_id) as varchar(255)) + '] set partner failover;' + char(10) + char(10)
from
    sys.database_mirroring
where
    mirroring_guid is not null
    and mirroring_role_desc = 'PRINCIPAL'
 
exec (@failover_mirror_databases)
