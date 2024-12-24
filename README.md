
# HLStatsX-Top10-Announcer

![GitHub Release](https://img.shields.io/github/v/release/DNA-styx/HLStatsX-Top10-Announcer)
![Total Downloads](https://img.shields.io/github/downloads/DNA-styx/HLStatsX-Top10-Announcer/total)
![Issues](https://img.shields.io/github/issues/DNA-styx/HLStatsX-Top10-Announcer)
![GitHub commit activity](https://img.shields.io/github/commit-activity/m/DNA-styx/HLStatsX-Top10-Announcer)
![GitHub last commit](https://img.shields.io/github/last-commit/DNA-styx/HLStatsX-Top10-Announcer)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/DNA-styx/HLStatsX-Top10-Announcer/.github%2Fworkflows%2Ftest_build.yaml)


- https://forums.alliedmods.net/showthread.php?t=139703



# Setup

databases.cfg

```
"top10"
	{
		"driver"			"default"
		"host"				"<your database ip or hostname>"
		"database"			"<your hlstatx database name>"
		"user"				"<your database userid>"
		"pass"				"<your database password>"
		//"timeout"			"0"
		"port"				"3306"
	}
```

# Cvars

```
"sm_top10_hlstatsce_enabled", "1", "Whether this plugin should be enabled"
"sm_top10_hlstatsce_game", buffer, "The shortname found after the game settings for particular servers on admin page"
"sm_top10_hlstatsce_text", "2", "Default message type. 1 = Center, 2 = Hint text, 3 = Regular text. Leave empty for center"
"sm_top10_hlstatsce_sounds", "addons/sourcemod/configs/top10_sounds.kv", "The config file containing the paths of sounds to play when a top10 hlstats player joins the game"
```

# In Game Commands
```
!settings
```
