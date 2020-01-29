![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (01 of 10)
**Post Date: 10 29, 2015**

## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process



JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES
Note:  For this process to work; you must have the same Job on both Principal & Mirror Servers.

![Job Steps]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_013.png "All SQL Job Steps")
 
STEP 1:    CONFIRM PRIMARY SERVER
The first step, and perhaps the most important allows you to Failover the Mirrored Databases from any Server (Principal or Mirror).   Whenever you run it.  It detects if there are presently any Principal Databases on the server.  If they exist (even just a single database); it will proceed if to the next step.  If not… It will simply get the Partner server name from the Mirror configuration tables and run the same exact Job starting at Step 2.
Note: The first block of code in every step is the SQL Database Mail configuration. This exists in nearly every step so that each steps process can be run outside of the Job if necessary. This also makes absolute sure that an SQL Database Mail profile does indeed exist, and notifications will be sent out. You'll need to replace the SMTP Server Name, and the MyDomain.com with your companies domain, and finally the @recipients line will need your email address directly (Preferably a distribution group).
Notification Logic:</p>


## SQL-Logic
```SQL
use msdb;
set nocount on
set ansi_nulls on
set quoted_identifier on
 
-- Configure SQL Database Mail if it's not already configured.
if (select top 1 name from msdb..sysmail_profile) is null
    begin
-- Enable SQL Database Mail
        exec master..sp_configure 'show advanced options',1
        reconfigure;
        exec master..sp_configure 'database mail xps',1
        reconfigure;
 
-- Add a profile
        execute msdb.dbo.sysmail_add_profile_sp
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @description        = 'SQLDatabaseMail';
 
-- Add the account names you want to appear in the email message.
        execute msdb.dbo.sysmail_add_account_sp
            @account_name       = 'sqldatabasemail@MyDomain.com'
        ,   @email_address      = 'sqldatabasemail@MyDomain.com'
        ,   @mailserver_name    = 'MySMTPServer.MyDomain.com'  
        --, @port               = ####              --optional
        --, @enable_ssl         = 1                 --optional
        --, @username           ='MySQLDatabaseMailProfile'     --optional
        --, @password           ='MyPassword'           --optional
 
        -- Adding the account to the profile
        execute msdb.dbo.sysmail_add_profileaccount_sp
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @account_name       = 'sqldatabasemail@MyDomain.com'
        ,   @sequence_number    = 1;
 
        -- Give access to new database mail profile (DatabaseMailUserRole)
        execute msdb.dbo.sysmail_add_principalprofile_sp
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @principal_id       = 0
        ,   @is_default     = 1;
 
-- Get Server info for test message
 
        declare @get_basic_server_name              varchar(255)
        declare @get_basic_server_name_and_instance_name    varchar(255)
        declare @basic_test_subject_message         varchar(255)
        declare @basic_test_body_message            varchar(max)
        set @get_basic_server_name              = (select cast(serverproperty('servername') as varchar(255)))
        set @get_basic_server_name_and_instance_name    = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
        set @basic_test_subject_message     = 'Test SMTP email from SQL Server: ' + @get_basic_server_name_and_instance_name
        set @basic_test_body_message        = 'This is a test SMTP email from SQL Server:  ' + @get_basic_server_name_and_instance_name + char(10) + char(10) + 'If you see this.  It''s working perfectly :)'
 
-- Send quick email to confirm email is properly working.
 
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @recipients     = 'SQLJobAlerts@MyDomain.com'
        ,   @subject        = @basic_test_subject_message
        ,   @body           = @basic_test_body_message;
 
        -- Confirm message send
        -- select * from msdb..sysmail_allitems
    end
```


Step 1 Logic


## SQL-Logic
```SQL
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
```
https://mikesdatawork.wordpress.com/2015/10/29/automatically-failover-all-database-mirrors-with-a-single-job-02-of-10/




[![WorksEveryTime](https://forthebadge.com/images/badges/60-percent-of-the-time-works-every-time.svg)](https://shitday.de/)

## Build-Info

| Build Quality | Build History |
|--|--|
|<table><tr><td>[![Build-Status](https://ci.appveyor.com/api/projects/status/pjxh5g91jpbh7t84?svg?style=flat-square)](#)</td></tr><tr><td>[![Coverage](https://coveralls.io/repos/github/tygerbytes/ResourceFitness/badge.svg?style=flat-square)](#)</td></tr><tr><td>[![Nuget](https://img.shields.io/nuget/v/TW.Resfit.Core.svg?style=flat-square)](#)</td></tr></table>|<table><tr><td>[![Build history](https://buildstats.info/appveyor/chart/tygerbytes/resourcefitness)](#)</td></tr></table>|

## Author

[![Gist](https://img.shields.io/badge/Gist-MikesDataWork-<COLOR>.svg)](https://gist.github.com/mikesdatawork)
[![Twitter](https://img.shields.io/badge/Twitter-MikesDataWork-<COLOR>.svg)](https://twitter.com/mikesdatawork)
[![Wordpress](https://img.shields.io/badge/Wordpress-MikesDataWork-<COLOR>.svg)](https://mikesdatawork.wordpress.com/)

    
## License
[![LicenseCCSA](https://img.shields.io/badge/License-CreativeCommonsSA-<COLOR>.svg)](https://creativecommons.org/share-your-work/licensing-types-examples/)

![Mikes Data Work](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_02.png "Mikes Data Work")

