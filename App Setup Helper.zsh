#!/bin/zsh

:<<HEADER
██████╗  ██████╗  ██████╗██╗  ██╗███████╗████████╗███╗   ███╗ █████╗ ███╗   ██╗
██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝╚══██╔══╝████╗ ████║██╔══██╗████╗  ██║
██████╔╝██║   ██║██║     █████╔╝ █████╗     ██║   ██╔████╔██║███████║██╔██╗ ██║
██╔══██╗██║   ██║██║     ██╔═██╗ ██╔══╝     ██║   ██║╚██╔╝██║██╔══██║██║╚██╗██║
██║  ██║╚██████╔╝╚██████╗██║  ██╗███████╗   ██║   ██║ ╚═╝ ██║██║  ██║██║ ╚████║
╚═╝  ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝

           Name: App Setup Helper
    Description: Monitors for user config of specified app during onboarding
     Created By: Chad Lawson
        License: Copyright (c) 2023, Rocketman Management LLC. All rights reserved. Distributed under MIT License.
      More Info: For Documentation, Instructions and Latest Version, visit https://www.rocketman.tech/jamf-toolkit

      Parameter Options
        A number of options can be set with policy parameters.
        The order does not matter, but they must be written in this format:
           --options=value
           --trueoption
        See the section immediately below starting with CONFIG for the list.

HEADER

## Configuration Options and Defaults
## An empty value indicates false or no default.
declare -A CONFIG
CONFIG=(
	[appcode]=''                         # REQUIRED: Application to monitor
	[timeout]='300'                      # REQUIRED: Time, in seconds, to wait before dropping out
    [launchpath]=''						 # RECOMMENDED: Full path to application to that needs to be launched
    [domain]="tech.rocketman.tcchelper"  # OPTIONAL: plist(s) to read or store data and options
    [appname]=''                         # OPTIONAL: Name of the Application to be displayed in DEPNotify
	[dnlogofile]=''						 # OPTIONAL: Full path to company Logo to be displayed in DEPNotify. Note: This is only seen if you don't use videos
	[dnvideopath]=''					 # OPTIONAL: Path to folder where the videos are stored. Videos must be named camera.mp4, microphone.mp4, configureapp.mp4, screensharing.mp4

)

###
### Rocketman Functions
###

function debug() { #8f174#
	## debug "Loading info from script parameters"
	## Log format: YYYY-mm-dd HH:MM:SS|PID|Message
	
	## Input
	local message=$1 # The text you want saved to the log	
	## Output: NULL
	
	## Gather log components
	local jamfPID=$$ # Reserved variable for PID
	local timestamp=$(date +'%F %T') # YYYY-MM-DD HH:MM:SS
	
	## If debug is requested, append to logfile
	[[ ${CONFIG[debug]} ]] && echo "${timestamp}|${jamfPID}|${message}" >> ${CONFIG[logfile]}
	
	## All is well
	return 0
}

function dumpLog() { #dcae4#
	## entries=$(dumpLog today)
	
	## Input
	local howMuch=$1                     ## Valid options are: 'all' 'today' or 'single'.
	[[ ${howMuch} ]] || howMuch="single" ## Default is 'single'
	
	## Output
	local logentries=''                  ## Entries from the log matching requested range
	
	if [[ ! -f "${CONFIG[logfile]}" ]]; then
		echo "No log found"
		return 1
	fi
	
	## Log parts to match for searches
	myPID=$$           ## Process ID of this execution
	today=$(date +%F)  ## Today's date in log format
	
	case "${howMuch}" in
		
		'single')
			logentries=$(grep -e "${today}.*|${myPID}|" ${CONFIG[logfile]})
		;;
		
		'today')
			logentries=$(grep "${today}" ${CONFIG[logfile]})
		;;
		
		'all')
			logentries=$(cat "${CONFIG[logfile]}")
		;;
	esac
	
	## Send back the entries
	echo "${logentries}"
	return 0
}

function loadArgs() { #2ca78#
	## loadArgs "CONFIG" "${argv}"

	## Input
	local hashName=$1  ## The name of the array as a string and NOT the array itself
	shift              ## Now the rest of the arguments start at 1

	## Output: NULL

	## If this is a Jamf policy, shift the arguments
	[[ $1 == "/" ]] && shift 3

	## Get a list of keys from the array
	keys=${(Pk)hashName}

	while [[ "$1" ]] ; do		
		## If it matches "--*" or "--*=*", parse into key/value or key/true
		case "$1" in
			--*=* ) # Key/Value pairs
				key=$(echo "$1" | sed -re 's|^\-\-([^=]+)\=.*$|\1|g')
				val=$(echo "$1" | sed -re 's|^\-\-[^=]+\=(.*)$|\1|g')
				[[ $(type debug) =~ "function" ]] && debug "Set ${key} to ${val} requested"
			;;

			--* ) # Simple flags
				key=$(echo "$1" | sed -re 's|\-+(.*)|\1|g')
				val="True"
			;;		

			*) # What if it's random stuff?
				key='' ; val='' ## Clear stuff out for next pass
			;;
		esac

		## If the current key is in the list of valid keys, update the array
		if (($keys[(Ie)$key])); then
			eval "${hashName}[${key}]='${val}'"
		fi		

		shift
	done

	return 0 ## All is well
}

function loadPlist() { #50d1e#
	## loadPlist "CONFIG" "/Library/Preferences/tech.rocketman.workflow.plist"

	## Input
	local hashName=$1    ## The name of the array as a string and NOT the array itself
	local configFile=$2  ## Full path to plist file 

	## Output: NULL

	if [[ -f "${configFile}" ]]; then
		for key in ${(Pk)hashName}; do
			val=$(defaults read "${configFile}" "${key}" 2>/dev/null)
			if [[ $? -eq 0 ]]; then
				eval "${hashName}[$key]='$val'"
			fi
		done
	fi
}

function runAsUser() { #8534c#
	## runAsUser ${CONFIG[currentuser]} open "/Applications/Jamf Connect.app"

	## Input
	local asWhom=$1     ## The short username (e.g. rocketman) 
	shift               ## The rest of the argument is now run as that user

	## Output: NULL

	local userID=$(id -u ${asWhom}) ## sudo uses username but launchtl uses uid
	launchctl asuser "${userID}" sudo -u "${asWhom}" ${argv}
}


function waitForUser() { #09d8c#
	## waitForUser [NOTE: No input or output]
	
	## Input:  NULL
	## Output: NULL
	## NOTE - This function is blocking until user logs in
	## TODO: Add timeout function

	## Check to see if we're in a user context or not. Wait if not.
	dockStatus=$( pgrep -x Dock )
	while [[ "$dockStatus" == "" ]]; do
		sleep 1
		dockStatus=$( pgrep -x Dock )
	done
}

c

function getCurrentUser() { #faaf1#
	## CONFIG[currentuser]=$(getCurrentUser)

	## Input: NULL
	## Output
	local currentUser='' ## The string of the current user

	## Does the existing config know or do we need to check?
	if [[ $1 == '/' ]]; then 
		## We are in a Jamf environment
		currentUser=$3
	else
		## Make sure there's an active user
		dockRunning=$(pgrep -x Dock)
		if [[ ${dockRunning} ]]; then
			currentUser=$(defaults read /Library/Preferences/com.apple.loginwindow.plist lastUserName)
		fi
	fi

	## Send it back
	echo "${currentUser}"
	return 0
}

###
### Workflow Functions
###

function cleanUp() {
	## Input
	local condition=$1 # If non-empty, there was a problem
	
	## Make DEPNotify go away gracefully
	DEPNotify "Command: Quit"
	
	if [[ ${condition} ]]; then
		echo "${condition}"
		exit 1
	fi
}

function checkAccess() {
	application=$1
	service=$2
	
	## Determine which database we need
	case ${service} in
		## Screen recording is handled at the /Library layer
		screen*)
			service='screen'
			db="/Library/Application Support/com.apple.TCC/TCC.db"
		;;
			
		## Microphone and camera are handled at the /User/Library layer
		'microphone' | 'camera')
			db="/Users/${CONFIG[currentuser]}/Library/Application Support/com.apple.TCC/TCC.db"
		;;
	esac
	
	query=""
	## Read the sqlite database
	access=$(sqlite3 \
		-separator ',' \
		"${db}" \
		"select client,service,auth_value from access where service like '%${service}%' and client like '%${application}%'"; \
	)

	lookupSuccess=$?	
	if [[ ${lookupSuccess} ]]; then
		## Send back "On" or "Off"
		[[ ${access: -1} -gt 0 ]] && echo "On" || echo "Off"
	fi
}

function DEPNotify {
	local NotifyCommand=$1
	/bin/echo "$NotifyCommand" >> /var/tmp/depnotify.log
}

function startDEPNotify {
	local DNOpts=$1  ## Ex. --fullscreen
	
	## Create the depnotify log file
	cat /dev/null > /var/tmp/depnotify.log
	chmod 777 /var/tmp/depnotify.log

	## Launch DEP Notify
	DNLoc=$(find /Applications -maxdepth 2 -type d -iname "*DEP*.app" )
	runAsUser $(getCurrentUser) "${DNLoc}/Contents/MacOS/DEPNotify" ${DNOpts} 2>/dev/null &
}

function waitForAccess() {
	## Input
	local accessType=$1
	
	## Output
	local statusCode=1 ## Let's assume there was a problem
	
	## Initial states
	local timeRemaining=${CONFIG[timeout]}
	local accessEnabled="Off"
	
	## Start the clock
	local startTime=$(date +%s)

	while [[ ${accessEnabled} == "Off" && ${timeRemaining} -gt 0 ]]; do
		sleep 1
		accessEnabled=$(checkAccess "${CONFIG[appcode]}" "${accessType}")
		timeRemaining=$(countdown ${startTime} ${CONFIG[timeout]})
	done
	
	## Did we get here because it turned on or timeout
	if [[ ${accessEnabled} == "On" ]]; then
		statusCode=0
	else
		dumpLog
		cleanUp "ERROR: Timeout while enabling ${accessType}"
	fi
	
	return ${statusCode}
}

function waitForDEPNotifyContinue {
	
    ## Input
	local buttonName=$1
    
    ## Creating the Continue button
    DEPNotify "Command: ContinueButton: $buttonName"
	
	## Output
	local statusCode=1 ## Let's assume there was a problem
	
	## Initial states
	local timeRemaining=${CONFIG[timeout]}
	
	## Start the clock
	local startTime=$(date +%s)

	while [[ ! -f /var/tmp/com.depnotify.provisioning.done && ${timeRemaining} -gt 0 ]]; do
		sleep 1
		timeRemaining=$(countdown ${startTime} ${CONFIG[timeout]})
	done
    
    ## Did we get here because it turned on or timeout
	if [[ -f /var/tmp/com.depnotify.provisioning.done ]]; then
		statusCode=0
	else
		dumpLog
		cleanUp "ERROR: Timeout - User did not click Continue"
	fi

    ## Removing the Continue button
    echo "User has clicked Continue. Relaunching the DEPNotify window."
    sed -i '' -e '$ d' /var/tmp/depnotify.log
    rm /private/var/tmp/com.depnotify.provisioning.done
    
    ## Launch DEP Notify
	DNLoc=$(find /Applications -maxdepth 2 -type d -iname "*DEP*.app" )
	runAsUser $(getCurrentUser) "${DNLoc}/Contents/MacOS/DEPNotify" ${DNOpts} 2>/dev/null &
}

###
### Setup
###
CONFIG[jamfurl]=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
CONFIG[serial]=$(system_profiler SPHardwareDataType | awk '(/Serial Number/){print $NF}')
CONFIG[currentuser]=$(getCurrentUser)

## Path to local and managed plist files based on script domain
LOCALPLIST="/Library/Preferences/${CONFIG[domain]}.plist"
MANAGEDPLIST="/Library/Managed Preferences/${CONFIG[domain]}.plist"

## Update input from policy parameters and profiles
loadArgs  "CONFIG" ${argv} ## Start here to get changes in $CONFIG[domain] for plists
loadPlist "CONFIG" "${LOCALPLIST}"
loadPlist "CONFIG" "${MANAGEDPLIST}"
loadArgs  "CONFIG" ${argv} ## Now take these as written in stone

## Check policy parameters or managed plist for updated text/logo
loadPlist "DIALOGS" "${argv}"
loadPlist "DIALOGS" "${MANAGEDPLIST}"

###
### Main
###

## Checks to ensure proper variables are set and files are in place.
if [[ ! ${CONFIG[appcode]} ]];then
	echo "The appcode parameter is not set. This is required to run. Exiting..."
	exit 1				
fi

if [[ ! ${CONFIG[timeout]} ]];then
	echo "The timeout parameter is not set. This is required to run. Exiting..."
	exit 1
fi

[[ -d ${CONFIG[dnvideopath]} ]] && DEPNotify "Command: Video: ${CONFIG[dnvideopath]}/configureapp.mp4"
if [[ ${CONFIG[launchpath]} ]];then
	echo "Checking to see if ${CONFIG[launchpath]} exists..."
	if [[ -d ${CONFIG[launchpath]} ]]; then
		echo "The Application ${CONFIG[launchpath]} exists. Opening Application..."
        open ${CONFIG[launchpath]}
	else
		echo "The Application ${CONFIG[launchpath]} does not exist. Exiting with failure..."
		exit 1
	fi
else
	echo "The Launch Path Configuration is not set. Proceeding without checking if the application exists."
fi


## Set up the initial DEP Notify window, if necessary
if [[ ! $(pgrep -x DEPNotify) ]]; then
	echo "DEPNotify is not running. Starting DEPNotify..."
	iStartedIt='True'
	startDEPNotify
else
	echo "DEPNotify is currently running, no need to launch."
fi

## Setting up the initial Window. 
DEPNotify "Command: MainTitle: Configure ${CONFIG[appname]}"
[[ ${CONFIG[dnlogofile]} ]] && DEPNotify "Command: Image: ${CONFIG[dnlogofile]}"

## Waiting for user to configure the application
DEPNotify "Command: MainText: Please log into ${CONFIG[appname]} and then Click Continue. If you need assistance, please contact IT."
DEPNotify "Status: Follow the instructions to login to ${CONFIG[appname]}"
[[ -d ${CONFIG[dnvideopath]} ]] && DEPNotify "Command: Video: ${CONFIG[dnvideopath]}/configureapp.mp4"
DEPNotify "Command: WindowStyle: Activate"
waitForDEPNotifyContinue "I have logged into ${CONFIG[appname]}"

## Camera
DEPNotify "Status: Enable Camera"
DEPNotify "Command: MainText: Please enable the Camera for ${CONFIG[appname]} to continue."
[[ -d ${CONFIG[dnvideopath]} ]] && DEPNotify "Command: Video: ${CONFIG[dnvideopath]}/camera.mp4"
DEPNotify "Command: WindowStyle: Activate"
waitForAccess "camera"

## Microphone
DEPNotify "Command: MainText: Please enable the Microphone for ${CONFIG[appname]} to continue."
DEPNotify "Status: Enable Microphone"
[[ -d ${CONFIG[dnvideopath]} ]] && DEPNotify "Command: Video: ${CONFIG[dnvideopath]}/microphone.mp4"
DEPNotify "Command: WindowStyle: Activate"
waitForAccess "microphone"

## Screen Sharing
DEPNotify "Command: MainText: Please enable Screen Sharing for ${CONFIG[appname]} to continue."
DEPNotify "Status: Enable Screen Sharing"
[[ -d ${CONFIG[dnvideopath]} ]] && DEPNotify "Command: Video: ${CONFIG[dnvideopath]}/screensharing.mp4"
DEPNotify "Command: WindowStyle: Activate"
waitForAccess "screen"



dumpLog

## If we started it, lets close it
if [[ ${iStartedIt} ]]; then
	## Notify the user of Completion
    DEPNotify "Command: MainTitle: Configuration of ${CONFIG[appname]} is complete!"
    DEPNotify "Command: MainText: You have successfully configured ${CONFIG[appname]}."
    DEPNotify "Status: Configuration of ${CONFIG[appname]} complete!"
    DEPNotify "Command: WindowStyle: Activate"
	DEPNotify  "Command: Quit: You have successfully configured ${CONFIG[appname]}!"
	cleanUp
fi