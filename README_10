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

