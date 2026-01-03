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
