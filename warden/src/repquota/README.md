# repquota

This program has similar functionality to `repquota` provided by the standard
quota packages. One difference is that it does not require you to `sync` the
filesystem before calling it, and always returns up-to-date quota usage and
limits.

Another difference is that it allows the user to specify a list of UIDs for
which to query the quota usage and limits, and does not print out the quota
usage and limits for all users.