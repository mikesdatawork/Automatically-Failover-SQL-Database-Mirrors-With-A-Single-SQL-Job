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

