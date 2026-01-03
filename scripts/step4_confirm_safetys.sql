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
        '

### ' + @message_subject + '

# A Failover error occurred before the databases could be failed over from the Primary Server:  ' + @primary + ' 
        to the Secondary Server: ' + @secondary        +
                        case
                            when @secondary <> @instance then @secondary + '\' + @instance
                            else ''
                        end + '             
                 
        Not all the Mirrored Datatabases could be set to Full Safety.  Full safetys are required before failover.  Please check the databases and ensure all are set to full safety before the failover process can proceed to the next step.

# Current Safety Modes

# Full Safety Off = (ASYNCHRONOUS - HIGH PERFORMANCE)

# Full Safety On = (SYNCHRONOUS - HIGH SAFETY)

'
 
set @body_top = @body_top + @xml_top +
/* '

| Server | Database | Synchronous Mode |
| --- | --- | --- |

# Mid Table Title Here

'       
+ @xml_mid */ 
'

| Column1 Here | Column2 Here | Column3 Here | ... |
| --- | --- | --- | --- |

# Go to the server using Start-Run, or (Win + R) and type in: mstsc -v:' + @server_name_basic + '

'
+ ''
 
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
