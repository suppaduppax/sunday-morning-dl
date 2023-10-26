#!/bin/bash
to_timestamp() {
    date --date="${1}" +%s;
}

debug() {
    if [ "${DEBUG}" -eq 1 ]; then
        echo "${1}"
    fi
}

DEBUG=0

plex_server_url="http://plex.home"
plex_tv_shows_library_id=2
plex_tv_shows_library_name="TV Shows"
plex_token_file="plex-token.txt"

plex_token="$(cat $plex_token_file)"
tv_path="/mnt/media/tv"
tvdb_url="https://thetvdb.com/series/cbs-news-sunday-morning#seasons"
series_name="CBS Sunday Morning With Jane Pauley"
show_url="https://www.cbsnews.com/sunday-morning/"

echo="Grabbing url: ${show_url}"
vid_url="$(curl -s ${show_url} | grep -oP 'https://www.cbsnews.com/video/sunday-morning-full.*/')"
# returns https://www.cbsnews.com/video/sunday-morning-full-episode-10-22-2023/
echo "Found vid url: $vid_url"
vid_date_parse="$(echo ${vid_url} |  grep -oP '[0-9][0-9][-][0-9][0-9][-][0-9][0-9][0-9][0-9]')"
echo "Finding match for date: ${vid_date_parse}"
vid_date="${vid_date_parse//-/\/}"
vid_timestamp="$(to_timestamp $vid_date)"
vid_format="mp4"

VALID_ARGS=$(getopt -o irv --long plex-library-id,force-refresh-metadata,debug -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

eval set -- "$VALID_ARGS"
while [ : ]; do
  case "$1" in
    -i | --plex-library-id)
        shift
        echo "Querying plex server for '${plex_tv_shows_library_name}'"
        echo -n "id: "
        curl -sX GET "${plex_server_url}/library/sections/?X-Plex-Token=${plex_token}" | grep "${plex_tv_shows_library_name}" | grep -oP 'key="[0-9]+"' | grep -oP '".+"' | tr -d '"'
        skip=1
        ;;
    -r | --force-refresh-metadata)
        force_refresh_metadata=1
        shift
        ;;
    -v | --debug)
        DEBUG=1
        shift;
        ;;
    --) shift;
        break
        ;;
  esac
done

cr=1
ac=""
read_dom () {
    local IFS=\>
    read -d \< ENTITY CONTENT
    local ret=$?
    TAG_NAME=${ENTITY%% *}
    ATTRIBUTES=${ENTITY#* }
    return $ret
}

get_month () {
    if [[ "$1" == "January" ]]; then
        echo "01"
    elif [[ "$1" == "February" ]]; then
        echo "02"
    elif [[ "$1" == "March" ]]; then
        echo "03"
    elif [[ "$1" == "April" ]]; then
        echo "04"
    elif [[ "$1" == "May" ]]; then
        echo "05"
    elif [[ "$1" == "June" ]]; then
        echo "06"
    elif [[ "$1" == "July" ]]; then
        echo "07"
    elif [[ "$1" == "August" ]]; then
        echo "08"
    elif [[ "$1" == "September" ]]; then
        echo "09"
    elif [[ "$1" == "October" ]]; then
        echo "10"
    elif [[ "$1" == "November" ]]; then
        echo "11"
    elif [[ "$1" == "December" ]]; then
        echo "12"
    fi
}

parse_series () {
    if [[ "$TAG_NAME" == "table" ]] && [ "$intable" != 1 ]; then
        intable=1
    elif [ "$intable" == 1 ]; then
        if [[ "$TAG_NAME" == "/table" ]]; then
            season=""
            intable=0
        elif [[ "$TAG_NAME" == "tr" ]]; then
            intr=1
            intd=0
        elif [[ "$TAG_NAME" == "/tr" ]]; then
            intr=0
        fi

        if [ "$intr" == 1 ]; then
            if [[ "$TAG_NAME" == "td" ]]; then
                intd=$((intd+1))
            elif [ "$intd" == 1 ] && [[ "$TAG_NAME" == "a" ]]; then
                season="$(echo "${CONTENT}" | grep -oP "Season[ ][0-9]*")"
                link="$(echo $ATTRIBUTES | grep -oP 'href=\"[^\"]*\"' | grep -oP '\"https://.*\"' | tr -d '\"')"
            fi

            if [ "$intd" == 2 ] && [ ! -z "$season" ]; then
                date=$(echo "${CONTENT}" | grep -oP "[a-zA-Z]*[ ]*[0-9]*")
                month=$(echo $date | grep -oP "[a-zA-Z]*")
                year=$(echo $date | grep -oP "[0-9]*")
                if [ ! -z "${month}" ]; then
                    timestamp="$(to_timestamp "$(get_month $month)/01/$year")"
                    if [ -z "$cur_timestamp" ] || [ "$timestamp" -gt "$cur_timestamp" ]; then
                        if [ "$vid_timestamp" -gt "$timestamp" ]; then
                            cur_timestamp="$timestamp"
                            cur_link="$link"
                            cur_season="$season"
                        fi
                    fi
                fi
            fi
        fi
    fi
}

parse_season () {
    if [[ "$TAG_NAME" == "table" ]] && [ "$intable" != 1 ]; then
        intable=1
        intr=0
        intd=0
    fi

    if [ "$intable" == 1 ]; then
        if [[ "$TAG_NAME" == "/table" ]]; then
            intable=0
        elif [[ "$TAG_NAME" == "tr" ]]; then
            intr=1
            intd=0
        elif [[ "$TAG_NAME" == "/tr" ]]; then
            intr=0
        fi

        if [ "$intr" == 1 ]; then
            if [[ "$TAG_NAME" == "a" ]]; then
                ep_name="$(echo ${CONTENT} | xargs)"
                ep_date="$(echo ${ep_name} | grep -oP '[0-9]+/[0-9]+/[0-9]+')"
                if [[ "${ep_date}" == "${vid_date}" ]]; then
                    echo -n "matched to episode: "
                    echo "${ep_name}"
                    cur_season_ep="${season_ep}"
                    cur_ep_name="${ep_name}"
                fi
            elif [[ "$TAG_NAME" == "td" ]]; then
                intd=$((intd+1))
            elif [[ "$TAG_NAME" == "/td" ]]; then
                indiv=0
            fi

            if [ "$intd" -eq 1 ] && [[ "$TAG_NAME" == "td" ]]; then
                season_ep="$(echo ${CONTENT} | grep -oP 'S[0-9]+E[0-9]+')"
            elif [ "$intd" -eq 2 ]; then
                if [[ "$TAG_NAME" == "div" ]]; then
                    indiv=$((indiv+1))
                fi
            fi
        fi
    fi
}

if [ -z "${skip}" ] || [ "${skip}" -ne 1 ]; then
    while read_dom; do
        parse_series
    done  <<< "$(curl -s ${tvdb_url})"

    echo "Found episode season url: $cur_link"
    if [ ! -z "${cur_link}" ]; then
        while read_dom; do
            parse_season
        done  <<< "$(curl -s ${cur_link})"
    fi

    echo "--------------"
    dest="${tv_path}/${series_name}/${cur_season}/"
    series_path="${tv_path}/${series_name}"
    filename="${series_name} - ${cur_season_ep} - ${vid_date_parse////\-}"
    full_path_template="${dest}/${filename}"
    full_path="${full_path_template}.${vid_format}"

    echo "Filename: '${filename}'"

    if [ ! -d "${dest}" ]; then
        echo "Destination location does not exist. Creating '${dest}'"
        mkdir -p "${dest}"
    fi

    if [[ ! -f "${full_path}" ]]; then
        echo "Downloading from url: ${vid_url}"
        debug "yt-dlp -f \"${vid_format}\" -o \"${dest}/${filename}.%(ext)s\" \"${vid_url}\""
        ytdlp_status=$(yt-dlp -f "${vid_format}" -o "${dest}/${filename}.%(ext)s" "${vid_url}")

        if [ $? -ne 0 ]; then
            echo "An error has occured... printing log..."
            echo "${ytdlp_status}"
        elif [[ "${DEBUG}" -eq 1 ]]; then
            echo "${ytdlp_status}"
        fi

        if [[ ! -z $(echo "${ytdlp_status}" || grep "${full_path_template} has already been downloaded") ]]; then
            if [[ ! -z "${force_refresh_metadata}" && "${force_refresh_metadata}" -eq 1 ]]; then
                debug "curl -sX GET \"${plex_server_url}/library/sections/${plex_tv_shows_library_id}/refresh?path=${series_path// /%20}&X-Plex-Token=${plex_token}\""
                curl -sX GET "${plex_server_url}/library/sections/${plex_tv_shows_library_id}/refresh?path=${series_path// /%20}&X-Plex-Token=${plex_token}"
            fi
        else
            echo "File created: ${filename}.${vid_format}"
            echo -n "Refreshing metadata for series..."
            debug "curl -sX GET \"${plex_server_url}/library/sections/${plex_tv_shows_library_id}/refresh?path=${series_path// /%20}&X-Plex-Token=${plex_token}\""
            curl -sX GET "${plex_server_url}/library/sections/${plex_tv_shows_library_id}/refresh?path=${series_path// /%20}&X-Plex-Token=${plex_token}"
            echo "DONE!"
        fi
    else
        echo "File already exists: '${filename}'"
    fi
fi
