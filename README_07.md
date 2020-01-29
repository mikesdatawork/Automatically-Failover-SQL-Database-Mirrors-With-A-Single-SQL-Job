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

