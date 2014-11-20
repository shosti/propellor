module Propellor.Property.Cron where

import Propellor
import qualified Propellor.Property.File as File
import qualified Propellor.Property.Apt as Apt
import Utility.SafeCommand
import Utility.FileMode

import Data.Char

type CronTimes = String

-- | Installs a cron job, run as a specified user, in a particular
-- directory. Note that the Desc must be unique, as it is used for the 
-- cron.d/ filename.
-- 
-- Only one instance of the cron job is allowed to run at a time, no matter
-- how long it runs. This is accomplished using flock locking of the cron
-- job file.
--
-- The cron job's output will only be emailed if it exits nonzero.
job :: Desc -> CronTimes -> UserName -> FilePath -> String -> Property
job desc times user cddir command = combineProperties ("cronned " ++ desc)
	[ cronjobfile `File.hasContent`
		[ "# Generated by propellor"
		, ""
		, "SHELL=/bin/sh"
		, "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
		, ""
		, times ++ "\t" ++ user ++ "\tchronic " ++ shellEscape scriptfile
		]
	-- Use a separate script because it makes the cron job name 
	-- prettier in emails, and also allows running the job manually.
	, scriptfile `File.hasContent`
		[ "#!/bin/sh"
		, "# Generated by propellor"
		, "set -e"
		, "flock -n " ++ shellEscape cronjobfile
			++ " sh -c " ++ shellEscape cmdline
		]
	, scriptfile `File.mode` combineModes (readModes ++ executeModes)
	]
	`requires` Apt.serviceInstalledRunning "cron"
	`requires` Apt.installed ["util-linux", "moreutils"]
  where
	cmdline = "cd " ++ cddir ++ " && ( " ++ command ++ " )"
	cronjobfile = "/etc/cron.d/" ++ name
	scriptfile = "/usr/local/bin/" ++ name ++ "_cronjob"
	name = map sanitize desc
	sanitize c
		| isAlphaNum c = c
		| otherwise = '_'

-- | Installs a cron job, and runs it niced and ioniced.
niceJob :: Desc -> CronTimes -> UserName -> FilePath -> String -> Property
niceJob desc times user cddir command = job desc times user cddir
	("nice ionice -c 3 sh -c " ++ shellEscape command)

-- | Installs a cron job to run propellor.
runPropellor :: CronTimes -> Property
runPropellor times = niceJob "propellor" times "root" localdir "make"