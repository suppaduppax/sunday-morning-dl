#!/bin/bash
USAGE="CBS Sunday Morning Automated Downloader
---------------------------------------
USAGE: ./cbs-sunday-morning-dl.sh [OPTIONS]

Options:
  -d, --dry-run                  Execute script without downloading any
                                 files
  -h, --help                     Print this usage screen
  -i, --plex-library-id          Query plex server for library id
  -l, --send-log                 Send the log file to discord after
                                 completion
  -r, --force-refresh-metadata   Refresh metadata regardless of outcome
  -v, --debug                    Enable verbose logging and output

For best results, add this script to crontab using: ./crontab.sh

See https://github.com/suppaduppax/sunday-morning-dl for more information."

DEBUG_LEVEL_INFO=0
DEBUG_LEVEL_DEBUG=1

LOG_FILE="log.txt"
LOG_DIR="logs"
MAX_LOG_FILES=25

SERIES_NAME="CBS Sunday Morning With Jane Pauley"
SERIES_URL="https://www.cbsnews.com/sunday-morning/"

DISCORD_WEBHOOK="$(cat discord-webhook.txt)"

PLEX_SERVER_URL="http://plex.home"
PLEX_LIBRARY_ID=2
PLEX_LIBRARY_NAME="TV Shows"
PLEX_LIBRARY_PATH="/mnt/media/tv"
PLEX_SERIES_PATH="${PLEX_LIBRARY_PATH}/${SERIES_NAME}"
PLEX_TOKEN_FILE="plex-token.txt"
PLEX_TOKEN="$(cat $PLEX_TOKEN_FILE)"

TVDB_URL="https://thetvdb.com/series/cbs-news-sunday-morning#seasons"

VIDEO_FORMAT="mp4"

# flag used to only print text and will skip any processing/downloading for opts such as --plex-library-id which will show the id number for the tv shows library and will skip download
QUERY_FLAG=0

OPT_DEBUG=0
OPT_SEND_LOG=0
OPT_DRY_RUN=0
OPT_REFRESH_METADATA=0

VALID_ARGS=$(getopt -o hlirdv --long help,send-log,plex-library-id,force-refresh-metadata,dry-run,debug -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

debug () {
    if [ "${1}" -eq "${DEBUG_LEVEL_DEBUG}" ]; then
        debug_tag="DEBUG"
    else
        debug_tag="INFO"
    fi

    if [ "${1}" -le ${OPT_DEBUG} ]; then
        echo "${2}"
        echo "[$debug_tag] [$(date +%m-%d-%y_%H:%M:%S)] ${2}" >> "${LOG_DIR}/${LOG_FILE}"
    fi
}

rotate_logs () {
    for (( i=$((MAX_LOG_FILES-2)); i>=1; i-- )); do
        cur_log_file="${LOG_DIR}/${LOG_FILE}.${i}"
        if [ -f "${cur_log_file}" ]; then
            mv "${cur_log_file}" "${LOG_DIR}/${LOG_FILE}.$((i+1))"
        fi
    done

    # move the curretn log file to *.1
    if [ -f "${LOG_DIR}/${LOG_FILE}" ]; then
        mv "${LOG_DIR}/${LOG_FILE}" "${LOG_DIR}/${LOG_FILE}.1"
    fi
}

to_timestamp () {
    date --date="${1}" +%s;
}

discord_msg () {
    curl -s -o /dev/null -F "payload_json={\"username\": \"Sunday Morning Bot\", \"content\": \"${1}\"}" "${DISCORD_WEBHOOK}"
}

discord_file () {
    curl -s -o /dev/null -F "file1=@${1}" -F "payload_json={\"username\": \"Sunday Morning Bot\", \"content\": \"${2}\"}" "${DISCORD_WEBHOOK}"
}

read_dom () {
    local IFS=\>
    read -d \< ENTITY CONTENT
    local ret=$?
    TAG_NAME=${ENTITY%% *}
    ATTRIBUTES=${ENTITY#* }
    return $ret
}

to_month_number () {
    if [[ "${1}" == "January" ]]; then
        echo "01"
    elif [[ "${1}" == "February" ]]; then
        echo "02"
    elif [[ "${1}" == "March" ]]; then
        echo "03"
    elif [[ "${1}" == "April" ]]; then
        echo "04"
    elif [[ "${1}" == "May" ]]; then
        echo "05"
    elif [[ "${1}" == "June" ]]; then
        echo "06"
    elif [[ "${1}" == "July" ]]; then
        echo "07"
    elif [[ "${1}" == "August" ]]; then
        echo "08"
    elif [[ "${1}" == "September" ]]; then
        echo "09"
    elif [[ "${1}" == "October" ]]; then
        echo "10"
    elif [[ "${1}" == "November" ]]; then
        echo "11"
    elif [[ "${1}" == "December" ]]; then
        echo "12"
    fi
}

parse_series () {
    if [[ "${TAG_NAME}" == "table" ]] && [ "${intable}" != 1 ]; then
        intable=1
    elif [ "${intable}" == 1 ]; then
        if [[ "${TAG_NAME}" == "/table" ]]; then
            season=""
            intable=0
        elif [[ "${TAG_NAME}" == "tr" ]]; then
            intr=1
            intd=0
        elif [[ "${TAG_NAME}" == "/tr" ]]; then
            intr=0
        fi

        if [ "$intr" == 1 ]; then
            if [[ "${TAG_NAME}" == "td" ]]; then
                intd=$((intd+1))
            elif [ "$intd" == 1 ] && [[ "${TAG_NAME}" == "a" ]]; then
                check_season="$(echo "${CONTENT}" | grep -oP "Season[ ][0-9]*")"
                check_season_url="$(echo ${ATTRIBUTES} | grep -oP 'href=\"[^\"]*\"' | grep -oP '\"https://.*\"' | tr -d '\"')"
            fi

            if [ "$intd" == 2 ] && [ ! -z "${check_season}" ]; then
                check_date=$(echo "${CONTENT}" | grep -oP "[a-zA-Z]*[ ]*[0-9]*")
                check_month=$(echo "${check_date}" | grep -oP "[a-zA-Z]*")
                check_year=$(echo "${check_date}" | grep -oP "[0-9]*")
                if [ ! -z "${check_month}" ]; then
                    check_timestamp="$(to_timestamp "$(to_month_number ${check_month})/01/${check_year}")"
                    if [ -z "${match_timestamp}" ] || [ "${check_timestamp}" -gt "${match_timestamp}" ]; then
                        debug ${DEBUG_LEVEL_DEBUG} "Found timestamp older than '${episode_timestamp}' > '${check_timestamp}(${check_month}/01/${check_year})'"
                        if [ "${episode_timestamp}" -gt "${check_timestamp}" ]; then
                            match_timestamp="${check_timestamp}"
                            match_season_url="${check_season_url}"
                            match_season="${check_season}"
                            debug ${DEBUG_LEVEL_DEBUG} "Replaced older timestamp: '${match_timestamp}' '${match_season}' '${match_season_url}'"
                        fi
                    fi
                fi
            fi
        fi
    fi
}

parse_season () {
    if [[ "${TAG_NAME}" == "table" ]] && [ "${intable}" != 1 ]; then
        intable=1
        intr=0
        intd=0
    fi

    if [ "${intable}" == 1 ]; then
        if [[ "${TAG_NAME}" == "/table" ]]; then
            intable=0
        elif [[ "${TAG_NAME}" == "tr" ]]; then
            intr=1
            intd=0
        elif [[ "${TAG_NAME}" == "/tr" ]]; then
            intr=0
        fi

        if [ "$intr" == 1 ]; then
            if [[ "${TAG_NAME}" == "a" ]]; then
                check_episode_name="$(echo ${CONTENT} | xargs | sed -e 's/\r//')"
                check_episode_date="$(echo ${check_episode_name} | grep -oP '[0-9]+/[0-9]+/[0-9]+')"
                if [[ "${check_episode_date}" == "${episode_date_slashes}" ]]; then
                    matched_season_and_episode="${check_season_and_episode}"
                    matched_episode_name="${check_episode_name}"
                fi
            elif [[ "${TAG_NAME}" == "td" ]]; then
                intd=$((intd+1))
            elif [[ "${TAG_NAME}" == "/td" ]]; then
                indiv=0
            fi

            if [ "$intd" -eq 1 ] && [[ "${TAG_NAME}" == "td" ]]; then
                check_season_and_episode="$(echo ${CONTENT} | grep -oP 'S[0-9]+E[0-9]+')"
            elif [ "$intd" -eq 2 ]; then
                if [[ "${TAG_NAME}" == "div" ]]; then
                    indiv=$((indiv+1))
                fi
            fi
        fi
    fi
}

# prepare logging
if [ ! -d "${LOG_DIR}" ]; then mkdir "${LOG_DIR}"; fi
log_files=(./${LOG_DIR}/${LOG_FILE}*)
if [ ${#log_files[@]} -le $MAX_LOG_FILES ]; then rotate_logs; fi
cat /dev/null >| "${LOG_DIR}/${LOG_FILE}"

# getopts processing
eval set -- "$VALID_ARGS"
while [ : ]; do
  case "${1}" in
    -i | --plex-library-id)
        shift
        debug ${DEBUG_LEVEL_INFO} "Querying plex server for '${PLEX_LIBRARY_NAME}'"
        debug 'id: $(curl -sX GET "${PLEX_SERVER_URL}/library/sections/?X-Plex-Token=${PLEX_TOKEN}" | grep "${PLEX_LIBRARY_NAME}" | grep -oP 'key="[0-9]+"' | grep -oP '".+"' | tr -d "\"")'
        QUERY_FLAG=1
        ;;
    -l | --send-log)
        shift
        OPT_SEND_LOG=1
        ;;
    -r | --force-refresh-metadata)
        OPT_REFRESH_METADATA=1
        shift
        ;;
    -d | --dry-run)
        OPT_DRY_RUN=1
        shift
        ;;
    -v | --debug)
        OPT_DEBUG=1
        shift;
        ;;
    -h | --help)
        shift;
        echo "${USAGE}"
        exit
        ;;
    --) shift;
        break
        ;;
  esac
done

# Grabs the url to the full episode
# returns https://www.cbsnews.com/video/sunday-morning-full-episode-10-22-2023/
debug ${DEBUG_LEVEL_INFO} "Scraping for episode url from: '${SERIES_URL}'"

episode_url="$(curl -s ${SERIES_URL} | grep -oP 'https://www.cbsnews.com/video/sunday-morning-full.*/')"
episode_date_dashes="$(echo ${episode_url} |  grep -oP '[0-9][0-9][-][0-9][0-9][-][0-9][0-9][0-9][0-9]')"
episode_date_slashes="${episode_date_dashes//-/\/}"
episode_timestamp="$(to_timestamp $episode_date_slashes)"

debug ${DEBUG_LEVEL_INFO} "Found full episode url: '${episode_url}'"
debug ${DEBUG_LEVEL_DEBUG} "Finding match for date: '${episode_date_dashes}'"
debug ${DEBUG_LEVEL_DEBUG} "Episode timetamp: '${episode_timestamp}'"

if [ "${QUERY_FLAG}" -ne 1 ]; then
    debug ${DEBUG_LEVEL_INFO} "Attempting to scrape TVDB to match season/episode with episode's date..."
    debug ${DEBUG_LEVEL_INFO} "Searching for season... "

    while read_dom; do
        parse_series
    done <<< "$(curl -s ${TVDB_URL})"

    if [ -z "${match_season_url}" ]; then
        debug ${DEBUG_LEVEL_INFO} "ERROR: Could not find matching url for date: '${episode_date_dashes}'"
        exit 1
    fi

    debug ${DEBUG_LEVEL_INFO} "Found url: '$match_season_url'"
    debug ${DEBUG_LEVEL_INFO} "Searching for specific episode... "

    if [ ! -z "${match_season_url}" ]; then
        while read_dom; do
            parse_season
        done  <<< "$(curl -s ${match_season_url})"
    fi

    if [ -z "${matched_episode_name}" ]; then
        debug ${DEBUG_LEVEL_INFO} "ERROR: Could not find matching episode for date: '${episode_date_dashes}'"
        exit 1
    elif [ -z "${matched_season_and_episode}" ]; then
        debug ${DEBUG_LEVEL_INFO} "ERROR: Could not find matching season_and_episode for date: '${episode_date_dashes}'"
        exit 1
    fi

    debug ${DEBUG_LEVEL_INFO} "Found episode name: '${matched_episode_name}'"
    debug ${DEBUG_LEVEL_INFO} "Using season/episode: '${matched_season_and_episode}'"

    season_path="${PLEX_SERIES_PATH}/${match_season}"
    base_filename="${SERIES_NAME} - ${matched_season_and_episode} - ${episode_date_dashes////\-}"
    filename="${base_filename}.${VIDEO_FORMAT}"
    full_path_template="${season_path}/${base_filename}"
    full_path="${full_path_template}.${VIDEO_FORMAT}"

    debug ${DEBUG_LEVEL_INFO} "Filename: '${base_filename}.${VIDEO_FORMAT}'"

    if [ ! -d "${season_path}" ]; then
        debug ${DEBUG_LEVEL_INFO} "Destination location does not exist. Creating '${season_path}'"
        mkdir -p "${season_path}"
    fi

    if [[ ! -f "${full_path}" ]]; then
        discord_msg "# New Episode Detected\nDownloading **${filename}**\n${episode_url}"
        debug ${DEBUG_LEVEL_INFO} "Downloading from url: ${episode_url}"
        debug ${DEBUG_LEVEL_DEBUG} "yt-dlp -o \"${full_path_template}.%(ext)s\" \"${episode_url}\""

        if [ ${OPT_DRY_RUN} -eq 0 ]; then
            echo "${OPT_DRY_RUN}"
            ytdlp_status=$(yt-dlp -o "${full_path_template}.%(ext)s" "${episode_url}")
        fi

        if [ $? -ne 0 ]; then
            debug ${DEBUG_LEVEL_INFO} "An error has occured... printing log..."
            debug ${DEBUG_LEVEL_INFO} "${ytdlp_status}"
            discord_file "${LOG_DIR}/${LOG_FILE}" "Attaching output file"
            exit 1
        else
            debug ${DEBUG_LEVEL_DEBUG} "${ytdlp_status}"
        fi

        if [[ ! -z $(echo "${ytdlp_status}" || grep "${full_path_template} has already been downloaded") ]]; then
            if [[ ! -z "${OPT_REFRESH_METADATA}" && "${OPT_REFRESH_METADATA}" -eq 1 ]]; then
                debug ${DEBUG_LEVEL_DEBUG} "curl -sX GET \"${PLEX_SERVER_URL}/library/sections/${PLEX_LIBRARY_ID}/refresh?path=${PLEX_SERIES_PATH// /%20}&X-Plex-Token=${PLEX_TOKEN}\""
                curl -sX GET "${PLEX_SERVER_URL}/library/sections/${PLEX_LIBRARY_ID}/refresh?path=${PLEX_SERIES_PATH// /%20}&X-Plex-Token=${PLEX_TOKEN}"
            fi
        else
            debug ${DEBUG_LEVEL_INFO} "File created: ${base_filename}.${VIDEO_FORMAT}"
            debug ${DEBUG_LEVEL_INFO} "Refreshing metadata for series..."
            debug ${DEBUG_LEVEL_DEBUG} "curl -sX GET \"${PLEX_SERVER_URL}/library/sections/${PLEX_LIBRARY_ID}/refresh?path=${PLEX_SERIES_PATH// /%20}&X-Plex-Token=${PLEX_TOKEN}\""
            curl -sX GET "${PLEX_SERVER_URL}/library/sections/${PLEX_LIBRARY_ID}/refresh?path=${PLEX_SERIES_PATH// /%20}&X-Plex-Token=${PLEX_TOKEN}"
            debug ${DEBUG_LEVEL_INFO} "DONE!"
            discord_msg "# Episode Imported\nEpisode has been downloaded and metadata refreshed\n**${filename}**"
        fi
    else
        debug ${DEBUG_LEVEL_INFO} "File already exists: '${filename}'"
    fi
fi

if [ "${OPT_SEND_LOG}" -eq 1 ]; then
    discord_file "${LOG_DIR}/${LOG_FILE}" "Attaching output file"
fi
