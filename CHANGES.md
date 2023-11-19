# CHANGELOG

## XX/11/2023 - Version 3.3

* Added path bar control which is shown when item is selected. Can be disabled.
* Now defaults to killing w. SIGTERM. The old behaviour of sending SIGKILL can be set in Prefs.

### 30/01/2022 - Version 3.2

* Various minor bug fixes and interface refinements

### 18/03/2021 - Version 3.1

* Configurable refresh interval
* Default (regex) filters can be set in Preferences
* Fixed filtering by volume on Catalina and Big Sur
* Various minor bug fixes and interface improvements

### 26/11/2020 - Version 3.0.1

* Fixed crash bug on macOS Big Sur

### 24/11/2020 - Version 3.0

* Universal binary supporting Apple's arm64 architecture
* New square icon for Big Sur
* Info Panel now shows volume name and mount point for file system items
* New "Show Package Contents" contextual menu item for bundles
* Various minor fixes and performance improvements
* Now requires macOS 10.9 or later

### 27/02/2020 - Version 2.9

* Sort by process type, bundle identifier or Carbon Process Serial Number
* Better handling of errors in lsof output

### 30/03/2019 - Version 2.8.1

* Fixed potential crash bug introduced in version 2.8.

### 27/03/2019 - Version 2.8

* New Dark Mode friendly template icons for Mojave
* Multiple items can now be selected and copied
* Info Panel now shows which processes are connected to each other via unix pipes & domain sockets
* Info Panel now also shows file system info such as device name & inode
* Cmd-L menu action to show selected item
* Minor performance improvements
* Sparkle update framework now has Mojave Dark Mode-compatible appearance
* No longer shows hidden volumes in Volumes filter
* Fixed issue with mangled process names
* Fixed issue with pipe icon on non-retina displays
* Fixed minor memory leak
* More graceful error handling when file descriptor lookup fails in lsof

### 10/02/2019 - Version 2.7

* Info Panel now shows file Uniform Type Identifier
* Fixed crash bug on macOS 10.9 and earlier
* Various minor bug fixes and interface improvements

### 26/09/2018 - Version 2.6

* New and improved contextual menu 
* Fixed quirks with macOS Mojave's "Dark Mode"
* Various user interface improvements

### 02/06/2018 - Version 2.5

* Fixed critical lsof output parsing bug introduced in 2.4
* New "Authenticate on launch" option in Preferences
* Various minor interface refinements

### 10/05/2018 - Version 2.4

* Now defaults to showing Mac-friendly process names (e.g. "Safari Web Content" instead of "com.apple.WebKit.WebContent")
* Unix process names no longer truncated to 32 characters
* Search filter can now be used to filter by IP protocol (e.g. TCP or UDP) or IP version (e.g. IPv4 or IPv6)
* Now shows TCP socket state (e.g. LISTEN, ESTABLISHED) in list and Info Panel
* Info Panel now shows file descriptor integer
* Info Panel now shows additional info for character devices
* Info Panel now shows Carbon Process Serial Number (PSN) for processes, if available
* Much improved IPv6 socket handling
* DNS to IP and port name resolution in Info Panel when DNS/port lookup enabled in Prefs
* Minor user interface enhancements

### 16/04/2018 - Version 2.3

* Now supports access mode filtering (e.g. read, write, read/write)
* Search filter now also filters by PID
* DNS and port name lookup for IP Sockets in Info Panel
* Info Panel now identifies standard I/O stream character devices
* New Search Filter menu with case sensitivity and regex options
* New application icon
* Fixed bug where Volumes filter wouldn't work
* Minor interface improvements

### 07/03/2018 - Version 2.2

* Now defaults to excluding process binaries, shared libraries and current working directories in listing
* DNS and port name lookup now disabled by default for faster execution (can be enabled in Preferences)
* Info Panel now displays file access mode and process owner
* New sort option: User ID
* Info Panel now shows IP socket protocol and version
* New Preferences window
* New high-resolution pipe and socket icons
* Fixed bug where sort settings were not respected on launch

### 12/02/2018 - Version 2.1

* Copying a file path now creates a file representation in clipboard in addition to text
* File paths are now red in colour if selected file does not exist at path
* Uniform Type Identifier now used to identify app bundles instead of .app suffix
* Fixed issue with Info Window's handling of moved or non-existent files
* Minor interface refinements

### 01/10/2017 - Version 2.0

* New Volumes filter
* New "Sort By" submenu under View in main menu
* Sorting by PID now correctly does numerical sort instead of alphabetic

### 07/06/2017- Version 1.9

* Files can now be dragged and dropped
* Cmd-F now focuses on filter field
* File representations can now be copied to the clipboard
* Cmd-double-click now reveals file in Finder
* Fixed various minor user interface bugs
* Fixed collapse all bug with Info Panel open
* New compact interface size option
* Fixed broken permissions display for non-bundle processes in Info Panel

### 03/05/2017 - Version 1.8

* Sloth is now code-signed
* QuickLook now works from the Info panel
* Minor user interface improvements

### 17/06/2016 - Version 1.7

* New Info Panel for items
* Minor UI changes

### 24/02/2016 - Version 1.6

* Asynchronous refresh
* Much improved performance
* UI improvements
* New filtering options
* Smarter regex filtering
* Load results as root without relaunching application
* Expanded sorting options
* Migrated project to ARC, modern Objective-C and Xcode 7
* Now requires OS X 10.8 or later

### 08/07/2010 - Version 1.5

* Column sorting, column rearrangement
* Several bug fixes
* Copy/drag and drop selected items

### 29/05/2009 - Version 1.4

* Regular expressions in search filter
* New "Relaunch as root" option
* Fixed bug in Mac OS X 10.5
* Now built for Mac OS X 10.4 or later

### 28/07/2006 - Version 1.3.1

* Released as a Universal Binary

### 05/03/2004 - Version 1.3

* Live update for search filter
* Sorting by column now works
* Performance improvements
* Lots of code replaced by Cocoa bindings thanks to Bill Bumgarner

### 27/02/2004 - Version 1.2

* Filter search field now tries to match all fields when filtering
* Added auto-refresh timer option
* lsof binary and kill signal type can now be set in Preferences
* New application icon
* Added Icelandic and Japanese localizations

### 22/02/2004 - Version 1.1

* Added search filter.
* New Action menu with menu items and shortcuts for button actions

### 21/02/2004 - Version 1.0

* Initial release
