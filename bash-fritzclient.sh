#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Jeroen Wiert Pluimers
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

## Configuration ideas based on https://github.com/mdmower/bash-no-ip-updater
## Fritz!Box code Based on config download example in https://home.debian-hell.org/dokuwiki/scripts/fritzbox.backup.mit.curl.bash

# Defines

CONFIGFILE="$( cd "$( dirname "$0" )" && pwd ).config"

if [ -e ${CONFIGFILE} ]; then
    source ${CONFIGFILE}
else
    echo "Config file not found."
    exit 1
fi

if [ -z "${FRITZBOX_USERNAME}" ]; then
   echo "FRITZBOX_USERNAME has not been set in the config file."
   exit 1
fi

if [ -z "${FRITZBOX_PASSWORD}" ]; then
   echo "FRITZBOX_PASSWORD has not been set in the config file."
   exit 1
fi

if [ -z "${FRITZBOX_URL}" ]; then
   echo "FRITZBOX_URL has not been set in the config file."
   exit 1
fi

if [ -z "${LOG_DIRECTORY}" ]; then
   echo "LOG_DIRECTORY has not been set in the config file."
   exit 1
fi

if [ -z "$*" ]; then
   echo "No commands given; valid commands are \"get-config\" and \"reboot\"."
   exit 1
fi

# http://stackoverflow.com/questions/255898/how-to-iterate-over-arguments-in-bash-script/255913#255913
for _PARAMETER in "$@"
do
    case ${_PARAMETER} in
        "get-config")
            ;;
        "reboot")
            ;;
        *)
            echo "unknown command ${_PARAMETER}; valid commands are \"get-config\" and \"reboot\"."
            exit 1
            ;;
    esac
done

USERAGENT="bash-fritzclient/0.1 "${FRITZBOX_USERNAME}

## if ever URI encoding is needed: https://github.com/jpluimers/bash-no-ip-updater/commit/754efa6d188d764309375918a06838b56458a512
# FRITZBOX_USERNAME=$(echo -ne ${FRITZBOX_USERNAME} | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
# FRITZBOX_PASSWORD=$(echo -ne ${FRITZBOX_PASSWORD} | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
# HTTP_USERNAME=$(echo -ne ${HTTP_USERNAME} | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
# HTTP_PASSWORD=$(echo -ne ${HTTP_PASSWORD} | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')

if [ ! -d ${LOG_DIRECTORY} ]; then
    mkdir -p ${LOG_DIRECTORY}
    if [ $? -ne 0 ]; then
        echo "Log directory could not be created or accessed."
        exit 1
    fi
fi

# remove extension: http://superuser.com/questions/634214/remove-a-file-extension-case-insentively-in-bash/634222#634222
LOG_FILENAME=$(basename "$0")
LOG_FILENAME=${LOG_DIRECTORY%}/${LOG_FILENAME%.*}.log
if [ ! -e ${LOG_FILENAME} ]; then
    touch ${LOG_FILENAME} $IPFILE
    if [ $? -ne 0 ]; then
        echo "Log file ${LOG_FILENAME} could not be created. Is the log directory ${LOG_DIRECTORY} writable?"
        exit 1
    fi
elif [ ! -w ${LOG_FILENAME} ]; then
    echo "Log file ${LOG_FILENAME} not writable."
    exit 1
fi

## DEBUG
[[ "$INSTRUMENTING" ]] && _CURL_VERBOSE="--verbose"
[[ "$INSTRUMENTING" ]] && builtin echo LOG_FILENAME=${LOG_FILENAME}
[[ "$INSTRUMENTING" ]] && builtin echo parameters: "$@"
## DEBUG

## methods

login-and-get-sid() {
    # get challenge key from FB
    FRITZBOX_CHALLENGE=$(curl --silent \
                              --insecure \
                              --user ${HTTP_USERNAME}:${HTTP_PASSWORD} \
                              "${FRITZBOX_URL}/login.lua" | \
                  egrep "^g_challenge|ready.onReady\(function" | \
                  tail -1 | \
                  awk --field-separator='"' '{ printf $2 }')
    [[ "$INSTRUMENTING" ]] && builtin echo FRITZBOX_CHALLENGE: $FRITZBOX_CHALLENGE

    # build md5 from challenge key and password
    _MD5=$(echo -n \
                ${FRITZBOX_CHALLENGE}"-"${FRITZBOX_PASSWORD} | \
            iconv -f ISO8859-1 \
                  -t UTF-16LE | \
            md5sum -b | \
            awk '{printf substr($0,1,32)}')
    [[ "$INSTRUMENTING" ]] && builtin echo _MD5: $_MD5

    # assemble challenge key and md5
    FRITZBOX_RESPONSE=${FRITZBOX_CHALLENGE}"-"${_MD5}
    [[ "$INSTRUMENTING" ]] && builtin echo FRITZBOX_RESPONSE: $FRITZBOX_RESPONSE

    # get sid for later use
    _LOCATION=$(curl --include \
                --silent \
                --insecure \
                --user ${HTTP_USERNAME}:${HTTP_PASSWORD} \
                --data 'response='${FRITZBOX_RESPONSE} \
                --data 'page=' \
                --data 'username='${FRITZBOX_USERNAME} \
                "${FRITZBOX_URL}/login.lua" | \
            grep "Location:")
    [[ "$INSTRUMENTING" ]] && builtin echo _LOCATION=${_LOCATION}
    # not trimming carriage return and newline leads to issues in curl, see https://gist.github.com/deanet/3427090#comment-1383976
    # the curl error you see is either of these:
    # "curl: (3) Illegal characters found in URL"
    # or in --verbose mode:
    # * Illegal characters found in URL
    # * Closing connection -1
    _SID=$(echo ${_LOCATION} | awk --field-separator='=' {' printf $2 '} | tr -d '\r\n')
    [[ "$INSTRUMENTING" ]] && builtin echo -e _SID: ${_SID}
}

get_config_fritzbox() {
    [[ "$INSTRUMENTING" ]] && builtin echo "Getting config from Fritz!Box"
    login-and-get-sid
    
    # get configuration from FB and write to STDOUT
    # enctype="multipart/form-data" means use `--form` http://superuser.com/questions/149329/what-is-the-curl-command-line-syntax-to-do-a-post-request/149335#149335
## POST this html form:
# <form action="/cgi-bin/firmwarecfg" method="POST" class="narrow" name="exportform" id="uiExportform" enctype="multipart/form-data" autocomplete="off">
# <input type="hidden" name="sid" value="547fb5e7b02c3548">
# <input type="text" name="ImportExportPassword" id="uiPass" autocomplete="off">
# <button type="submit" name="ConfigExport" onclick="onSaveBtn();">Save</button> </form>
    curl --silent \
         --insecure \
         --user ${HTTP_USERNAME}:${HTTP_PASSWORD} \
         --form 'sid='${_SID} \
         --form 'ImportExportPassword='${EXPORT_PASSWORD} \
         --form 'ConfigExport=' \
         "${FRITZBOX_URL}/cgi-bin/firmwarecfg"
}

reboot-fritzbox() {
    [[ "$INSTRUMENTING" ]] && builtin echo "Rebooting Fritz!Box"
    login-and-get-sid
    
    
    # no need to do GET request first as the POST will be initiating the reboot:
#    _URL="${FRITZBOX_URL}/system/reboot.lua?sid=${_SID}"
#    [[ "$INSTRUMENTING" ]] && builtin echo -e "Reboot GET request _URL ${_URL}"
#    curl --silent \
#         ${_CURL_VERBOSE} \
#         --insecure \
#         --user ${HTTP_USERNAME}:${HTTP_PASSWORD} \
#         "${_URL}"
    # This does not work either: go straight ahead with the POST, followed by following the 303 redirect:
## POST this html form:
#    <form action="/system/reboot.lua" method="POST">
#    <input type="hidden" name="sid" value="5abed5e90f9c7e99">
#    <button type="submit" name="reboot">Restart</button>
#    </form>
## Then a GET request with the redirect obtained from the POST Request:
# POST /system/reboot.lua HTTP/1.1
# Host: 192.168.71.1
# Content-Type: application/x-www-form-urlencoded
## Response:
# HTTP/1.1 303 See Other
# Location: http://192.168.71.1/reboot.lua?sid=a4adcf16de6cd803
# Keep-Alive: timeout=60, max=300
    # no enctype is equivalent to "application/x-www-form-urlencoded", see http://stackoverflow.com/questions/14063311/curl-post-data-binary-vs-form
    # the reason this does not work by itself is that newer Fritz!Box perform the actual reboot using Ajax requests.
    [[ "$INSTRUMENTING" ]] && builtin echo "Reboot POST request"
    _POST_RESULT=$(curl --silent \
                        ${_CURL_VERBOSE} \
                        --insecure \
                        --location \
                        --user ${HTTP_USERNAME}:${HTTP_PASSWORD} \
                        --data 'sid='${_SID} \
                        --data 'reboot=' \
                        "${FRITZBOX_URL}/system/reboot.lua" | \
                        grep "^ajaxGet")
    [[ "$INSTRUMENTING" ]] && builtin echo -e "Reboot POST request _POST_RESULT ${_POST_RESULT}"
    # the Ajax call is in a line like this in the script "ajaxGet("/reboot.lua?sid=3de2997257bcac19&ajax=1", callback_state);"
    # what actually happens is that the "ajaxGet" expande the parameters to be like this:
    # "http://192.168.71.1/reboot.lua?sid=3de2997257bcac19&ajax=1&xhr=1&t1433712887073=nocache"
    # the name of the "t######=nocache" is determined in http://192.168.71.1/js/ajax.js
    # from this piece of JavaScript: "t" + String((new Date()).getTime())
    # according to https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/getTime
    # this is the number of milliseconds since 1 January 1970 00:00:00 UTC.
    # this is doable from the shell: http://serverfault.com/questions/151109/how-do-i-get-current-unix-time-in-milliseconds-using-bash/151112#151112
    # echo $(($(date +%s%N)/1000000))
    _MILLISECONDS_FROM_EPOCH=$(echo $(($(date +%s%N)/1000000)))
    _URL="${FRITZBOX_URL}/reboot.lua?sid=${_SID}&ajax=1&xhr=1&t${_MILLISECONDS_FROM_EPOCH}=nocache"
    [[ "$INSTRUMENTING" ]] && builtin echo -e "Reboot AJAX request _URL ${_URL}"
    _JSON_RESULT=$(curl --silent \
                        ${_CURL_VERBOSE} \
                        --insecure \
                        --user ${HTTP_USERNAME}:${HTTP_PASSWORD} \
                        ${_URL})
    # the ajaxGet request will return a JSON result. When the reboot is allowed, this will be 
    # {"reboot_state":"0"}
    _EXPECTED_JSON_OK_RESULT="{\"reboot_state\":\"0\"}"
    [[ "$INSTRUMENTING" ]] && builtin echo -e "Reboot AJAX _JSON_RESULT ${_JSON_RESULT}"
    # string comparisons: http://stackoverflow.com/questions/4277665/how-do-i-compare-two-string-variables-in-an-if-statement-in-bash/4277753#4277753
    # if/condition/semicolon/then/fi construct is a convention: http://stackoverflow.com/questions/7985327/bash-convention-for-if-then/7986219#7986219
    # != not equals operator: http://unix.stackexchange.com/questions/67898/using-the-not-equal-operator-for-string-comparison/67900#67900
    if [ "${_JSON_RESULT}" != "${_EXPECTED_JSON_OK_RESULT}" ]; then
       echo "JSON resut ${_JSON_RESULT} is not the expected reboot result. Failed to initiate reboot."
       exit 1
    fi
    [[ "$INSTRUMENING" ]] && builtin echo "Reboot requests done; JSON result ${_JSON_RESULT} is OK."
}

## MAIN

for _PARAMETER in "$@"
do
    [[ "$INSTRUMENTING" ]] && builtin echo Command: "${_PARAMETER}"
    case ${_PARAMETER} in
        "get-config")
            LOGLINE="[$(date +'%Y-%m-%d %H:%M:%S')] Getting config from Fritz!Box ${FRITZBOX_URL}"
            echo $LOGLINE >> ${LOG_FILENAME}
            get_config_fritzbox
            ;;
        "reboot")
            LOGLINE="[$(date +'%Y-%m-%d %H:%M:%S')] Rebooting Fritz!Box ${FRITZBOX_URL}"
            echo $LOGLINE >> ${LOG_FILENAME}
            reboot-fritzbox
            ;;
    esac
done

exit 0