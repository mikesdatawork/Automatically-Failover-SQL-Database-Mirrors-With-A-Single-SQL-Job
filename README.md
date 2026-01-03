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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")

# Automatically Failover SQL Database Mirrors With A Single Job (02 of 10)
**Post Date: October 29, 2015**





## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process


JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES
 
STEP 2:  START MIRROR FAILOVER PROCESS</p>      


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
        --, @port           = ####          --optional
        --, @enable_ssl     = 1         --optional
        --, @username       ='MySQLDatabaseMailProfile' --optional
        --, @password       ='MyPassword'       --optional
 
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
 
        declare @get_basic_server_name                      varchar(255) = (select cast(serverproperty('servername') as varchar(255)))
        declare @get_basic_server_name_and_instance_name    varchar(255) set @get_basic_server_name_and_instance_name = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
        declare @basic_test_subject_message                 varchar(255) set @basic_test_subject_message = 'Test SMTP email from SQL Server: ' + @get_basic_server_name_and_instance_name
        declare @basic_test_body_message                    varchar(max) = 'This is a test SMTP email from SQL Server:  ' + @get_basic_server_name_and_instance_name + char(10) + char(10) + 'If you see this.  It''s working perfectly :)'
 
        -- Send quick email to confirm email is properly working.
 
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name   = 'SQLDatabaseMailProfile'
        ,   @recipients     = 'SQLJobAlerts@MyDomain.com'
        ,   @subject        = @basic_test_subject_message
        ,   @body           = @basic_test_body_message;
 
        -- Confirm message send
        -- select * from msdb..sysmail_allitems
    end
 
use master;
set nocount on
-- get basic server info.
 
declare
    @server_name_basic      varchar(255) = (select cast(serverproperty('servername') as varchar(255)))
,   @server_name_instance_name  varchar(255) = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
 
-- get basic server mirror role info.
 
declare
    @primary    varchar(255) = ( select @@servername )
,   @secondary  varchar(255) = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
,   @instance   varchar(255) = ( select top 1 mirroring_partner_instance from master.sys.database_mirroring where mirroring_guid is not null )
,   @witness    varchar(255) = ( select top 1 case mirroring_witness_name when '' then 'None configured' end from master.sys.database_mirroring where mirroring_guid is not null )
 
-- set message subject.
declare @message_subject        varchar(255)
set @message_subject        = 'Mirror Failover Process (1 of 2) has started on Server: ' + @server_name_instance_name
 
-- create table for mirrored databases
if object_id('tempdb..#mirrored_databases') is not null
    drop table #mirrored_databases
 
create table #mirrored_databases
    (
        [current_server]varchar(255)
    ,   [database]  varchar(255)
    ,   [current_state] varchar(255)
    ,   [process]   varchar(255)
    )
 
-- populate table for mirrored databases
insert into #mirrored_databases
select
    'current_server'    = @primary
,   'database'      = upper(DB_NAME(database_id))
,   'current_state'     = mirroring_state_desc
,   'process'       = 'Failing over to Server: ' + @secondary
from
    sys.database_mirroring
where
    mirroring_guid is not null
order by
    db_name(database_id) asc
-- create conditions for html tables in top and mid sections of email.
 
declare @xml_top            NVARCHAR(MAX)
declare @xml_mid            NVARCHAR(MAX)
declare @body_top           NVARCHAR(MAX)
declare @body_mid           NVARCHAR(MAX)
 
-- set xml top table td's
-- create html table object for: #check_mirror_latency
 
set @xml_top = 
    cast(
        (select
            [current_server]as 'td'
        ,   ''
        ,   [database]  as 'td'
        ,   ''
        ,   [current_state] as 'td'
        ,   ''
        ,   [process]   as 'td'
        ,   ''
 
        from  #mirrored_databases
        order by [database] asc
        for xml path('tr')
        ,   elements)
        as NVARCHAR(MAX)
        )
 
-- set xml mid table td's
-- create html table object for: #extra_table_formatting_if_needed
/*
set @xml_mid = 
    cast(
        (select 
            [Column1]   as 'td'
        ,   ''
        ,   [Column2]   as 'td'
        ,   ''
        ,   [Column3]   as 'td'
        ,   ''
        ,   [...]   as 'td'
 
        from  #get_last_known_backups 
        order by [database], [time_of_backup] desc 
        for xml path('tr')
    ,   elements)
    as NVARCHAR(MAX)
        )
*/
-- format email
set @body_top =
        '<html>
        <head>
 
<style>
                    h1{
                        font-family: sans-serif;
                        font-size: 87%;
                    }
                    h3{
                        font-family: sans-serif;
                        color: black;
                    }
 
                    table, td, tr, th {
                        font-family: sans-serif;
                        font-size: 87%;
                        border: 1px solid black;
                        border-collapse: collapse;
                    }
                    th {
                        text-align: left;
                        background-color: gray;
                        color: white;
                        padding: 5px;
                        font-size: 87%;
                    }
 
                    td {
                        padding: 5px;
                    }
            </style>
 
        </head>
        <body>
 
<h1>' + @message_subject + '</h1>
 
 
<h1>
 
 
        The database Mirror Failover Process has started on Server:  <font color="blue">' + @primary      + '.  </font> The following databases will failover to the secondary Server:  <font color="blue">' + @secondary     +
                        case
                            when @secondary <> @instance then @secondary + '\' + @instance
                            else ''
                        end + '             </font>
         
 
        </h1>
 
          
 
<h1></h1>
 
 
<table border = 1>
 
<tr>
 
<th> Server       </th>
 
 
<th> Database     </th>
 
 
<th> Current State    </th>
 
 
<th> Process      </th>
 
        </tr>
 
'
 
set @body_top = @body_top + @xml_top +
/* '</table>
 
 
<h1>Mid Table Title Here</h1>
 
 
<table border = 1>
 
<tr>
 
<th> Column1 Here </th>
 
 
<th> Column2 Here </th>
 
 
<th> Column3 Here </th>
 
 
<th> ...          </th>
 
        </tr>
 
'       
+ @xml_mid */ 
'</table>
 
 
<h1>This process is driven by the Job ( DATABASE MIRRORS - Failover All Mirrored Databases )</h1>
 
 
<h1>Go to the server using Start-Run, or (Win + R) and type in: mstsc -v:' + @server_name_basic + '</h1>
 
'
+ '</body></html>'
-- send email.
 
exec msdb.dbo.sp_send_dbmail
    @profile_name       = 'SQLDatabaseMailProfile'
,   @recipients     = 'SQLJobAlerts@MyDomain.com'
,   @subject        = @message_subject
,   @body           = @body_top
 
drop table #mirrored_databases
```

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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (03 of 10)
**Post Date: October 29, 2015**


## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process

<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES

![Set Full Safety]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_03.png "Set Mirrored Safety")
 
STEP 3:  SET FULL SAFETY ON ALL MIRRORED DATABASES (REQUIRED BEFORE FAILOVER)

Step logic:</p>      


## SQL-Logic
```SQL
 
use master;
set nocount on
 
declare
    @set_full_safety_on_mirror_databases    varchar(max) = ''
select
    @set_full_safety_on_mirror_databases    = @set_full_safety_on_mirror_databases + 
'alter database [' + cast(DB_NAME(database_id) as varchar(255)) + '] set safety full;'  + char(10)
from
    sys.database_mirroring
where
    mirroring_guid is not null
    and mirroring_role_desc = 'PRINCIPAL'
 
exec (@set_full_safety_on_mirror_databases)
```

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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (04 of 10)
**Post Date: October 29, 2015**





## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process

<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Confirm Full Safety]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_04.png "Step 4")
 
STEP 4:  CONFIRM SAFETYS
Step logic:



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
        --, @port           = ####          --optional
        --, @enable_ssl     = 1         --optional
        --, @username       ='MySQLDatabaseMailProfile' --optional
        --, @password       ='MyPassword'       --optional
 
        -- Adding the account to the profile
        execute msdb.dbo.sysmail_add_profileaccount_sp
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @account_name       = 'sqldatabasemail@MyDomain.com'
        ,   @sequence_number    = 1;
 
        -- Give access to new database mail profile (DatabaseMailUserRole)
        execute msdb.dbo.sysmail_add_principalprofile_sp
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @principal_id       = 0
        ,   @is_default         = 1;
 
       -- Get Server info for test message
 
        declare @get_basic_server_name          varchar(255)
        declare @get_basic_server_name_and_instance_name    varchar(255)
        declare @basic_test_subject_message     varchar(255)
        declare @basic_test_body_message        varchar(max)
        set @get_basic_server_name          = (select cast(serverproperty('servername') as varchar(255)))
        set @get_basic_server_name_and_instance_name    = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
        set @basic_test_subject_message     = 'Test SMTP email from SQL Server: ' + @get_basic_server_name_and_instance_name
        set @basic_test_body_message        = 'This is a test SMTP email from SQL Server:  ' + @get_basic_server_name_and_instance_name + char(10) + char(10) + 'If you see this.  It''s working perfectly :)'
 
        -- Send quick email to confirm email is properly working.
 
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name   = 'SQLDatabaseMailProfile'
        ,   @recipients = 'SQLJobAlerts@MyDomain.com'
        ,   @subject    = @basic_test_subject_message
        ,   @body       = @basic_test_body_message;
 
        -- Confirm message send
        -- select * from msdb..sysmail_allitems
    end
 
use master;
set nocount on
-- get basic server info.
 
declare @server_name_basic      varchar(255)
declare @server_name_instance_name  varchar(255)
set @server_name_basic      = (select cast(serverproperty('servername') as varchar(255)))
set @server_name_instance_name  = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
 
-- get basic server mirror role info.
 
declare
    @primary    varchar(255) = ( select @@servername )
,   @secondary  varchar(255) = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
,   @instance   varchar(255) = ( select top 1 mirroring_partner_instance from master.sys.database_mirroring where mirroring_guid is not null )
,   @witness    varchar(255) = ( select top 1 case mirroring_witness_name when '' then 'None configured' end from master.sys.database_mirroring where mirroring_guid is not null )
 
-- set message subject.
declare @message_subject        varchar(255)
set @message_subject        = 'Failover error found on Server:  ' + @server_name_instance_name + '  - Not all mirrored databases were set to full safety prior to failover.'
 
-- create table to hold mirror operating modes
 
if object_id('tempdb..#mirror_operating_modes') is not null
    drop table #mirror_operating_modes
 
create table #mirror_operating_modes
    (
    [server]        varchar(255)
,   [database]      varchar(255)
,   [synchronous_mode]  varchar(255)
)
 
-- populate table #mirror_operating_modes
 
insert into #mirror_operating_modes
select
    [server]        = @@servername
,   [database]      = upper(db_name(sdm.database_id))
,   [synchronous_mode]  = case sdm.mirroring_safety_level_desc
                            when 'full' then 'SYNCHRONOUS   - HIGH SAFETY'
                            when 'off'  then 'ASYNCHRONOUS  - HIGH PERFORMANCE'
                        else 'Not Mirrored'
                    end
from
    master.sys.database_mirroring sdm
where
    db_name(sdm.database_id) not in ('tempdb')
    and sdm.mirroring_safety_level_desc = 'off'
order by
    @@servername, [database] asc
 
 
-- create conditions for html tables in top and mid sections of email.
 
declare @xml_top            NVARCHAR(MAX)
declare @xml_mid            NVARCHAR(MAX)
declare @body_top           NVARCHAR(MAX)
declare @body_mid           NVARCHAR(MAX)
 
-- set xml top table td's
-- create html table object for: #check_mirror_latency
 
set @xml_top = 
    cast(
        (select
            [server]        as 'td'
        ,   ''
        ,   [database]      as 'td'
        ,   ''
        ,   [synchronous_mode]  as 'td'
        ,   ''
 
        from  #mirror_operating_modes
        order by [server], [database] asc
        for xml path('tr')
        ,   elements)
        as NVARCHAR(MAX)
        )
 
-- set xml mid table td's
-- create html table object for: #extra_table_formatting_if_needed
/*
set @xml_mid = 
    cast(
        (select 
            [Column1]   as 'td'
        ,   ''
        ,   [Column2]   as 'td'
        ,   ''
        ,   [Column3]   as 'td'
        ,   ''
        ,   [...]   as 'td'
 
        from  #get_last_known_backups 
        order by [database], [time_of_backup] desc 
        for xml path('tr')
    ,   elements)
    as NVARCHAR(MAX)
        )
*/
-- format email
set @body_top =
        '<html>
        <head>
 
<style>
                    h1{
                        font-family: sans-serif;
                        font-size: 87%;
                    }
                    h3{
                        font-family: sans-serif;
                        color: black;
                    }
 
                    table, td, tr, th {
                        font-family: sans-serif;
                        font-size: 87%;
                        border: 1px solid black;
                        border-collapse: collapse;
                    }
                    th {
                        text-align: left;
                        background-color: gray;
                        color: white;
                        padding: 5px;
                        font-size: 87%;
                    }
 
                    td {
                        padding: 5px;
                    }
            </style>
 
        </head>
        <body>
 
<H3>' + @message_subject + '</H3>
 
 
 
<h1>
        A Failover error occurred before the databases could be failed over from the Primary Server:  <font color="blue">'    + @primary      + ' </font> 
        to the Secondary Server: <font color="blue">' + @secondary        +
                        case
                            when @secondary <> @instance then @secondary + '\' + @instance
                            else ''
                        end + '             </font>
                 
        Not all the Mirrored Datatabases could be set to Full Safety.  Full safetys are required before failover.  Please check the databases and ensure all are set to full safety before the failover process can proceed to the next step.
        </h1>
 
          
 
<h1>Current Safety Modes              </h1>
 
 
<h1>Full Safety Off = (ASYNCHRONOUS - HIGH PERFORMANCE)   </h1>
 
 
<h1>Full Safety On  = (SYNCHRONOUS    - HIGH SAFETY)  </h1>
 
 
<table border = 1>
 
<tr>
 
<th> Server       </th>
 
 
<th> Database     </th>
 
 
<th> Synchronous Mode </th>
 
        </tr>
 
'
 
set @body_top = @body_top + @xml_top +
/* '</table>
 
 
<h1>Mid Table Title Here</h1>
 
 
<table border = 1>
 
<tr>
 
<th> Column1 Here </th>
 
 
<th> Column2 Here </th>
 
 
<th> Column3 Here </th>
 
 
<th> ...      </th>
 
        </tr>
 
'       
+ @xml_mid */ 
'</table>
 
 
<h1>Go to the server using Start-Run, or (Win + R) and type in: mstsc -v:' + @server_name_basic + '</h1>
 
'
+ '</body></html>'
 
-- send email.
 
if exists(select top 1 * from #mirror_operating_modes)
    begin
        exec msdb.dbo.sp_send_dbmail
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @recipients     = 'SQLJobAlerts@MyDomain.com'
        ,   @subject        = @message_subject
        ,   @body           = @body_top
        ,   @body_format        = 'HTML';
         
        drop table #mirror_operating_modes
        raiserror('50005 Mirror Failover Error.  Not all Mirrored Databases were set to Full Safety', 16, -1, @@servername )
    end
```


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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (05 of 10)
**Post Date: October 29, 2015**





## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process

<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Failover Mirror Databases]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_05.png "Step 5")
 
STEP 5:  FAILOVER ALL MIRRORED DATABASES
Step logic:     



## SQL-Logic
```SQL
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
```


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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (06 of 10)
**Post Date: October 29, 2015**

## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process


<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Confirm Mirror Database Failover]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_06.png "Step 6")
 
STEP 6:  CONFIRM MIRROR DATABASE FAILOVER
Step logic:

      
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
        --, @port           = ####          --optional
        --, @enable_ssl     = 1         --optional
        --, @username       ='MySQLDatabaseMailProfile' --optional
        --, @password       ='MyPassword'       --optional
 
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
 
        declare @get_basic_server_name          varchar(255)
        declare @get_basic_server_name_and_instance_name    varchar(255)
        declare @basic_test_subject_message     varchar(255)
        declare @basic_test_body_message        varchar(max)
        set @get_basic_server_name          = (select cast(serverproperty('servername') as varchar(255)))
        set @get_basic_server_name_and_instance_name    = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
        set @basic_test_subject_message     = 'Test SMTP email from SQL Server: ' + @get_basic_server_name_and_instance_name
        set @basic_test_body_message        = 'This is a test SMTP email from SQL Server:  ' + @get_basic_server_name_and_instance_name + char(10) + char(10) + 'If you see this.  It''s working perfectly :)'
 
       -- Send quick email to confirm email is properly working.
 
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name   = 'SQLDatabaseMailProfile'
        ,   @recipients = 'SQLJobAlerts@MyDomain.com'
        ,   @subject    = @basic_test_subject_message
        ,   @body       = @basic_test_body_message;
 
        -- Confirm message send
        -- select * from msdb..sysmail_allitems
    end
 
use master;
set nocount on
-- get basic server info.
 
declare @server_name_basic      varchar(255)
declare @server_name_instance_name  varchar(255)
set @server_name_basic      = (select cast(serverproperty('servername') as varchar(255)))
set @server_name_instance_name  = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
 
-- get basic server mirror role info.
 
declare
    @primary    varchar(255) = ( select @@servername )
,   @secondary  varchar(255) = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
,   @instance   varchar(255) = ( select top 1 mirroring_partner_instance from master.sys.database_mirroring where mirroring_guid is not null )
,   @witness    varchar(255) = ( select top 1 case mirroring_witness_name when '' then 'None configured' end from master.sys.database_mirroring where mirroring_guid is not null )
 
-- set message subject.
declare @message_subject    varchar(255)
set @message_subject    = 'Failover error found on Server:  ' + @server_name_instance_name + '  - Not all databases were properly failed over.'
 
-- create table to hold confirm failover
 
if object_id('tempdb..#confirm_mirror_failover') is not null
    drop table #confirm_mirror_failover
 
create table #confirm_mirror_failover
    (
        [server_name]       varchar(255)
    ,   [database]      varchar(255)
    ,   [mirror_state]      varchar(255)
    ,   [mirror_role]       varchar(255)
    ,   [mirror_partner_name]   varchar(255)
    )
 
-- populate table to hold confirm failover
insert into #confirm_mirror_failover
select
    upper(@@servername)
,   upper(DB_NAME(database_id))
,   mirroring_state_desc
,   mirroring_role_desc
,   mirroring_partner_name
from
    sys.database_mirroring
where
    mirroring_guid is not null
    and mirroring_role_desc in ('PRINCIPAL', 'DISCONNECTED', 'SUSPENDED')
 
-- create conditions for html tables in top and mid sections of email.
 
declare @xml_top            NVARCHAR(MAX)
declare @xml_mid            NVARCHAR(MAX)
declare @body_top           NVARCHAR(MAX)
declare @body_mid           NVARCHAR(MAX)
 
-- set xml top table td's
-- create html table object for: #check_mirror_latency
 
set @xml_top = 
    cast(
        (select
            [server_name]       as 'td'
        ,   ''
        ,   [database]      as 'td'
        ,   ''
        ,   [mirror_state]      as 'td'
        ,   ''
        ,   [mirror_role]       as 'td'
        ,   ''
        ,   [mirror_partner_name]   as 'td'
        ,   ''
 
        from  #confirm_mirror_failover
        order by [database], [mirror_role] asc
        for xml path('tr')
        ,   elements)
        as NVARCHAR(MAX)
        )
 
-- set xml mid table td's
-- create html table object for: #extra_table_formatting_if_needed
/*
set @xml_mid = 
    cast(
        (select 
            [Column1]as 'td'
        ,   ''
        ,   [Column2]as 'td'
        ,   ''
        ,   [Column3]as 'td'
        ,   ''
        ,   [...]   as 'td'
 
        from  #get_last_known_backups 
        order by [database], [time_of_backup] desc 
        for xml path('tr')
    ,   elements)
    as NVARCHAR(MAX)
        )
*/
-- format email
set @body_top =
        '<html>
        <head>
 
<style>
                    h1{
                        font-family: sans-serif;
                        font-size: 87%;
                    }
                    h3{
                        font-family: sans-serif;
                        color: black;
                    }
 
                    table, td, tr, th {
                        font-family: sans-serif;
                        font-size: 87%;
                        border: 1px solid black;
                        border-collapse: collapse;
                    }
                    th {
                        text-align: left;
                        background-color: gray;
                        color: white;
                        padding: 5px;
                        font-size: 87%;
                    }
 
                    td {
                        padding: 5px;
                    }
            </style>
 
        </head>
        <body>
 
<H3>' + @message_subject + '</H3>
 
 
 
<h1>
        A Failover error occurred while failing over from the Primary Server:  <font color="blue">'   + @primary      + ' </font> 
        to the Secondary Server: <font color="blue">' + @secondary        +
                        case
                            when @secondary <> @instance then @secondary + '\' + @instance
                            else ''
                        end + '             </font>
                 
        Not all the Mirrored Datatabases failed over.  Please check the databases on the server, and resolve before proceeding to the next step.
        </h1>
 
          
 
<h1>The following databases did not failover properly.</h1>
 
 
<table border = 1>
 
<tr>
 
<th> Server Name  </th>
 
 
<th> Database     </th>
 
 
<th> Mirror State </th>
 
 
<th> Mirror Role  </th>
 
 
<th> Mirror Partner Name</th>
 
        </tr>
 
'
 
set @body_top = @body_top + @xml_top +
/* '</table>
 
 
<h1>Mid Table Title Here</h1>
 
 
<table border = 1>
 
<tr>
 
<th> Column1 Here </th>
 
 
<th> Column2 Here </th>
 
 
<th> Column3 Here </th>
 
 
<th> ...      </th>
 
        </tr>
 
'       
+ @xml_mid */ 
'</table>
 
 
<h1>Go to the server using Start-Run, or (Win + R) and type in: mstsc -v:' + @server_name_basic + '</h1>
 
'
+ '</body></html>'
 
-- send email.
 
if exists(select top 1 * from #confirm_mirror_failover)
    begin
        exec msdb.dbo.sp_send_dbmail
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @recipients     = 'SQLJobAlerts@MyDomain.com'
        ,   @subject        = @message_subject
        ,   @body           = @body_top
        ,   @body_format        = 'HTML';
         
        drop table #confirm_mirror_failover
        raiserror('50005 Mirror Failover Error.  Not all Mirrored Databases were properly failed over.', 16, -1, @@servername )
    end
```

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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (07 of 10)
**Post Date: October 29, 2015**





## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process



<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Set Performance Mode]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_07.png "Step 7")
 
STEP 7:  SET HIGH PERFORMANCE MODE ON PARTNER SERVER
It's important to note that the Step actions ( On Success & On Failure ) should go as follows for this this step.
The steps following 7 are to be run independantly so they cannot (and should not) run after Step 7 has completed. These steps are initiated by the same Job on the Partner Server and vice versa.

![Set Precedence Action]( https://mikesdatawork.files.wordpress.com/2015/10/quit_on_success_for_step_7.png "Step 7")
 
Step logic:



## SQL-Logic
```SQL
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
```



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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        # Automatically Failover SQL Database Mirrors With A Single Job (08 of 10)
**Post Date: October 29, 2015**




## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process



<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Set Performance]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_08.png "Step 8")
 
STEP 8:  SET HIGH PERFORMANCE
Step logic:



## SQL-Logic
```SQL
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
```


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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Failover SQL Database Mirrors With A Single Job (09 of 10)
**Post Date: October 29, 2015**        

## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process


<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Confirm High Performance]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_09.png "Step 9")
 
STEP 9:  CONFIRM HIGH PERFORMANCE
Step logic:



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
        --, @port           = ####          --optional
        --, @enable_ssl     = 1         --optional
        --, @username       ='MySQLDatabaseMailProfile' --optional
        --, @password       ='MyPassword'       --optional
 
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
 
        declare @get_basic_server_name          varchar(255)
        declare @get_basic_server_name_and_instance_name    varchar(255)
        declare @basic_test_subject_message     varchar(255)
        declare @basic_test_body_message            varchar(max)
        set @get_basic_server_name          = (select cast(serverproperty('servername') as varchar(255)))
        set @get_basic_server_name_and_instance_name    = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
        set @basic_test_subject_message     = 'Test SMTP email from SQL Server: ' + @get_basic_server_name_and_instance_name
        set @basic_test_body_message            = 'This is a test SMTP email from SQL Server:  ' + @get_basic_server_name_and_instance_name + char(10) + char(10) + 'If you see this.  It''s working perfectly :)'
 
       -- Send quick email to confirm email is properly working.
 
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name   = 'SQLDatabaseMailProfile'
        ,   @recipients = 'SQLJobAlerts@MyDomain.com'
        ,   @subject    = @basic_test_subject_message
        ,   @body       = @basic_test_body_message;
 
        -- Confirm message send
        -- select * from msdb..sysmail_allitems
    end
 
use master;
set nocount on
-- get basic server info.
 
declare @server_name_basic          varchar(255)
declare @server_name_instance_name      varchar(255)
set     @server_name_basic      = (select cast(serverproperty('servername') as varchar(255)))
set     @server_name_instance_name  = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
 
-- get basic server mirror role info.
 
declare
    @primary    varchar(255) = ( select @@servername )
,   @secondary  varchar(255) = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
,   @instance   varchar(255) = ( select top 1 mirroring_partner_instance from master.sys.database_mirroring where mirroring_guid is not null )
,   @witness    varchar(255) = ( select top 1 case mirroring_witness_name when '' then 'None configured' end from master.sys.database_mirroring where mirroring_guid is not null )
 
-- set message subject.
declare @message_subject    varchar(255)
set @message_subject    = 'Failover error found on Server:  ' + @server_name_instance_name + '  - Not all mirrored databases were set to full safety prior to failover.'
 
-- create table to hold mirror operating modes
 
if object_id('tempdb..#mirror_operating_modes') is not null
    drop table #mirror_operating_modes
 
create table #mirror_operating_modes
    (
    [server]        varchar(255)
,   [database]      varchar(255)
,   [synchronous_mode]  varchar(255)
)
 
-- populate table #mirror_operating_modes
 
insert into #mirror_operating_modes
select
    [server]        = @@servername
,   [database]      = upper(db_name(sdm.database_id))
,   [synchronous_mode]  = case sdm.mirroring_safety_level_desc
                            when 'full' then 'SYNCHRONOUS   - HIGH SAFETY'
                            when 'off'  then 'ASYNCHRONOUS  - HIGH PERFORMANCE'
                            else 'Not Mirrored'
                          end
from
    master.sys.database_mirroring sdm
where
    db_name(sdm.database_id) not in ('tempdb')
    and sdm.mirroring_safety_level_desc = 'full'
order by
    @@servername, [database] asc
 
 
-- create conditions for html tables in top and mid sections of email.
 
declare @xml_top            NVARCHAR(MAX)
declare @xml_mid            NVARCHAR(MAX)
declare @body_top           NVARCHAR(MAX)
declare @body_mid           NVARCHAR(MAX)
 
-- set xml top table td's
-- create html table object for: #check_mirror_latency
 
set @xml_top = 
    cast(
        (select
            [server]        as 'td'
        ,   ''
        ,   [database]      as 'td'
        ,   ''
        ,   [synchronous_mode]  as 'td'
        ,   ''
 
        from  #mirror_operating_modes
        order by [server], [database] asc
        for xml path('tr')
        ,   elements)
        as NVARCHAR(MAX)
        )
 
-- set xml mid table td's
-- create html table object for: #extra_table_formatting_if_needed
/*
set @xml_mid = 
    cast(
        (select 
            [Column1]   as 'td'
        ,   ''
        ,   [Column2]   as 'td'
        ,   ''
        ,   [Column3]       as 'td'
        ,   ''
        ,   [...]   as 'td'
 
        from  #get_last_known_backups 
        order by [database], [time_of_backup] desc 
        for xml path('tr')
    ,   elements)
    as NVARCHAR(MAX)
        )
*/
-- format email
set @body_top =
        '<html>
        <head>
 
<style>
                    h1{
                        font-family: sans-serif;
                        font-size: 87%;
                    }
                    h3{
                        font-family: sans-serif;
                        color: black;
                    }
 
                    table, td, tr, th {
                        font-family: sans-serif;
                        font-size: 87%;
                        border: 1px solid black;
                        border-collapse: collapse;
                    }
                    th {
                        text-align: left;
                        background-color: gray;
                        color: white;
                        padding: 5px;
                        font-size: 87%;
                    }
 
                    td {
                        padding: 5px;
                    }
            </style>
 
        </head>
        <body>
 
<H3>' + @message_subject + '</H3>
 
 
 
<h1>
        A Failover error occurred before the databases could be failed over from the Primary Server:  <font color="blue">'    + @primary      + ' </font> 
        to the Secondary Server: <font color="blue">' + @secondary        +
                        case
                            when @secondary <> @instance then @secondary + '\' + @instance
                            else ''
                        end + '             </font>
                 
        Not all the Mirrored Datatabases could be set to Full Safety.  Full safetys are required before failover.  Please check the databases and ensure all are set to full safety before the failover process can proceed to the next step.
        </h1>
 
          
 
<h1>Current Safety Modes</h1>
 
 
<h1>Full Safety Off = (ASYNCHRONOUS - HIGH PERFORMANCE)   </h1>
 
 
<h1>Full Safety On  = (SYNCHRONOUS    - HIGH SAFETY)  </h1>
 
 
<table border = 1>
 
<tr>
 
<th> Server       </th>
 
 
<th> Database     </th>
 
 
<th> Synchronous Mode </th>
 
        </tr>
 
'
 
set @body_top = @body_top + @xml_top +
/* '</table>
 
 
<h1>Mid Table Title Here</h1>
 
 
<table border = 1>
 
<tr>
 
<th> Column1 Here </th>
 
 
<th> Column2 Here </th>
 
 
<th> Column3 Here </th>
 
 
<th> ...      </th>
 
        </tr>
 
'       
+ @xml_mid */ 
'</table>
 
 
<h1>Go to the server using Start-Run, or (Win + R) and type in: mstsc -v:' + @server_name_basic + '</h1>
 
'
+ '</body></html>'
 
-- send email.
 
if exists(select top 1 * from #mirror_operating_modes)
    begin
        exec msdb.dbo.sp_send_dbmail
            @profile_name       = 'SQLDatabaseMailProfile'
        ,   @recipients     = 'SQLJobAlerts@MyDomain.com'
        ,   @subject        = @message_subject
        ,   @body           = @body_top
        ,   @body_format        = 'HTML';
         
        drop table #mirror_operating_modes
        raiserror('50005 Mirror Failover Error.  Not all Mirrored Databases were set to High Performance', 16, -1, @@servername )
    end
```

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

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        # Automatically Failover SQL Database Mirrors With A Single Job (10 of 10)
**Post Date: October 29, 2015**




## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process

<p>JOB:  DATABASE MIRRORS – FAILOVER ALL MIRRORED DATABASES</p>

![Finish Mirror Failover]( https://mikesdatawork.files.wordpress.com/2015/10/screenshot_10.png "Step 10")
 
STEP 10:  FINISH MIRROR FAILOVER PROCESS
Step logic:



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
        --, @port           = ####      --optional
        --, @enable_ssl     = 1     --optional
        --, @username       ='MySQLDatabaseMailProfile' --optional
        --, @password       ='MyPassword'   --optional
 
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
 
        declare @get_basic_server_name      varchar(255) = (select cast(serverproperty('servername') as varchar(255)))
        declare @get_basic_server_name_and_instance_name    varchar(255) set @get_basic_server_name_and_instance_name = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
        declare @basic_test_subject_message     varchar(255) set @basic_test_subject_message = 'Test SMTP email from SQL Server: ' + @get_basic_server_name_and_instance_name
        declare @basic_test_body_message        varchar(max) = 'This is a test SMTP email from SQL Server:  ' + @get_basic_server_name_and_instance_name + char(10) + char(10) + 'If you see this.  It''s working perfectly :)'
 
      -- Send quick email to confirm email is properly working.
 
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name   = 'SQLDatabaseMailProfile'
        ,   @recipients = 'SQLJobAlerts@MyDomain.com'
        ,   @subject    = @basic_test_subject_message
        ,   @body       = @basic_test_body_message;
 
        -- Confirm message send
        -- select * from msdb..sysmail_allitems
    end
 
use master;
set nocount on
-- get basic server info.
 
declare
    @server_name_basic      varchar(255) = (select cast(serverproperty('servername') as varchar(255)))
,   @server_name_instance_name  varchar(255) = (select  replace(cast(serverproperty('servername') as varchar(255)), '\', '   SQL Instance: '))
 
-- get basic server mirror role info.
 
declare
    @primary    varchar(255) = ( select @@servername )
,   @secondary  varchar(255) = ( select top 1 replace(left(mirroring_partner_name, charindex('.', mirroring_partner_name) - 1), 'TCP://', '') from master.sys.database_mirroring where mirroring_guid is not null )
,   @instance   varchar(255) = ( select top 1 mirroring_partner_instance from master.sys.database_mirroring where mirroring_guid is not null )
,   @witness    varchar(255) = ( select top 1 case mirroring_witness_name when '' then 'None configured' end from master.sys.database_mirroring where mirroring_guid is not null )
 
-- set message subject.
declare @message_subject        varchar(255)
set @message_subject        = 'Mirror Failover Process (2 of 2) has completed.  Failover was successful to Server: ' + @server_name_instance_name
 
-- create table for mirrored databases
if object_id('tempdb..#mirrored_databases') is not null
    drop table #mirrored_databases
 
create table #mirrored_databases
    (
        [current_server]    varchar(255)
    ,   [database]  varchar(255)
    ,   [current_state] varchar(255)
    ,   [partner_name]  varchar(255)
    )
 
-- populate table for mirrored databases
insert into #mirrored_databases
select
    'current_server'= @primary
,   'database'  = upper(DB_NAME(database_id))
,   'current_state' = mirroring_state_desc
,   'partner_name'  = mirroring_partner_name
from
    sys.database_mirroring
where
    mirroring_guid is not null
order by
    db_name(database_id) asc
 
-- create conditions for html tables in top and mid sections of email.
 
declare @xml_top            NVARCHAR(MAX)
declare @xml_mid            NVARCHAR(MAX)
declare @body_top           NVARCHAR(MAX)
declare @body_mid           NVARCHAR(MAX)
 
-- set xml top table td's
-- create html table object for: #check_mirror_latency
 
set @xml_top = 
    cast(
        (select
            [current_server]as 'td'
        ,   ''
        ,   [database]  as 'td'
        ,   ''
        ,   [current_state] as 'td'
        ,   ''
        ,   [partner_name]  as 'td'
        ,   ''
 
        from  #mirrored_databases
        order by [database] asc
        for xml path('tr')
        ,   elements)
        as NVARCHAR(MAX)
        )
 
-- set xml mid table td's
-- create html table object for: #extra_table_formatting_if_needed
/*
set @xml_mid = 
    cast(
        (select 
            [Column1]   as 'td'
        ,   ''
        ,   [Column2]   as 'td'
        ,   ''
        ,   [Column3]   as 'td'
        ,   ''
        ,   [...]   as 'td'
 
        from  #get_last_known_backups 
        order by [database], [time_of_backup] desc 
        for xml path('tr')
    ,   elements)
    as NVARCHAR(MAX)
        )
*/
-- format email
set @body_top =
        '&amp;lt;html&amp;gt;
        &amp;lt;head&amp;gt;
 
&amp;lt;style&amp;gt;
                    h1{
                        font-family: sans-serif;
                        font-size: 87%;
                    }
                    h3{
                        font-family: sans-serif;
                        color: black;
                    }
 
                    table, td, tr, th {
                        font-family: sans-serif;
                        font-size: 87%;
                        border: 1px solid black;
                        border-collapse: collapse;
                    }
                    th {
                        text-align: left;
                        background-color: gray;
                        color: white;
                        padding: 5px;
                        font-size: 87%;
                    }
 
                    td {
                        padding: 5px;
                    }
            &amp;lt;/style&amp;gt;
 
        &amp;lt;/head&amp;gt;
        &amp;lt;body&amp;gt;
 
&amp;lt;h1&amp;gt;' + @message_subject + '&amp;lt;/h1&amp;gt;
 
 
&amp;lt;h1&amp;gt;
 
 
        The Mirror Failover Process has successfully completed.  Primary (Principal) server is:  &amp;lt;font color="blue"&amp;gt;' + @primary      + '.  &amp;lt;/font&amp;gt; The Secondary (Mirror) now is Server:  &amp;lt;font color="blue"&amp;gt;' + @secondary      +
                        case
                            when @secondary &amp;lt;&amp;gt; @instance then @secondary + '\' + @instance
                            else ''
                        end + '             &amp;lt;/font&amp;gt;
         
 
        &amp;lt;/h1&amp;gt;
 
          
 
&amp;lt;h1&amp;gt;&amp;lt;/h1&amp;gt;
 
 
&amp;lt;table border = 1&amp;gt;
 
&amp;lt;tr&amp;gt;
 
&amp;lt;th&amp;gt; Server   &amp;lt;/th&amp;gt;
 
 
&amp;lt;th&amp;gt; Database &amp;lt;/th&amp;gt;
 
 
&amp;lt;th&amp;gt; Current State    &amp;lt;/th&amp;gt;
 
 
&amp;lt;th&amp;gt; Process  &amp;lt;/th&amp;gt;
 
        &amp;lt;/tr&amp;gt;
 
'
 
set @body_top = @body_top + @xml_top +
/* '&amp;lt;/table&amp;gt;
 
 
&amp;lt;h1&amp;gt;Mid Table Title Here&amp;lt;/h1&amp;gt;
 
 
&amp;lt;table border = 1&amp;gt;
 
&amp;lt;tr&amp;gt;
 
&amp;lt;th&amp;gt; Column1 Here &amp;lt;/th&amp;gt;
 
 
&amp;lt;th&amp;gt; Column2 Here &amp;lt;/th&amp;gt;
 
 
&amp;lt;th&amp;gt; Column3 Here &amp;lt;/th&amp;gt;
 
 
&amp;lt;th&amp;gt; ...      &amp;lt;/th&amp;gt;
 
        &amp;lt;/tr&amp;gt;
 
'       
+ @xml_mid */ 
'&amp;lt;/table&amp;gt;
 
 
&amp;lt;h1&amp;gt;This process is driven by the Job ( DATABASE MIRRORS - Failover All Mirrored Databases )&amp;lt;/h1&amp;gt;
 
 
&amp;lt;h1&amp;gt;Go to the server using Start-Run, or (Win + R) and type in: mstsc -v:' + @server_name_basic + '&amp;lt;/h1&amp;gt;
 
'
+ '&amp;lt;/body&amp;gt;&amp;lt;/html&amp;gt;'
 
-- send email.
 
exec msdb.dbo.sp_send_dbmail
    @profile_name       = 'SQLDatabaseMailProfile'
,   @recipients     = 'SQLJobAlerts@MyDomain.com'
,   @subject        = @message_subject
,   @body           = @body_top
,   @body_format        = 'HTML';
 
 
drop table #mirrored_databases
```

Here's the .sql file for the Job and all it's steps.

create_database_mirror_failover_job.sql.pdf

As a reminder; You'll need to replace just a few things in this logic before running it.
After you open the .sql file in Management Studio do a find and replace for the following items:

Find: MyDomain.com
Replace with: YourDomain.com
Find: MySMTPServer.MyDomain.com
Replace with: YourSMTPServer.YourDomain.com
Find: @recipients = "SQLJobAlerts@MyDomain.com"
Replace with: @recipients = "YourEmailAddress@YourDomain.com"

Note: It's recommended that you use a distribution group for this
Everything else is dynamic and will pull server names from system tables. Theirs not much you need to do here.
You might want to change the security context that the Jobs are running under. You can replace the 'sa' cause you might have that disabled, and are running your Agent Jobs under another account. If thats the case… Do this:
Find: @owner_login_name=N'sa'
Replace with: @owner_login_name=N'SomeOtherLogin'

Thats it.

Hope it works for you. As usual with any process; you might need to tweak it for your needs. This is NOT intended as some officially supported operation. There is always another way of doing things. Some might be better. Some maybe not so much.

https://mikesdatawork.wordpress.com/2015/10/29/automatically-failover-all-database-mirrors-with-a-single-job-1-of-10/

If you want to try your hand at the ridiculous syntax formatting of in this blog on the total Job script here you go. 


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

