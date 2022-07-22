#!/bin/bash

########## CONFIGURATIONS ##########
# Host on which qBittorrent runs
qbt_host="http://10.0.0.100"
# Port -> the same port that is inside qBittorrent option -> Web UI -> Web User Interface
qbt_port="8081"
# Username to access to Web UI
qbt_username="admin"
# Password to access to Web UI
qbt_password="adminadmin"

# Configure here your categories
category_list='movie,tv_show'

# Minimum seed time before deletion, expressed in seconds, for example 864000 means 10 days
min_seeding_time=864000
########## CONFIGURATIONS ##########

jq_executable="$(command -v jq)"
curl_executable="$(command -v curl)"

if [[ -z $jq_executable ]]; then
	echo -e "\n\e[0;91;1mFail on jq. Aborting.\n\e[0m"
	echo "You can find it here: https://stedolan.github.io/jq/"
	echo "Or you can install it with -> sudo apt install jq"
	exit 1
fi

if [[ -z $curl_executable ]]; then
	echo -e "\n\e[0;91;1mFail on curl. Aborting.\n\e[0m"
	echo "You can install it with -> sudo apt install curl"
	exit 2
fi

########## FUNCTIONS ##########
get_cookie () {
	qbt_cookie=$($curl_executable --silent --fail --show-error \
		--header "Referer: ${qbt_host}:${qbt_port}" \
		--cookie-jar - \
		--request GET "${qbt_host}:${qbt_port}/api/v2/auth/login?username=${qbt_username}&password=${qbt_password}")
}

get_torrent_list () {
	[[ -z "$qbt_cookie" ]] && get_cookie
	category="$1"
	torrents=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error \
		--cookie - \
		--request GET "${qbt_host}:${qbt_port}/api/v2/torrents/info?category=${category}")
}

delete_torrent () {
	[[ -z "$qbt_cookie" ]] && get_cookie
	hash="$1"
	torrents=$(echo "$qbt_cookie" | $curl_executable --silent --fail --show-error \
		--cookie - \
		--request GET "${qbt_host}:${qbt_port}/api/v2/torrents/delete?hashes=${hash}&deleteFiles=true")
}
########## FUNCTIONS ##########

if [ -n "$category_list" ]; then
	for j in ${category_list//,/ }; do

		get_torrent_list "${j}"

		torrent_name_list=$(echo "$torrents" | $jq_executable --raw-output '.[] .name')

		if [[ -z "$torrent_name_list" ]]; then
			echo "There's no categories named ${j}"
			continue
		else
			echo "Checking category ${j}:"
			tor_name_array=()
			tor_hash_array=()
			tor_path_array=()
			tor_seeding_time_array=()
			tor_progress_array=()
			while read -r single_found; do
				tor_name_array+=("$single_found")
				hash=$(echo "$torrents" | $jq_executable --raw-output --arg tosearch "$single_found" '.[] | select(.name == "\($tosearch)") | .hash')
				tor_hash_array+=("$hash")
				path=$(echo "$torrents" | $jq_executable --raw-output --arg tosearch "$single_found" '.[] | select(.name == "\($tosearch)") | .content_path')
				tor_path_array+=("$path")
				seeding_time=$(echo "$torrents" | $jq_executable --raw-output --arg tosearch "$single_found" '.[] | select(.name == "\($tosearch)") | .seeding_time')
				tor_seeding_time_array+=("$seeding_time")
				progress=$(echo "$torrents" | $jq_executable --raw-output --arg tosearch "$single_found" '.[] | select(.name == "\($tosearch)") | .progress')
				tor_progress_array+=("$progress")
			done <<< "$torrent_name_list"
		fi

		for i in "${!tor_name_array[@]}"; do
			echo "Analyzing torrent -> ${tor_name_array[$i]}"

			if awk "BEGIN {exit !(${tor_progress_array[$i]} < 1)}"; then
				printf "Torrent incomplete, nothing to do -> %0.3g%%\n" $(awk -v var="${tor_progress_array[$i]}" 'BEGIN{print var * 100}')
			else
				if [ "$(ls -l "${tor_path_array[$i]}" | awk '{print $2}')" = "1" ]; then
					echo "Found 1 hardlinks, checking seeding time:"
					if [ ${tor_seeding_time_array[$i]} -gt $min_seeding_time ]; then
						echo "I can delete this torrent, seeding time more than $min_seeding_time seconds"
						delete_torrent ${tor_hash_array[$i]}
					else
						echo "I can not delete this torrent, seeding time not meet -> ${tor_seeding_time_array[$i]}/${min_seeding_time}"
					fi
				else
					echo "More than 1 hardlinks found, nothing to do"
				fi
			fi
			echo "------------------------------"
		done
	done
	echo "Checking complete"
else
	echo "Categories list empty"
fi