# TODO for Sloth

* STPrivilegedTask relies on long-deprecated AuthorizationExecuteWithPrivileges function
* Preserve selection between refreshes (preserve expanded items between refreshes?)
* Show full command (i.e. w. args) for process (ala ps -ef) in Info Panel
* Highlight matching part of string when filtering (option in filter field popup - might be slow)
* Store authentication privileges and use them to run command line tool "/usr/bin/file" for Info Dialog when already authenticated
* Add tests for lsof output parsing
* Click on connected process f. pipes to select and show info of that process
* Create visualization of pipes between processes in special view
* Structure item objects instead of using MutableDictProxy
* Make port and DNS lookup in Info Panel configurable in Settings
* Make *all* file info async in Info Panel
* Update old screenshots in README
