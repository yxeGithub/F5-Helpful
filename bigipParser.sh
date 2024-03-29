#!/bin/bash
#
# bigipParser
# Author: Fatih Celik (9.2020)
# 
# This script provides Virtual Servers and it's dependent objects as divided by files with objects as much as possible
# It takes single argument which points of bigip.conf file. 
# Usage: 
# bigipParser  path/to/bigip.conf
#
# 
# Copyright (C) Fatih Celik, hereby disclaims all copyright
# interest in the program written by Fatih CELIK
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. 
#
#########################################################################
#																		#
# ver. 0.10																#
# ver. 0.20   Denis F5 - YXESE - Modified to work on OSX and updates    #
# ver. 0.21	  Denis F5 - YXESE - Modified to change Declare -A; not -a  #
# ver. 0.22   Denis F5 - YXESE - Fixed a bunch of profile types that    #
#             were not processing and giving error.  There is still the #
#             security dos profile that doesnt work                     #
#																		#
#########################################################################
# ****************************** Important ******************************

#if you get tr errors then run these 2 commands at the command prompt
export LC_ALL=C
export LC_CTYPE=C

if [ $# -ne 1 ]; then 
	echo -e "\n\tUsage: bigipParser  /path/to/bigip.conf\n"
	exit 9
	
fi

er=0

for command in awk grep cat tac tail head sed base64
do
	if [ -x "/bin/${command}" ] || [ -x "/usr/bin/${command}" ] || [ -x "/usr/local/bin/${command}" ]; then
	
		printf "%-24s [ OK ]\n" "${command}"
	   
	else
	
		printf "%-24s [ MISSING ]\n" "${command}"
		(( er += 1 ))

	fi
done

if [ $er -ne 0 ]; then
	echo -e "\nSorry, Some of the tools ( ${er} pieces ) listed above are missing.\nPlease fullfill the requirements before using this script\n"
	exit 40
fi

confFile="$1"
DEBUG=1 		# Need more details ? Set any thing !
# Prepare bigip.conf file 
# Since iApp created Virtual Servers not important for us, erase those lines 'app.service' and '*.app' in where they stands

# OSX Freindly - run these at teh cmd line to test
#export LC_ALL=C
#export LC_CTYPE=C
#iAppFreeConfFile=/tmp/bigip.conf_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9-_!@#$%^&*()_+{}|:<>?=' | head -c 10 | base64)

iAppFreeConfFile=/tmp/bigip.conf_$(cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c 10 | base64) 
#~ sed -e 's/[a-zA-Z0-9\_\-\.]\+app\///g' -e '/app-service/d' "${confFile}" > ${iAppFreeConfFile}
sed -e '/app-service/d' "${confFile}" > ${iAppFreeConfFile}

# lets find out how many conf object in bigip.conf file
declare -A virtServerArray			#OK
declare -A poolArray				#OK
declare -A monitorArray				#OK
declare -A policyArray				#OK
declare -A iruleArray				#OK
declare -A snatTranslationArray		#OK
declare -A snatPoolArray			#OK
declare -A dataGroupArray			#OK
declare -A persistArray				#OK
declare -A profileArray				#OK
declare -A virtAddrArray			#OK
declare -A sysiFileArray			#OK
declare -A ltmiFileArray			#OK
declare -A sysSslCertArray			#OK
declare -A sysSslKeyArray			#OK

# declare -a netRouteArray # Should I worry about route definitions and some other objects like ssl certs & keys ?
# Yes, we support iFiles and we are going to implement a support for SSL certs & Keys soon

vsRange=0
policyRange=0
poolRange=0
ruleRange=0
virtAddrRange=0
sysiFileRange=0
ltmiFileRange=0
[ $DEBUG ] && echo -e "#################################################\n## $(date)\n#################################################\n"

findFinish(){
	#!/bin/bash
	# count every opening and closing curly brace and find out where it ends...
	if [ $# -ne 2 ]; then
		i=1
		openCurly=0
		while read -r line
		do
		  isCurly=$(echo $line | grep -E "{|}" )
		  if [ "$isCurly" ]; then 
			openCurly=$(( openCurly + $(echo $line | sed 's/[^{]//g' | tr -d '\n' | wc -m) ))
			openCurly=$(( openCurly - $(echo $line | sed 's/[^}]//g' | tr -d '\n' | wc -m) ))	
			if [ $openCurly -eq 0 ]; then 
				endingLine=$i		
				echo $endingLine
				exit 0
			fi
		  fi
		  (( i+=1 ))
		done < <( cat - ) 

	else 
		i=1
		openCurly=0
		file=$1
		start=$2
		while read -r line
		do
		  isCurly=$(echo $line | grep -E "{|}" )
		  if [ "$isCurly" ]; then 
			openCurly=$(( openCurly + $(echo $line | sed 's/[^{]//g' | tr -d '\n' | wc -m) ))
			openCurly=$(( openCurly - $(echo $line | sed 's/[^}]//g' | tr -d '\n' | wc -m) ))	
			if [ $openCurly -eq 0 ]; then 
				endingLine=$i		
				echo $endingLine
				exit 0
			fi
		  fi
		  (( i+=1 ))
		done < <( /usr/bin/tail -n +${start} $file ) 
	fi
}

get_virtualServer(){
# lets find how many Virtual Servers in that config file and then populate our Array (virtServerArray) with them.
# Array Contains Virtual Server names, starting and ending points
# Before; tempArray[index]=StartLine:EndingLine:Name
# After; Array[Name]=StartLine,EndingLine
	declare -a tempArray
	local name start end res

	#read -a tempArray <<< $( grep -nE "ltm virtual " ${iAppFreeConfFile} | sed -e 's/ltm virtual \/Common\//\:/g' -e 's/{ \|{//g' | tr '\n' ' ' )
	read -a tempArray <<< $( grep -nE "ltm virtual " ${iAppFreeConfFile} | sed -e 's/ltm virtual \/Common\//\:/g' -e 's/{//g' | tr '\n' ' ' )
		[ $DEBUG ] && declare -p tempArray | tr " " "\n" # debug

	if [ ${#tempArray[@]} -ne 0 ]; then 
		for (( i = 0; i < ${#tempArray[@]}; i++)){
			start=$( echo ${tempArray[i]} | awk -F':' '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F':' '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F':' '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi
			if [ $(( ${#tempArray[@]} -1)) -eq ${#virtServerArray[@]} ]; then
				res=$(findFinish ${iAppFreeConfFile} $start)
				ECHO "RES=$res"
				end=$(( $res + $start -1 ))
				vsRange=$( echo "${vsRange},${end}" )
			fi
			if [ $i -eq 0 ]; then
				vsRange=$start
			fi
			virtServerArray["${name}"]="${start},${end}"
		}	
		[ $DEBUG ] && declare -p virtServerArray | tr ' ' '\n' # debug
	else
		echo -e "\tNo Virtual Server found\n...so we quit"
		exit 11
	fi
	unset tempArray
}

get_virtAddr(){
# Populate Virtual IP Address list with below format
# virtAddrArray[virtIPAddr]="StartingLine,EndingLine
	declare -a tempArray
	local name start end res
	
	read -a tempArray <<< $( grep -nE "^ltm virtual-address " ${iAppFreeConfFile} | awk -F '/' '{ print $1" "$3 }' | sed -e 's,:, ,g' -e 's, {,,g' -e s'/ ltm virtual-address //g' -e 's/ /::/g' | tr '\n' ' ' )
	[ $DEBUG ] && declare -p tempArray | tr ' ' '\n' # debug
	
	if [ ${#tempArray[@]} -ne 0 ]; then		
		for (( addr=0; addr < ${#tempArray[@]}; addr++ )){
			name=$( echo ${tempArray[$addr]} | awk -F ':' '{ print $3 }' )
			start=$( echo ${tempArray[$addr]} | awk -F ':' '{ print $1 }' )
			end=$( echo ${tempArray[$addr + 1]} | awk -F ':' '{ print $1 -1 }' )
			if [ $(( ${#tempArray[@]} -1 )) -eq ${#virtAddrArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $start + $res -1 ))
				virtAddrRange=$(echo "${virtAddrRange},${end}" )
			fi
			if [ $addr -eq 0 ]; then
				virtAddrRange=$start
			fi
			#echo "addr = $addr    name = $name     start = $start     end = $end"  		
			virtAddrArray["${name}"]="${start},${end}"			
		}

		[ $DEBUG ] && declare -p virtAddrArray | tr ' ' '\n' # debug		
	fi	
	unset tempArray	
}
 
get_pools(){
# populate array with pool names and add the starting, ending points	
# poolArray[poolName]=Number_of_StartingLine,Number_of_EndingLine
	declare -a tempArray
	declare -a poolUsedInRules
	local name start end res 

	read -a tempArray <<< $( grep -nE "ltm pool " ${iAppFreeConfFile} | sed -e 's/ltm pool \/Common\//\:/g' -e 's/ {//g' -e 's/{ \|{//g' -e 's,}$,,g' | tr '\n' ' ' )
	#read -a tempArray <<< $( grep -nE "ltm pool " ${iAppFreeConfFile} | sed -e 's/ltm pool \/Common\//\:/g' -e 's/{ \|{//g' -e 's/{ \|{//g' -e 's,}$,,g' | tr '\n' ' ' )
	[ $DEBUG ] && declare -p tempArray | tr ' ' '\n' # debug
	
	if [ ${#tempArray[@]} -ne 0 ]; then 		
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi			

			if [ $(( ${#tempArray[@]} -1)) -eq ${#poolArray[@]} ]; then
				res=$(findFinish ${iAppFreeConfFile} $start)
				end=$(( $res + $start -1 ))
				poolRange=$( echo "${poolRange},${end}" )
			fi

			if [ $i -eq 0 ]; then
				poolRange=$start
			fi

			poolArray["${name}"]="${start},${end}"
			
			if [ ! -z $ruleRange ]; then # if there is no iRule, no need to go further then...
				read -a poolUsedInRules <<< $( sed -n ${ruleRange}p ${iAppFreeConfFile} | grep -nE "$name" | grep -v "#" | cut -d ":" -f 1 | tr '\n' ' ' )
				[ $DEBUG ] && echo "Pool Used IN Rules first populate" # debug
				[ $DEBUG ] && echo "DEBUG - IF the Pool ${name}, -> ${poolArray["${name}"]} Used IN anywhere of whole iRules list" && declare -p poolUsedInRules | tr " " "\n" # debug
				 
				if [ ${#poolUsedInRules[@]} -ne 0 ]; then 
						#~ extractPools "$name"
						extract_poolsFromiRules "$name"
				fi
			fi
		}
		
	
	else 
		echo -e "\tNo Pool Found"	
	fi
	
	[ $DEBUG ] && echo "Status of poolArray after Pool Array Populated:" # debug
	[ $DEBUG ] && declare -p poolArray | tr " " "\n" # debug
	[ $DEBUG ] && echo "Status of iruleArray after Pool Array Populated:" # debug
	[ $DEBUG ] && declare -p iruleArray | tr " " "\n" # debug
	unset tempArray poolUsedInRules
}

get_policy(){
# Populate Array (policyArray) below formats
# policyArray[PolicyName]=StartLine,EndLine
	declare -a tempArray
	local name start end res

	read -a tempArray <<< $( grep -nE "ltm policy " ${iAppFreeConfFile} | sed -e 's/ltm policy \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
	# read -a tempArray <<< $( grep -nE "ltm policy " ${iAppFreeConfFile} | sed -e 's/ltm policy \/Common\//\:/g' -e 's/{ \|{//g' | tr '\n' ' ' )

	[ $DEBUG ] && echo -e "DEBUG - policies temp array;\n" && declare -p tempArray | tr ' ' '\n' # DEBUG

	if [ ${#tempArray[@]} -ne 0 ]; then	
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
					name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi			
			
			if [ $(( ${#tempArray[@]} -1)) -eq ${#policyArray[@]} ]; then
				res=$(findFinish ${iAppFreeConfFile} $start)
				end=$(( $res + $start -1 ))
				policyRange=$( echo "${policyRange},${end}" )
			fi

			if [ $i -eq 0 ]; then
				policyRange=$start
			fi

			policyArray["${name}"]="${start},${end}"		
		}

		#~ debug
		[ $DEBUG ] &&  declare -p policyArray | tr ' ' '\n' 	
	else
		echo -e "\tNo Policy found"
		policyRange=""
	fi
		
	unset tempArray	
}

get_iRules(){
	declare -a tempArray
	local start end name res
	
	read -a tempArray <<< $( grep -nE "ltm rule " ${iAppFreeConfFile} | sed -e 's/ltm rule \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
		[ $DEBUG ] && echo "IRULE first"
		[ $DEBUG ] && declare -p tempArray | tr " " "\n" # debug
		
	if [ ${#tempArray[@]} -ne 0 ]; then		
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi	
				
			if [ $(( ${#tempArray[@]} -1)) -eq ${#iruleArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
				ruleRange="$( echo ${ruleRange},${end} )"
			fi
			
			if [ $i -eq 0 ]; then 
				ruleRange=$start
			fi
			
			iruleArray["${name}"]="${start},${end}"
		}			
		[ $DEBUG ] && echo " iRule ARRAY " # debug
		[ $DEBUG ] && echo " iRule Range ( ruleRange ) is $ruleRange" # debug
		[ $DEBUG ] && declare -p iruleArray | tr " " "\n" # debug		
	else	
		echo -e "\tNo iRule found"
		ruleRange=""	
	fi
	
	unset tempArray	
}

get_iFiles(){
	# this function detect if there is any "ltm ifile" definitions exist
	# then fullfill their start and end line numbers like others. But
	# this time we 'll use this array store more than one tuples like "Start,End:Start,End:Start,End:(...),(...)"
	# As you guess, the first tuple is point "ltm ifile" lines and second tuples points its corresponding sub "sys file ifile" line ranges.
	declare -a tempArray # for "sys file ifile"
	declare -a tmpArray  # for "ltm ifile"
	local start end name res
	
	read -a tmpArray <<< $( grep -nE "^ltm ifile " ${iAppFreeConfFile} | sed -e 's,:[a-z]\+\ ifile\ /[a-zA-Z0-9\-\_]\+/,::,g' -e 's, {$,,g' | tr '\n' ' ' )
	[ $DEBUG ] && echo "DEBUG - ltm ifile temp array " && declare -p tmpArray | tr ' ' '\n' #debug
	
	if [ ${#tmpArray[@]} -ne 0 ]; then #ltm ifile lines exist so we can go further and find "sys file ifile" lines	
		for (( k = 0; k < ${#tmpArray[@]}; k++ )){
				start=$( echo ${tmpArray[k]} | awk -F: '{ print $1 }' )
				end=$( echo ${tmpArray[k+1]} | awk -F: '{ print $1 -1 }' )
				name=$( echo ${tmpArray[k]} | awk -F: '{ print $3 }' )
				if [ $( echo "$name" | grep -E "\.app\/") ]; then
					name=$( echo $name | awk -F "/" '{ print $2"__APP"}' )
				fi		
				if [ $(( ${#tmpArray[@]} -1 )) -eq ${#ltmiFileArray[@]} ]; then
					res=$( findFinish ${iAppFreeConfFile} $start )
					end=$(( $res + $start -1 ))
					ltmiFileRange=$( echo "${ltmiFileRange},${end}" )
				fi
				
				if [ $k -eq 0 ]; then
					ltmiFileRange=$start
				fi
				ltmiFileArray["${name}"]="${start},${end}"	
		}
			
		[ $DEBUG ] && echo "DEBUG - ltmiFileArray " && declare -p ltmiFileArray | tr ' ' '\n' # debug
		[ $DEBUG ] && echo -e "DEBUG - ltmiFileRange is ${ltmiFileRange}\n\n" # debug
		
		read -a tempArray <<< $( grep -nE "^sys file ifile " ${iAppFreeConfFile} | sed -e 's,:, ,g' -e 's, {$,,g' | awk  '{ print $1"::"$NF }' | sed -e 's,/[a-zA-Z0-9\-\_]\+/,,g' | tr '\n' ' ')
		[ $DEBUG ] && echo "DEBUG - sys file ifile temp array " && declare -p tempArray | tr ' ' '\n' #debug
		if [ ${#tempArray[@]} -ne 0 ]; then
			for (( i = 0; i < ${#tempArray[@]}; i++ )){
				start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
				end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
				name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )

				if [ $( echo "$name" | grep -E "\.app\/") ]; then
					name=$( echo $name | awk -F "/" '{ print $2"__APP"}' )
				fi		
	
				if [ $(( ${#tempArray[@]} -1)) -eq ${#sysiFileArray[@]} ]; then
					res=$( findFinish ${iAppFreeConfFile} $start )
					end=$(( $res + $start -1 ))
					sysiFileRange=$( echo "${sysiFileRange},${end}" )
				fi
				
				if [ $i -eq 0 ]; then
					sysiFileRange=$start
				fi
				sysiFileArray["${name}"]="${start},${end}"
			}
			
			[ $DEBUG ] && echo "DEBUG - sysiFileArray " && declare -p sysiFileArray | tr ' ' '\n' # debug
			[ $DEBUG ] && echo "DEBUG - sysiFileRange is ${sysiFileRange}" # debug		
		fi

		for m in "${!ltmiFileArray[@]}"
		do	
			if [ $( echo  ${ltmiFileArray[$m]} | grep -E "[0-9]+,[0-9]+" ) ]; then
				ifileName=$( sed -n "${ltmiFileArray[$m]}p" ${iAppFreeConfFile} | grep "file-name " | awk -F '/' '{ print $3 }' )			
				if [ $( echo "${sysiFileArray[${ifileName}]}" | grep -E "[0-9]+,[0-9]+" ) ]; then
					ltmiFileArray["${m}"]="${ltmiFileArray[${m}]};${sysiFileArray[${ifileName}]}"
					[ $DEBUG ] && echo "ltm iFile - ${ltmiFileArray[${m}]};${sysiFileArray[${ifileName}]}"
					fileName=$( sed -n "${sysiFileArray[${ifileName}]}p" ${iAppFreeConfFile} | grep -E "^\s{4}cache-path " | awk -F '/' '{ print $NF }' )
					res=$( find . -type f -name "${fileName}" )
					if [ -a "${res}" ]; then
						ltmiFileArray["${m}"]="${ltmiFileArray[${m}]};${res}"
					else
						echo "Sorry Can not find the file - ${res}"
						ltmiFileArray["${m}"]="${ltmiFileArray[${m}]};NOFILE"
					fi			
				else		
					echo "These ifile and sys ifile tuples are missing --> ${ltmiFileArray[${m}]};${sysiFileArray[${ifileName}]} <-- "
					ltmiFileArray["${m}"]="${ltmiFileArray[${m}]};N"
				fi
			else
				echo "Sorry, There is no iFile - ${ltmiFileArray[$m]}"
			fi
		done	
		
		[ $DEBUG ] && echo -e "DEBUG - After the sys file ifile \ninformation has been \nadded ltmiFileArray " && declare -p ltmiFileArray | tr ' ' '\n' # debug		
	fi
	
	unset tempArray
	unset tmpArray	
}

get_snatTranslation(){
	declare -a tempArray
	local start end name res
	
	read -a tempArray <<< $( grep -nE "ltm snat-translation " ${iAppFreeConfFile} | sed -e 's/ltm snat-translation \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
		
	if [ ${#tempArray[@]} -ne 0 ]; then	
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi	
				
			if [ $(( ${#tempArray[@]} -1)) -eq $i ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
			fi
				
			snatTranslationArray["${name}"]="${start},${end}"
		}	

		[ $DEBUG ] && declare -p snatTranslationArray | tr ' ' '\n' # debug
	else	
		echo -e "\tNo Snat Translation found"	
	fi
	
	unset tempArray		
}

get_snatPool(){
	declare -a tempArray
	local start end name res
	
	read -a tempArray <<< $( grep -nE "ltm snatpool " ${iAppFreeConfFile} | sed -e 's/ltm snatpool \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
		
	if [ ${#tempArray[@]} -ne 0 ]; then	
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi
				
			if [ $(( ${#tempArray[@]} -1)) -eq ${#snatPoolArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
			fi

			snatPoolArray["${name}"]="${start},${end}"
		}
		
		[ $DEBUG ] &&  declare -p snatPoolArray | tr ' ' '\n' # debug
	else
		echo -e "\tNo Snat Pool found"
	fi
	
	unset tempArray	
}

get_monitors(){
	declare -a tempArray
	local start end name res
	
	#read -a tempArray <<< $( grep -nE "ltm monitor " ${iAppFreeConfFile} | sed -e 's/ltm monitor [a-zA-Z0-9\_\-]\+\ \/Common\//:/g' -e 's/ {//g' | tr '\n' ' ' )
	read -a tempArray <<< $( grep -nE "ltm monitor " ${iAppFreeConfFile} | sed -e 's/ltm monitor [a-zA-Z0-9\_\-]*\ \/Common\//:/g' -e 's/ {//g' | tr '\n' ' ' )
		
	if [ ${#tempArray[@]} -ne 0 ]; then
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )	
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi	
				
			if [ $(( ${#tempArray[@]} -1)) -eq ${#monitorArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
			fi	
			monitorArray["${name}"]="${start},${end}"
		}	
		[ $DEBUG ] && declare -p monitorArray | tr ' ' '\n' # debug
	else
		echo -e "\tNo Monitor found"
	fi
	
	unset tempArray		
}

get_persistence(){
	declare -a tempArray
	local start end name res
	
	read -a tempArray <<< $( grep -nE "ltm persistence " ${iAppFreeConfFile} | sed -e 's/ltm persistence [a-zA-Z0-9\_\-]*//g' -e 's/ \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
		
	if [ ${#tempArray[@]} -ne 0 ]; then	
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi	
				
			if [ $(( ${#tempArray[@]} -1)) -eq ${#persistArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
			fi
	
			persistArray["${name}"]="${start},${end}"
		}	

		[ $DEBUG ] && declare -p persistArray | tr ' ' '\n' # debug
	else
		echo -e "\tNo Persistence found"
	fi
	
	unset tempArray	
}

get_dataGroup(){
	declare -a tempArray
	local start end name res
	
	read -a tempArray <<< $( grep -nE "ltm data-group " ${iAppFreeConfFile} | sed -e 's/ltm data-group [a-zA-Z0-9\_\-]*//g' -e 's/ \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
		
	if [ ${#tempArray[@]} -ne 0 ]; then
		
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )	
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi
				
			if [ $(( ${#tempArray[@]} -1)) -eq ${#dataGroupArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
			fi
			
			dataGroupArray["${name}"]="${start},${end}"
		}	
			[ $DEBUG ] && declare -p dataGroupArray | tr ' ' '\n' # debug
	else
		echo -e "\tNo Data Group found"
	fi
	unset tempArray
}

get_profile(){
	declare -a tempArray
	local start end name res
	
	#Original 11 Aug 2022
	#read -a tempArray <<< $( grep -nE "ltm profile " ${iAppFreeConfFile} | sed -e 's/ltm profile [a-zA-Z0-9\_\-]*//g' -e 's/ \/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )

	read -a tempArray <<< $( grep -nE "ltm profile |security bot-defense asm-profile |security bot-defense profile " ${iAppFreeConfFile} | sed -e 's/security bot-defense asm-profile [a-zA-Z0-9\_\-]*//g' -e 's/ltm profile [a-zA-Z0-9\_\-]*//g' -e 's/security bot-defense profile [a-zA-Z0-9\_\-]*//g' -e 's/security dos profile [a-zA-Z0-9\_\-]*//g' -e 's/ \/Common\//\:/g' -e 's/\/Common\//\:/g' -e 's/ {//g' | tr '\n' ' ' )
		
	if [ ${#tempArray[@]} -ne 0 ]; then
		for (( i = 0; i < ${#tempArray[@]}; i++ )){
			start=$( echo ${tempArray[i]} | awk -F: '{ print $1 }' )
			end=$( echo ${tempArray[i+1]} | awk -F: '{ print $1 -1 }' )
			name=$( echo ${tempArray[i]} | awk -F: '{ print $3 }' )	
			if [ $( echo "$name" | grep -E "\.app\/") ]; then
				name=$( echo $name | awk -F "/" '{ print $2"__APP"}')
			fi
				
			if [ $(( ${#tempArray[@]} -1)) -eq ${#profileArray[@]} ]; then
				res=$( findFinish ${iAppFreeConfFile} $start )
				end=$(( $res + $start -1 ))
			fi
	
			profileArray["${name}"]="${start},${end}"
		}
		[ $DEBUG ] && declare -p profileArray | tr ' ' '\n' # debug
	else
		echo -e "\t\nNo Profile found"
	fi
	
	unset tempArray	
}

get_extraPools(){ 
# find dataGroups used in iRules
	local lines
	declare -a tempArray
	
	lines="$1"
	echo "Extra Pool -----------------!!!!!!!!!"
	echo "$1"
	
	read -a tempArray <<< $( sed -n ${lines}p ${iAppFreeConfFile} | grep -E "class match" \
		| sed -E -e 's/if |elseif | else //g' -e 's/{|}|\[|\]| ]|] |[ |] !|\(|\)//g' -e 's/\&&.*|or .*|\"//g' | awk 'NF>1 { print $NF }'  | tr '\n' ' ' )
		#| sed -e 's/if\|elseif\| else //g' -e 's/{\|}\|\[\|\]\|\!\|(\|)//g' -e 's/&&\|||/\n/g' | awk 'NF>1 { print $NF }' | tr '\n' ' ' )		
		
	for _e in ${!tempArray[@]}
	do
		[ $DEBUG ] && echo -e "Extra Pool Server Start,End --> ${dataGroupArray[${tempArray[$_e]}]}p"
		if [ $( echo "${dataGroupArray[${tempArray[$_e]}]}" | grep -E "[0-9]+\,[0-9]+" ) ]; then
			sed -n ${dataGroupArray[${tempArray[$_e]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
		else
			echo "ERROR - Extra Pool Start or End or both are missing"
			echo -e "#############################################\n## ERROR - Looks like there is a Data-Group in the above irule\n## and somehow i could not parse it\n#############################################\n" >> "$vsFileName"
		fi
	done
	
	unset tempArray
}

extract_poolsFromiRules(){
	# this is the function which extracts pool names from iRules and inserts their start,end tuple
	# informations back in iRuleArray[]. This is the second design implamantation and this is faster than previous one.
	# it accepts iRuleName as first and only parameter. 
	
	local _offset _ruleName _rule _pName _m
	_pName="$1"
	
	# lets replace real line numbers with numbers in array of pools where we found.
	# since we assume ruleRange is our offset, we have to replace those numbers
	
	_offset=$( echo $ruleRange | cut -d ',' -f 1 )
	
	if [ $DEBUG ]; then 
		echo "Looking for pool $_pName. The offset is $_offset"
		echo "We have line numbers of the iRules which used the pool $_pName"
		declare -p poolUsedInRules | tr ' ' '\n'
		echo -e "---------------------------------------------\n"
	fi
	
	for _m in "${!poolUsedInRules[@]}"
	do
		poolUsedInRules[$_m]=$(( ${_offset} + ${poolUsedInRules[$_m]} ))
		[ $DEBUG ] && echo "The actual line number of ${_m}.th is = ${poolUsedInRules[$_m]} "
		_rule=$( sed -n "1,${poolUsedInRules[$_m]}p" ${iAppFreeConfFile} | tac | grep -m1 -E "ltm rule /[a-zA-Z0-9\-\_\.]+/" | sed -e 's, {,,g' -e 's,/, ,g' | awk '{ print $NF }' )
		
		poolUsedInRules[$_m]="$_rule"
		[ $DEBUG ] && echo "poolUsedInRule Array ${_m}.th element is replaced with the name of irule ${poolUsedInRules[$_m]}"		
	done
	
	[ $DEBUG ] && echo "We have located all iRules which used the pool $_pName"
	[ $DEBUG ] && declare -p poolUsedInRules | tr ' ' '\n'
	[ $DEBUG ] && echo -e "---------------------------------------------\n"
	
	# How about a pool used more than once in a same iRule ?
	# We will sanitisize it, that's it.

	for _ruleName in $( echo "${poolUsedInRules[@]}" | tr ' ' '\n' | sort | uniq )
	do	
		[ $DEBUG ] && echo "Now we are going to put pool start,end tuples in iRuleArrays"
		[ $DEBUG ] && echo "Pool is $_pName and tuples of it ${poolArray[$_pName]}"
		[ $DEBUG ] && echo "The iRule is $_ruleName ${iruleArray[$_ruleName]} before adding pool tuples"
		iruleArray[$_ruleName]+=';'
		iruleArray[$_ruleName]+=${poolArray[$_pName]}
		
		[ $DEBUG ] && echo "The iRule ( $_ruleName --> ${iruleArray[$_ruleName]} ) updated with pool ( $_pName --> ${poolArray[$_pName]} ) tuples"
	done
	
	unset _offset _ruleName _rule _pName _m	
}

extract_monitors(){
	# This function aims to find monitor definitions in pools which sent by any other functions
	# We need poolName and file name where we store the details of the monitor. That is it
  	local _poolName _monitorName _vsFileName
	declare -a _monitors
	_poolName="$1"
	_vsFileName="$2"

	[ $DEBUG ] && echo "DEBUG - extract_monitors called with ${_poolName}" # debug

	if [ $( echo ${poolArray[$_poolName]} | grep -E "[0-9]+,[0-9]+" ) ]; then
		# find used pool definitions in pool lines and list them
		read -a _monitors <<< $( sed -n "${poolArray[$_poolName]}p" ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" | grep monitor | tr ' ' '\n' | awk -F '/' '$0 ~ /\/[a-zA-Z0-9\-\_\.]+/ { print $NF } ' | sort -u | tr '\n' ' ' )
		#read -a _monitors <<< $( sed -n "${poolArray[$_poolName]}p" ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" | grep monitor | tr ' ' '\n' | awk -F '/' '$0 ~ /\/[a-zA-Z0-9\-\_\.]+/ { print $NF } ' | sort -u | tr '\n' ' ' )

		[ $DEBUG ] && echo -e "DEBUG - Monitor Count of (${_poolName}) is ${#_monitors[@]}" 
		[ $DEBUG ] && sed -n "${poolArray[$_poolName]}p" ${iAppFreeConfFile}
			
		for _monitorName in "${!_monitors[@]}"
		do
			case "${_monitors[$_monitorName]}" in
			
				tcp|gateway_icmp|http|https|udp)
				;;
				icmp|inband|real_server|snmp_dca)
				;;
				tcp_echo|tcp_half_open|http_head_f5)
				;;
				https_443|https_head_f5)
				;;
				*)		
				[ $DEBUG ] && echo -e "DEBUG - extract_monitors pool Name = $_poolName , Monitor Name = ${_monitors[$_monitorName]} , Monitor Start,End --> ${monitorArray[${_monitors[$_monitorName]}]}p"
				sed -n ${monitorArray[${_monitors[$_monitorName]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$_vsFileName"		
				;;		
			esac	
		done
		# Below lines adds support to call directly with the pool Start,End info instead of poolName. Also we check start and end line info stays inside of poolRange. 
	elif [ $( echo "$_poolName" | grep -E "[0-9]+,[0-9]+" ) ] && (( $( echo "$_poolName" | cut -d ',' -f 1 ) >= $( echo $poolRange | cut -d ',' -f 1) )) && (( $( echo "$_poolName" | cut -d ',' -f 2 ) <= $( echo $poolRange | cut -d ',' -f 2) )); then 
			read -a _monitors <<< $( sed -n "${_poolName}p" ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" | grep monitor | tr ' ' '\n' | awk -F '/' '$0 ~ /\/[a-zA-Z0-9\-\_\.]+/ { print $NF } ' | sort -u | tr '\n' ' ' )

			[ $DEBUG ] && echo -e "DEBUG - Monitor Count of (${_poolName}) is ${#_monitors[@]}" 

			for _monitorName in "${!_monitors[@]}"
			do		
				case "${_monitors[$_monitorName]}" in			
					tcp|gateway_icmp|http|https|udp)
					;;
					icmp|inband|real_server|snmp_dca)
					;;
					tcp_echo|tcp_half_open|http_head_f5)
					;;
					https_443|https_head_f5)
					;;
					*)
					
					[ $DEBUG ] && echo -e "DEBUG - extract_monitors pool Name or Tuple = $_poolName , Monitor Name = ${_monitors[$_monitorName]} , Monitor Start,End --> ${monitorArray[${_monitors[$_monitorName]}]}p"
					sed -n ${monitorArray[${_monitors[$_monitorName]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$_vsFileName"				
					;;				
				esac			
			done
	  fi  
	  unset _monitors
}

extract_poolsFromPolicy(){
# This function picks pools used in policies. No worry about pools used more than once.	
# extract_poolsFromPolicy "${policyNames[$_policy]}" "$vsFileName"

	local poolNames policyName _vsFileName monitorName monitorTuples
	policyName="$1"
	_vsFileName="$2"

	sed -n "${policyArray[$policyName]}p" "${iAppFreeConfFile}" | awk -F '/' '$0 ~ /[[:space:]]pool\s/ { print $3 }' | sort -u | \
	while read -r _line
	do
		[ $DEBUG ] && echo "DEBUG - 12 - Pool ${_line} found in Policy ${policyName}" # debug

		if [ $( echo ${poolArray[${_line}]} | grep -E "[0-9]+,[0-9]+" ) ]; then
			sed -n "${poolArray[${_line}]}p" "${iAppFreeConfFile}" | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$_vsFileName"

				## invoke "extract_monitos() functions here with pool name
				## it will take care of the rest of the problem.  
				extract_monitors "${_line}" "$_vsFileName"

				#~ if [ $( echo ${monitorName} | grep -E "\.app\/" ) ]; then
					#~ monitorName=$( echo ${monitorName}__APP | cut -d "/" -f2 )
				#~ fi
		else
			echo -e "###########################################\n## WARNING - This Policy has pool forwarding option but somehow\n## i could not find any tuples - ${poolArray[${_line}]} - ${policyName}\n###########################################" >> "$_vsFileName"
		fi
		monitorTuples=""
   done		
}

extract_iFiles(){
	# This function aims to extract ifile definitions in iRules.
	# basically we need to know irule name which contains "ifile get " word syntax and the "VsConfig" file name
	# and a final note. It is not easy to store any kind of file content here except the txt files. We need to store them carefully
	# because we are going to use those iFiles later. So, prepare to be amazed. While storing iFile contents here, we encode them with base64
	# Do not forget to decode them before use !!!    
	local ruleName ruleStartEnd _vsFileName
	if [ $# -ne 2 ]; then
		echo -e 'This function (extract_iFiles) need to know the name of iRule which we are looking for'
		return 30
	fi

	ruleName="$1"
	_vsFileName="$2"
	
	[ $DEBUG ] && echo "DEBUG - 6 - extract iFiles in rule -> $ruleName"
	
	ruleStartEnd=$( echo ${iruleArray[${ruleName}]} | cut -d ";" -f 1 )
	[ $DEBUG ] && echo "DEBUG - 7 - extract iFiles of this range -> $ruleStartEnd"
	_rule=$( sed -n "${ruleStartEnd}p" ${iAppFreeConfFile} )
	
	for k in "${!ltmiFileArray[@]}"
	do
		echo "$_rule" | grep -E "$k" > /dev/null 2>&1
 		if [ $? -eq 0 ]; then	
			[ $DEBUG ] && echo "DEBUG - 8 - iruleArray[ruleName] ${iruleArray[${ruleName}]}" # debug		
			echo "${ltmiFileArray[$k]}" | tr ';' '\n' | while read -r line
			do		
				case "$line" in
					N)
						echo -e "###########################################\n## ERROR - Can not locate the iFile  - ${line} \n###########################################" >> "$_vsFileName"
					
					;;
					[0-9]*,[0-9]*)
					
						[ $DEBUG ] && echo "DEBUG - 9 - iFile and sys file iFile to ${line}" # debug
						sed -n "${line}p" ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$_vsFileName"
					;;
					[a-zA-Z0-9\-\_\/\.]*)				
						[ $DEBUG ] && echo "DEBUG - 10 - iFile and sys file iFile contains - ${line}"
						echo "## $line ##" >> "$_vsFileName"
						echo "## -------------------------###################---------------------- ##" >> "$_vsFileName"
						echo "## ---------------###########   iFile START   ##########------------- ##" >> "$_vsFileName"
						echo "## ---------------######### Encoded with Base64 ########------------- ##" >> "$_vsFileName"
						echo "## -------------------------###################---------------------- ##" >> "$_vsFileName"
						cat "$line" | base64 >> "$_vsFileName"
						echo "" >> "$_vsFileName"
						echo "## -------------------------###################---------------------- ##" >> "$_vsFileName"
						echo "## ---------------###########    iFile END    ##########------------- ##" >> "$_vsFileName"
						echo "## -------------------------###################---------------------- ##" >> "$_vsFileName"					
					;;
					*)
						echo "DEBUG - 11 - ERROR - Could not get neither any information of Start,End of any tuple nor a file path - ${line}"
					;;
				esac
			done
		fi
	done
	return 0
}


### Main
get_virtualServer
get_virtAddr
get_iRules
get_policy
get_pools
get_iFiles
get_snatTranslation
get_snatPool
get_monitors
get_persistence
get_dataGroup
get_profile

for i in ${!virtServerArray[@]}
do

	vsFileName="VsConfigFile_${i}.txt"

	# vServer
	virt=$( sed -n ${virtServerArray[$i]}p ${iAppFreeConfFile} )
	echo "$virt" | grep -E "^\s{4}disabled" > /dev/null 2>&1 
	if [ $? -eq 0 ]; then
		vsFileName="VsConfigFile_${i}__DISABLED"
	fi
	[ $DEBUG ] && echo -e "virtual Server Start,End --> ${virtServerArray[$i]}p"
	sed -n ${virtServerArray[$i]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" > "$vsFileName"
	
	[ $DEBUG ] && echo -e "###########################" # DEBUG
	[ $DEBUG ] && echo -e "DEBUG - virt ${virt}\n\n" # DEBUG
	
	# Fallback Persist
	echo "${virt}" | grep -E "fallback-persistence " > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		fallback=$( echo "${virt}" | grep "fallback-persistence " | sed -e 's/fallback-persistence \/Common\///g' -e 's/^[[:space:]]*//g' )
		if [ $( echo $fallback | grep -E "\.app\/" ) ]; then 
			fallback=$( echo ${fallback}__APP | cut -d "/" -f 2 )
		fi
		fallbackLines=$( echo ${persistArray[$fallback]} )

		case $fallback in 

			cookie|dest_addr|hash)
			;;
			msrdp|sip_info|source_addr)
			;;
			ssl|universal)
			;;
			*)
			[ $DEBUG ] && echo -e "Fallback Persistence Start,End --> ${fallbackLines}p"
			sed -n ${fallbackLines}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
			;;

		esac
		
	fi
	
	# persistence
	persistence=$( echo "${virt}" | grep -nE "^\s\s\s\spersist\s{" | cut -d ":" -f 1 )
	if [ $persistence ]; then
		blockEnd=$( echo "${virt}" | tail -n +${persistence} |  grep -m 1 -nE "^\s{4}}$" | cut -d ":" -f1 )
		persistName=$( echo "${virt}" | sed -n ${persistence},$(( persistence + blockEnd -1))p | grep -E "\/Common\/[a-zA-Z0-9\_\-]+" | sed -e "s/\/Common\///g" -e "s/\ {//g" -e 's/^[[:space:]]*//g' )
		if [ $( echo $persistName | grep -E "\.app\/" ) ]; then # created by an iApp ?  
			persistName=$( echo ${persistName}__APP | cut -d "/" -f2 )
		fi
		
		case $persistName in 

			cookie|dest_addr|hash)
			;;
			msrdp|sip_info|source_addr)
			;;
			ssl|universal)
			;;
			*)
			[ $DEBUG ] && echo -e "Persistence Start,End --> ${persistArray[$persistName]}p"
			sed -n ${persistArray[$persistName]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
			;;

		esac
	fi
	unset blockEnd
	
	# pool
	echo "${virt}" | grep -E "^\s\s\s\spool\s\/" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		declare -a monitorName
		poolName=$( echo "$virt" | grep -E "^\s\s\s\spool\s\/" | sed -e "s/pool\ \/Common\///g" -e "s/^ *//g" )
		[ $DEBUG ] && echo "DEBUG - poolName ${poolName}" # DEBUG
		if [ $( echo $poolName | grep -E "\.app\/" ) ]; then
			poolName=$( echo ${poolName}__APP | cut -d "/" -f2 )
		fi
		[ $DEBUG ] && echo -e "Pool Start,End --> ${poolArray[$poolName]}p"
		sed -n ${poolArray[$poolName]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
		# Parse monitors as well
		#read -a monitorName <<< $( sed -n ${poolArray[$poolName]}p ${iAppFreeConfFile} | grep -E "^\s{4,12}monitor\s" | sed -e "s/^\s\{4,12\}monitor\s//g;s/min \(.*\) of //g" -e "s,{\|},,g" -e "s/\/Common\///g" -e "s/ and//g" -e "s/^[[:space:]]*//g" -e "s/ *$//g" | tr " " "\n" | sort -u | tr '\n' ' ' )
		read -a monitorName <<< $( sed -n ${poolArray[$poolName]}p ${iAppFreeConfFile} | grep -E "^\s{4,12}monitor\s" | sed -e "s/^\s\{4,12\}monitor\s//g;s/min \(.*\) of //g" -e "s,[{}],,g" -e "s/\/Common\///g" -e "s/ and//g" -e "s/^[[:space:]]*//g" -e "s/ *$//g" | tr " " "\n" | sort -u | tr '\n' ' ' )
		[ $DEBUG ] && echo -e "DEBUG - monitorName" && declare -p monitorName | tr ' ' '\n' # DEBUG
		for m in ${!monitorName[@]}
		do
			if [ $( echo ${monitorName[$m]} | grep -E "\.app\/" ) ]; then
				monitorName[$m]=$( echo ${monitorName[$m]}__APP | cut -d "/" -f2 )
			fi
			case "${monitorName[$m]}" in
			
				tcp|gateway_icmp|http|https|udp)
				;;
				icmp|inband|real_server|snmp_dca)
				;;
				tcp_echo|tcp_half_open|http_head_f5)
				;;
				https_443|https_head_f5)
				;;
				*)
				if [ ${monitorArray[${monitorName[$m]}]}p != "p" ]; then
					[ $DEBUG ] && echo -e "Monitor Start,End --> ${monitorArray[${monitorName[$m]}]}p"
					sed -n ${monitorArray[${monitorName[$m]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
				fi
				;;
				
			esac
			
		done
		
		unset monitorName
	fi
	

	# profiles
	profiles=$( echo "$virt" | grep -nE "^\s{4}profiles\s{" | cut -d ":" -f1 )
	echo "profiles begin count = $profiles"
	if [ "$profiles" ]; then 
		declare -a profileName
		blockEnd=$( echo "$virt" | tail -n +${profiles} | grep -m 1 -nE "^\s{4}}$" | cut -d ":" -f1 )
		echo "Block end = $blockEnd"
		read -a profileName <<< $( echo "$virt" | sed -n ${profiles},$(( profiles + blockEnd -1 ))p | grep -E "^\s{8}\/Common\/" | sed -e "s/\/Common\///g" -e "s/ [{}]//g" -e "s/^[[:space:]]*//g" \
			-e "/^tcp$/d" -e "/^http$/d" -e "/^https$/d" -e "/^serverssl-insecure-compatible$/d" -e "/^tcp-lan-optimized$/d" -e "/^tcp-wan-optimized$/d" -e "/^clientssl-insecure-compatible$/d" -e "/^websecurity$/d"| tr '\n' ' ' )
		#	read -a profileName <<< $( echo "$virt" | sed -n ${profiles},$(( profiles + blockEnd -1 ))p | grep -E "^\s{8}\/Common\/" | sed -e "s/\/Common\///g" -e "s/ { }\|{\| {//g" -e "s/^[[:space:]]*//g" \
		#	-e "/^tcp$/d" -e "/^http$/d" -e "/^https$/d" -e "/^serverssl-insecure-compatible$/d" -e "/^tcp-lan-optimized$/d" -e "/^tcp-wan-optimized$/d" -e "/^clientssl-insecure-compatible$/d" | tr '\n' ' ' )
		[ $DEBUG ] && echo -e "DEBUG - profileName" && declare -p profileName | tr ' ' '\n'
		
		for _p in "${!profileName[@]}"
		do
			if [ $( echo "${profileName[$_p]}" | grep -E "\.app\/" ) ]; then
				profileName[$_p]=$( echo ${profileName[$_p]}__APP | cut -d "/" -f2 )
			fi
            case "${profileName[$_p]}" in
				http|oneconnect|stream|statistics|webacceleration)
				;;
				ftp|dns|rtsp|icap|requestadapt|responseadapt|wan-optimized-compression)
				;;
				diameter|dhcpv4|dhcpv6|radiusLB|ipother|certificateauthority)
				;;
				classification|clientldap|clientssl|dnslogging|fasthttp|udp_dns)
				;;
				fastl4|fastL4|fix|gtp|html|httpcompression|http2|websocket|sctp|rtsp|rewrite)
				;;
				iiop|mblb|mssql|ntlm|ocsp-stapling-params|pptp|udp_gtm_dns|qoe)
				;;
				tcp|sip|rewrite|rtsp|sctp|smtps|socks|xml|vdi|?itrix-vdi)
				;;
				spdy|serverssl|stream|udp|xml|qoe|serverldap|ppp|rba|websso|certificateauthority)
				;;
				serverssl-insecure-compatible|clientssl-insecure-compatible|tcp-lan-optimized|tcp-wan-optimized)
				;;
				# Added the next two lines to skip processing of this default profile.
				bot_defense_asm_aggregated)
				;;
				*)
				[ $DEBUG ] && echo -e "Profile Start,End --> ${profileArray[${profileName[$_p]}]}p"
				## What if profile Start or End info does not exists ?
				if [ $( echo "${profileArray[${profileName[$_p]}]}" | grep -E "[0-9]+\,[0-9]+" ) ]; then
				    sed -n ${profileArray[${profileName[$_p]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
				else
					echo "ERROR - Profile Start or End or both are missing"
					echo -e "###########################################\n## ERROR - Some of the Profiles probably are missing - ${profileName[$_p]} \n###########################################" >> "$vsFileName"
				fi
				;;
			esac
		done
		unset profileName
	fi	
	
	# clone-pools
	clonePool=$( echo "$virt" | grep -nE "^\s{4}clone-pools\s{" | cut -d ":" -f1 )
	if [ $clonePool ]; then 
		declare -a clonePoolName
		clonePoolLines=$( echo "$virt" | tail -n +${clonePool} | grep -m 1 -nE "^\s{4}}$" | cut -d ":" -f1 )
		read -a clonePoolName <<< $( echo "$virt" | sed -n ${clonePool},$(( clonePool + clonePoolLines -1 ))p | grep -E "\/Common\/" | sed -e "s/\/Common\///g" \
		-e "s/ [{}]//g" -e "s/[[:space:]]*//g" | sort | uniq | tr '\n' ' ' )

		[ $DEBUG ] && echo -e "DEBUG - clonePoolName" && declare -p clonePoolName | tr ' ' '\n'
		
			for _c in ${!clonePoolName[@]} 
			do
				if [ $( echo ${clonePoolName[$_c]} | grep -E "\.app\/" ) ]; then
					clonePoolName[$_c]=$( echo ${clonePoolName[$_c]}__APP | cut -d "/" -f2 )
				fi
				[ $DEBUG ] && echo -e "clonePool Start,End --> ${poolArray[${clonePoolName[$_c]}]}p"
				sed -n ${poolArray[${clonePoolName[$_c]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
			
			done
		unset clonePoolName
	fi
	
	# iRules 
	rule=$( echo "$virt" | grep -m 1 -nE "^\s{4}rules\s{" | cut -d ":" -f1 )
	if [ $rule ]; then 
		declare -a ruleName
		ruleLines=$( echo "$virt" | tail -n +${rule} | grep -m 1 -nE "^\s{4}}$" | cut -d ":" -f1 )
		read -a ruleName <<< $( echo "$virt" | sed -n ${rule},$(( rule + ruleLines -1 ))p | grep -E "\/Common\/" | sed -e "s/\/Common\///g" -e "s/^[[:space:]]*//g" | tr '\n' ' ' )
		
		[ $DEBUG ] && echo -e "DEBUG - ruleName" &&  declare -p ruleName | tr " " "\n" # debug
		
			for _r in ${!ruleName[@]} ### 
			do
				case "${ruleName[$_r]}" in 
				
					_sys_*)
					;;
					*)
					[ $DEBUG ] && echo "Rule ( ${ruleName[$_r]} ) has tuple informations in array: ${iruleArray[${ruleName[$_r]}]}"
					ruleScale=$( echo ${iruleArray[${ruleName[$_r]}]} | cut -d ";" -f 1 ) # avoiding use to "${iruleArray[${ruleName[$_r]}]}" and use with delimited by ";" and ordered style because sometimes we store pool's start and end point info (Start,End) in this array. 
					echo "${iruleArray[${ruleName[$_r]}]}" | tr ";" "\n" | \
					while read -r _delim
					do
						[ $DEBUG ] && echo -e "Rule Name, Start,End --> ${ruleName[$_r]} ${_delim}p"
						sed -n ${_delim}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
						# Since we have pool start,end info, now we can try to have monitor definitions 
						[ $DEBUG ] && echo "Look for monitor definitons of ( $_delim )"
						extract_monitors "${_delim}" "$vsFileName" 
					done
					# This control points added to detect iFile definitions which is used by iRules.
					sed -n ${ruleScale}p ${iAppFreeConfFile} | grep -E "ifile get " > /dev/null 2>&1
					if [ $? -eq 0 ]; then
						extract_iFiles ${ruleName[$_r]} "$vsFileName"
					fi
					# what if there is a data-group in this iRule ?
					res=$( sed -n ${ruleScale}p ${iAppFreeConfFile} | grep -E "matchclass|class match" )
					###### Denis next 3
					if [ "$res" ]; then
						get_extraPools ${ruleScale}
					fi
					;;
				esac
			done
			
		unset ruleName
	fi

	# policy
	policy=$( echo "$virt" | grep -nE "\s{4}policies\s{" | cut -d ":" -f1 | awk '{ print $1 +1 }' )
	if [ $policy ]; then
		declare -a policNames
		policyEnd=$( echo "$virt" | tail -n +${policy} | grep -m 1 -nE "^\s{4}}" | cut -d ":" -f 1 )
		read -a policyNames <<< $( echo "$virt" | sed -n ${policy},$(( policy + policyEnd -2 ))p | sed -e 's,^[[:space:]]\+,,g' -e 's,/Common/,,g' -e 's, { },,g' -e 's, [{}],,g' | tr '\n' ' ' )
		#read -a policyNames <<< $( echo "$virt" | sed -n ${policy},$(( policy + policyEnd -2 ))p | sed -e 's,^[[:space:]]\+,,g' -e 's,/Common/,,g' -e 's, { },,g' -e 's, {\| },,g' | tr '\n' ' ' )
		
		[ $DEBUG ] && echo -e "DEBUG - policyNames" &&  declare -p policyNames | tr " " "\n" # debug 
		
		for _policy in "${!policyNames[@]}"
		do
			
			[ $DEBUG ] && echo -e "policy Start,End -> ${policyArray[${policyNames[$_policy]}]}" # debug 
			if [ $( echo "${policyArray[${policyNames[$_policy]}]}" | grep -E "[0-9]+\,[0-9]+" ) ]; then
				sed -n ${policyArray[${policyNames[$_policy]}]}p "${iAppFreeConfFile}" | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
				
				# what if this policy has forwarding option to forward traffic to specific pool/s ?
				# here is how to solve this isssue
				sed -n ${policyArray[${policyNames[$_policy]}]}p "${iAppFreeConfFile}" | grep -E "[[:space:]]+pool\s\/" > /dev/null 2>&1
				[ $? -eq 0 ] && extract_poolsFromPolicy "${policyNames[$_policy]}" "$vsFileName"
				
				
			else
				echo -e "Some of the policies can not parsed correctly - ${policyNames[$_policy]}"
				echo -e "###########################################\n## ERROR - Some of the policies can not parsed correctly - ${policyNames[$_policy]}\n###########################################\n" >> "$vsFileName" 
			fi
		
		done

	fi
	unset policyNames
	
	
	# SNAT pool
	snat=$( echo "$virt" | grep -nE "\s{4}source-address-translation\s{" | cut -d ":" -f 1 )
	if [ $snat ]; then
		declare -a snatPool
		snatBlock=$( echo "$virt" | tail -n +"${snat}" | grep -m 1 -nE "\s{4}}$" | cut -d ":" -f 1 )
		read -a snatPool <<< $( echo "$virt" | sed -n $(( snat +1 )),$(( snat + snatBlock -2 ))p | awk -F '/' '$1 ~ /pool/ { print $3 }' | tr '\n' ' ' )
		if [ ${#snatPool[@]} -ne 0 ]; then
			for _snat in "${!snatPool[@]}"
			do
				[ $DEBUG ] && echo -e "snat address translation Start,End -> ${snatPoolArray[${snatPool[$_snat]}]}" # debug
				sed -n ${snatPoolArray[${snatPool[$_snat]}]}p "${iAppFreeConfFile}" | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
			done
		fi
	
	fi
	unset snatPool
	unset snat
	
	# last-hop-pool 
	lastHopPool=$( echo "$virt" | grep -E "^\s{4}last-hop-pool" | awk -F '/' '{ print $3 }' )
	if [ ! -z "$lastHopPool" ]; then
		declare -a monitorName
		
		if [ $( echo "${poolArray[$lastHopPool]}" | grep -E "[0-9]+\,[0-9]+" ) ]; then
		
			[ $DEBUG ] && echo -e "DEBUG - last hop pool Start,End - ${poolArray[$lastHopPool]}"
			sed -n ${poolArray[$lastHopPool]}p "${iAppFreeConfFile}" | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
			
			read -a monitorName <<< $( sed -n ${poolArray[$lastHopPool]}p ${iAppFreeConfFile} | grep -E "^\s{4,12}monitor\s" | sed -e "s/^\s\{4,12\}monitor\s//g;s/min \(.*\) of //g" -e "s,[{}],,g" -e "s/\/Common\///g" -e "s/ and//g" -e "s/^[[:space:]]*//g" -e "s/ *$//g" | tr " " "\n" | sort | uniq | tr '\n' ' ' )
			#read -a monitorName <<< $( sed -n ${poolArray[$lastHopPool]}p ${iAppFreeConfFile} | grep -E "^\s{4,12}monitor\s" | sed -e "s/^\s\{4,12\}monitor\s//g;s/min \(.*\) of //g" -e "s,{\|},,g" -e "s/\/Common\///g" -e "s/ and//g" -e "s/^[[:space:]]*//g" -e "s/ *$//g" | tr " " "\n" | sort | uniq | tr '\n' ' ' )
			[ $DEBUG ] && echo -e "DEBUG - monitorName" && declare -p monitorName | tr ' ' '\n' # DEBUG
			for m in ${!monitorName[@]}
			do
				if [ $( echo ${monitorName[$m]} | grep -E "\.app\/" ) ]; then
				monitorName[$m]=$( echo ${monitorName[$m]}__APP | cut -d "/" -f2 )
				fi
				case "${monitorName[$m]}" in
			
					tcp|gateway_icmp|http|https|udp)
					;;
					icmp|inband|real_server|snmp_dca)
					;;
					tcp_echo|tcp_half_open|http_head_f5)
					;;
					https_443|https_head_f5)
					;;
					*)
					if [ ${monitorArray[${monitorName[$m]}]}p != "p" ]; then
						[ $DEBUG ] && echo -e "Monitor Start,End --> ${monitorArray[${monitorName[$m]}]}p"
						sed -n ${monitorArray[${monitorName[$m]}]}p ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
					fi
					;;
				
				esac
			
			done
		
		unset monitorName
			
		else
	
			echo "Looks like we have a pool which do not have valid starting or ending points - ${poolArray[$lastHopPool]}"
			echo -e "###########################################\n## ERROR - Looks like we have a pool which do not have\n## a valid starting, ending points - ${poolArray[$lastHopPool]} \n###########################################\n" >> "$vsFileName"
			
		fi
	fi
	
	
	# Virtual Address
	virtAddr=$( echo "$virt" | grep -E "^\s{4}destination " | awk -F '/' '{ print $3 }' | sed -e 's, destination ,,g' | awk -F ":" '{ print $1 }' )
	if [ ! -z "$virtAddr" ]; then
		
		[ $DEBUG ] && echo -e "DEBUG - Virtual IP Address Start,End - ${virtAddrArray[$virtAddr]}"
		sed -n "${virtAddrArray[$virtAddr]}p" ${iAppFreeConfFile} | sed -e "s/[\_a-zA-Z0-9\-]\+\.app\///g" >> "$vsFileName"
			
	
	fi
	
	unset virtAddr
	
	# Snat Translations
	# add codes here for Snat-Translations
done 


#initialize to exit

if [ -z $DEBUG ]; then 
	/bin/rm ${iAppFreeConfFile}
fi
unset virtServerArray
unset poolArray
unset monitorArray
unset policyArray
unset iruleArray
unset snatTranslationArray
unset snatPoolArray
unset dataGroupArray
unset persistArray
unset profileArray
unset sysiFileArray
unset sysSslCertArray
unset sysSslKeyArray

exit 0
