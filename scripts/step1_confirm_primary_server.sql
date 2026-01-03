use master;
set nocount on
 
-- confirm principal and mirror servers
declare
    @confirm_mirror_server  varchar(255) = ( select @@servername )
,   @confirm_principal_server   varchar(255) = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
,   @instance       varchar(255) = ( select top 1 mirroring_partner_instance from master.sys.database_mirroring where mirroring_guid is not null )
,   @witness        varchar(255) = ( select top 1 case mirroring_witness_name when '' then 'None configured' end from master.sys.database_mirroring where mirroring_guid is not null )
 
-- create confirmation email message
 
declare
    @confirm_server_message_subject varchar(max) = 'You are attempting to run the Mirror Failover Process from the Secondary Server: ' + @confirm_mirror_server + '.  The Failover process is typically run from the Primary Server"' + @confirm_principal_server
,   @confirm_server_message_body    varchar(max) = 'You are attempting to run the Mirror Failover Process from the Secondary Server: ' + @confirm_mirror_server + '.  There are presently no Principal Databases on this Server.  This Job will now cancel on this local server, and execute the Failover process instead from the Primary Server ' + @confirm_principal_server + '. A notification will be sent out automatically from the Primary server when the process begins.'
 
if not exists (select top 1 database_id  from sys.database_mirroring where mirroring_role_desc = 'PRINCIPAL')
    begin
        exec msdb.dbo.sp_send_dbmail
            @profile_name   = 'SQLDatabaseMailProfile'
        ,   @recipients = 'SQLJobAlerts@MyDomain.com'
        ,   @subject    = @confirm_server_message_subject
        ,   @body       = @confirm_server_message_body
 
        waitfor delay '00:00:5';
         
        if not exists(select value from master.sys.configurations where name = 'show advanced options')
            begin
                exec master..sp_configure 'show advanced options', 1; reconfigure with override
            end
 
        if not exists(select value from master.sys.configurations where name = 'xp_cmdshell')
            begin
                exec master..sp_configure 'xp_cmdshell', 1; reconfigure with override
            end
 
        declare
            @retcode        int
        ,   @job_name   varchar(255)
        ,   @step_name  varchar(255)
        ,   @server_name    varchar(255)
        ,   @query      varchar(8000) 
        ,   @cmd        varchar(8000)
        set @job_name   = 'DATABASE MIRRORS - Failover All Mirrored Databases'
        set @step_name      = 'Start Mirror Failover Process'
        set @server_name    = @confirm_principal_server
        set @query      = 'exec msdb.dbo.sp_start_job @job_name = '''   + @job_name + ''', @step_name = ''' + @step_name + ''''
        set @cmd        = 'osql -E -S ' + @server_name + ' -Q "'        + @query + '"'
 
        print ' @job_name = '   +isnull(@job_name,      'NULL @job_name') 
        print ' @server_name = '    +isnull(@server_name,   'NULL @server_name') 
        print ' @query = '      +isnull(@query,     'NULL @query') 
        print ' @cmd = '        +isnull(@cmd,       'NULL @cmd')
 
        exec    @retcode = xp_cmdshell @cmd
 
        if @retcode <> 0 or @retcode is null
            begin
                print 'xp_cmdshell @retcode = '+isnull(convert(varchar(20),@retcode),'NULL @retcode')
            end
 
        raiserror('50005 Mirror Failover Warning.  Mirror Database Failover was initiated from the Mirror Server.  Process will instead be executed on the Primary Server', 16, -1, @@servername )
    end
