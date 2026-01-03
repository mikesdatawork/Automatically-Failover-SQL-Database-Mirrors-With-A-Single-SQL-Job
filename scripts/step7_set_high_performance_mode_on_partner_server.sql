use master;
set nocount on
 
if not exists(select value from master.sys.configurations where name = 'show advanced options')
    begin
        exec master..sp_configure 'show advanced options', 1; reconfigure with override
    end
 
if not exists(select value from master.sys.configurations where name = 'xp_cmdshell')
    begin
        exec master..sp_configure 'xp_cmdshell', 1; reconfigure with override
    end
 
-- confirm all servers failed over (only mirrors should exist on this local server at this stage) thus the partner server is the Principal where the HIGH PERFORMANCE mode should be set.
-- this was confirmed by the former step (Confirm Mirror Failover).  If this step was reached; it passed otherwise it would fail before this step.  The 'if exists' is added so this logic block so it
-- could exist outside of this job step flow if necessary.
 
if not exists (select top 1 database_id  from sys.database_mirroring where mirroring_role_desc = 'PRINCIPAL')
    begin
        declare
            @new_principal  varchar(255) 
        ,   @retcode        int
        ,   @job_name   varchar(255)
        ,   @step_name  varchar(255)
        ,   @server_name    varchar(255) 
        ,   @query      varchar(8000) 
        ,   @cmd        varchar(8000)
        set @new_principal  = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
        set @job_name   = 'DATABASE MIRRORS - Failover All Mirrored Databases'
        set     @step_name  = 'Set High Performance'
        set     @server_name    = @new_principal
        set     @query      = 'exec msdb.dbo.sp_start_job @job_name = '''   + @job_name + ''', @step_name = ''' + @step_name + ''''
        set     @cmd        = 'osql -E -S ' + @server_name + ' -Q "'    + @query + '"'
 
        print ' @job_name = '   +isnull(@job_name,      'NULL @job_name') 
        print ' @server_name = '    +isnull(@server_name,   'NULL @server_name') 
        print ' @query = '      +isnull(@query,     'NULL @query') 
        print ' @cmd = '        +isnull(@cmd,       'NULL @cmd')
 
        --exec  @retcode = xp_cmdshell @cmd
 
        if @retcode <> 0 or @retcode is null
            begin
                print 'xp_cmdshell @retcode = '+isnull(convert(varchar(20),@retcode),'NULL @retcode')
            end
    end
