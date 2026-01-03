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
 
 
        The Mirror Failover Process has successfully completed.  Primary (Principal) server is:  <font color="blue">' + @primary      + '.  </font> The Secondary (Mirror) now is Server:  <font color="blue">' + @secondary      +
                        case
                            when @secondary <> @instance then @secondary + '\' + @instance
                            else ''
                        end + '             </font>
         
 
        </h1>
 
          
 
<h1></h1>
 
 
<table border = 1>
 
<tr>
 
<th> Server   </th>
 
 
<th> Database </th>
 
 
<th> Current State    </th>
 
 
<th> Process  </th>
 
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
,   @body_format        = 'HTML';
 
 
drop table #mirrored_databases
