#!/bin/bash

# Dependencies:
# This script requires ffmpeg (which includes ffprobe), jq, and bc to be installed on Ubuntu.
# Installation commands:
# sudo apt update && sudo apt install ffmpeg jq bc
# Documentation:
# ffmpeg: https://ffmpeg.org/documentation.html
# jq: https://jqlang.github.io/jq/
# bc: Standard Unix calculator
# ffprobe is used to probe the stream for video and audio details.
# ffmpeg is used to capture screenshots from the stream.
# jq is used to parse JSON output from ffprobe.
# bc is used for arithmetic calculations (e.g., sample rate conversion).
# The script assumes the m3u file is named 'iptv.m3u' in the current directory.
# It will create a root directory 'iptv_YYYYMMDD_HHMMSS' for each run.
# Inside the root directory:
# - results.csv (UTF-8 with BOM for Excel compatibility)
# - script.log
# - screenshots/ (directory with screenshots named ${counter}_${channel_name}.png)
# - skipped_lines.log (records skipped line numbers and contents for debugging)
# - mismatch.log (records mismatches between channel name resolution and actual resolution)
# - modified_iptv.m3u (modified m3u file with updated resolution tags and only connect_flag=true channels)
# The script processes each #EXTINF line followed by the URL.
# It attempts to connect to each URL with configurable timeouts.
# Video track format: e.g., "#1 h264, 1920x1080,25fps"
# Audio track format: e.g., "#1 mp2,2ch,48khz"
# Resolution flag: "高清" for 1920x1080, "4K" for 3840x2160 or 0x0, "标清" for 720x576 or 720x560, "其它" for other resolutions, "错误" if unable to connect or no video info.
# If connection fails, flag is 'false', and other fields are empty.
# Screenshot is taken at 5 seconds into the stream if possible.
# Timings: Logs timestamps for each step, durations for ffprobe, screenshot, per channel, and total execution.
# Statistics: Displays total channels, connect true/false counts, and resolution counts (高清,4K,标清,其它,错误).
# Fix for missing channels: Redirects ffprobe/ffmpeg stdin to /dev/null to prevent consuming m3u file lines.
# CSV encoding: UTF-8 with BOM for Chinese character compatibility in Excel.
# Debug enhancements: Line number tracking and logging of skipped lines to skipped_lines.log.
# New: Checks resolution mismatch with channel name and logs to mismatch.log.
# New: Modifies iptv.m3u to update resolution tags in channel names, outputs to modified_iptv.m3u.
# New: Removes channels with connect_flag=false (both #EXTINF and URL lines) from modified_iptv.m3u.

# set shell locale to UTF-8
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Configurable timeouts (in seconds)
FFPROBE_TIMEOUT=10
FFMPEG_TIMEOUT=10

# Check if required commands are installed
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "ffmpeg/ffprobe not found. Please install with: sudo apt update && sudo apt install ffmpeg"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "jq not found. Please install with: sudo apt update && sudo apt install jq"
    exit 1
fi
if ! command -v bc &> /dev/null; then
    echo "bc not found. Please install with: sudo apt update && sudo apt install bc"
    exit 1
fi

# Input m3u file
M3U_FILE="iptv.m3u"

# Current date and time for root directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Root directory
ROOT_DIR="iptv_${TIMESTAMP}"

# Create root directory
mkdir -p "$ROOT_DIR"

# Output CSV file
CSV_FILE="${ROOT_DIR}/results.csv"

# Screenshots directory
SCREENSHOT_DIR="${ROOT_DIR}/screenshots"

# Log file
LOG_FILE="${ROOT_DIR}/script.log"

# Skipped lines log file for debugging
SKIPPED_LINES_LOG="${ROOT_DIR}/skipped_lines.log"

# Mismatch log file for resolution mismatches
MISMATCH_LOG="${ROOT_DIR}/mismatch.log"

# Modified m3u file
MODIFIED_M3U="${ROOT_DIR}/modified_iptv.m3u"

# Redirect all output to log file and console
exec > >(tee "$LOG_FILE") 2>&1

# Total start time
total_start=$(date +%s)
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Starting script execution in directory $ROOT_DIR. Total start time epoch: $total_start"

# Create screenshots directory if it doesn't exist
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Creating screenshots directory: $SCREENSHOT_DIR"
mkdir -p "$SCREENSHOT_DIR"

# Initialize skipped lines log
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Initializing skipped lines log: $SKIPPED_LINES_LOG"
echo "Skipped Lines Log" > "$SKIPPED_LINES_LOG"
echo "----------------" >> "$SKIPPED_LINES_LOG"

# Initialize mismatch log
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Initializing mismatch log: $MISMATCH_LOG"
echo "Resolution Mismatch Log" > "$MISMATCH_LOG"
echo "-----------------------" >> "$MISMATCH_LOG"

# Preprocess m3u file to remove hidden characters and normalize
TEMP_FILE="${ROOT_DIR}/temp.m3u"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Preprocessing $M3U_FILE to remove hidden characters..."
tr -cd '\11\12\15\40-\176\200-\377' < "$M3U_FILE" | sed 's/^[ \t]*//;s/[ \t]*$//' > "$TEMP_FILE"

# Initialize CSV with UTF-8 BOM and headers
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Initializing CSV file with UTF-8 BOM: $CSV_FILE"
printf "\xEF\xBB\xBF" > "$CSV_FILE"
echo "编号,频道名称,video track,audio track,screenshot_name,连接flag,分辨率flag" >> "$CSV_FILE"

# Initialize modified m3u file with header
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Initializing modified m3u file: $MODIFIED_M3U"
grep '^#EXTM3U' "$TEMP_FILE" > "$MODIFIED_M3U"

# Counters for statistics
total_channels=0
true_count=0
false_count=0
hd_count=0
k4_count=0
sd_count=0
other_count=0
error_count=0

# Counter for numbering
counter=1

# Line number tracker
line_number=0

# Read the preprocessed temp m3u file line by line
while IFS= read -r line || [ -n "$line" ]; do
    ((line_number++))
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Line $line_number: $line (hex: $(echo -n "$line" | xxd -p | head -c 20)...)"

    # Skip empty or whitespace-only lines
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Skipped empty or whitespace line at $line_number: '$line'"
        echo "Line $line_number: $line" >> "$SKIPPED_LINES_LOG"
        continue
    fi

    # Check for #EXTINF with optional leading whitespace
    if [[ "$line" =~ ^[[:space:]]*#EXTINF ]]; then
        channel_start=$(date +%s)
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Processing channel $counter... Channel start time epoch: $channel_start"

        # Store original #EXTINF line for modified m3u
        original_extinf_line="$line"

        # Extract channel name robustly
        if [[ "$line" == *","* ]]; then
            channel_name=$(echo "$line" | cut -d',' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        else
            channel_name=$(echo "$line" | sed 's/^[[:space:]]*#EXTINF:[^ ]*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        if [ -z "$channel_name" ]; then
            channel_name="Unknown_Channel_$counter"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Warning: Could not extract channel name, using default: $channel_name"
        fi
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Channel name: $channel_name"

        # Read next line which should be the URL
        ((line_number++))
        IFS= read -r url || [ -n "$url" ]
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Line $line_number: $url (hex: $(echo -n "$url" | xxd -p | head -c 20)...)"

        # Check if URL is valid (starts with http)
        if [[ ! "$url" =~ ^http ]]; then
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Invalid or missing URL for $channel_name: '$url'. Skipping channel."
            echo "Line $line_number: $url" >> "$SKIPPED_LINES_LOG"
            continue
        fi

        # Screenshot name without timestamp
        screenshot_name="${counter}_${channel_name}.png"
        screenshot_path="${SCREENSHOT_DIR}/${screenshot_name}"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Screenshot name: $screenshot_name"

        # Initialize variables
        video_track=""
        audio_track=""
        connect_flag="false"
        resolution_flag="错误"  # Default to "错误" if unable to connect

        # Run ffprobe with stdin redirected to /dev/null
        probe_start=$(date +%s)
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Executing ffprobe. Start time epoch: $probe_start"
        probe_command="timeout $FFPROBE_TIMEOUT ffprobe -v quiet -print_format json -show_streams \"$url\" 2>/dev/null < /dev/null"
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ffprobe command: $probe_command"
        probe_output=$(eval "$probe_command")
        probe_end=$(date +%s)
        probe_duration=$((probe_end - probe_start))
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ffprobe execution completed. End time epoch: $probe_end. Duration: $probe_duration seconds."

        if [ $? -eq 0 ] && [ -n "$probe_output" ]; then
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Parsing ffprobe output..."

            # Parse video track
            video_codec=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name' | head -n1)
            video_width=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .width' | head -n1)
            video_height=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .height' | head -n1)
            video_fps=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate' | head -n1 | cut -d'/' -f1)
            if [ -n "$video_codec" ] && [ -n "$video_width" ] && [ -n "$video_height" ] && [ -n "$video_fps" ]; then
                video_track="#1 $video_codec, ${video_width}x${video_height},${video_fps}fps"

                # Set resolution flag
                resolution_flag="其它"
                if [ "$video_width" = "1920" ] && [ "$video_height" = "1080" ]; then
                    resolution_flag="高清"
                elif { [ "$video_width" = "3840" ] && [ "$video_height" = "2160" ]; } || { [ "$video_width" = "0" ] && [ "$video_height" = "0" ]; }; then
                    resolution_flag="4K"
                elif [ "$video_width" = "720" ] && { [ "$video_height" = "576" ] || [ "$video_height" = "560" ]; }; then
                    resolution_flag="标清"
                fi
            fi
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Video track: $video_track"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Resolution flag: $resolution_flag"

            # Parse audio track
            audio_codec=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name' | head -n1)
            audio_channels=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="audio") | .channels' | head -n1)
            audio_sample_rate=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="audio") | .sample_rate' | head -n1)
            audio_ch="2ch" # Default to 2ch, adjust if needed
            if [ "$audio_channels" = "1" ]; then audio_ch="1ch"; elif [ "$audio_channels" = "2" ]; then audio_ch="2ch"; fi
            if [ -n "$audio_sample_rate" ] && [ "$audio_sample_rate" != "null" ]; then
                audio_khz=$(echo "scale=0; $audio_sample_rate / 1000" | bc)khz
            else
                audio_khz=""
            fi
            if [ -n "$audio_codec" ] && [ -n "$audio_ch" ] && [ -n "$audio_khz" ]; then
                audio_track="#1 $audio_codec,${audio_ch},${audio_khz}"
            fi
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Audio track: $audio_track"

            # If we have video info, attempt screenshot
            if [ -n "$video_track" ]; then
                screenshot_start=$(date +%s)
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] Executing screenshot. Start time epoch: $screenshot_start"
                screenshot_command="timeout $FFMPEG_TIMEOUT ffmpeg -nostdin -v quiet -ss 5 -i \"$url\" -frames:v 1 -update 1 \"$screenshot_path\" 2>/dev/null < /dev/null"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] Screenshot command: $screenshot_command"
                eval "$screenshot_command"
                screenshot_end=$(date +%s)
                screenshot_duration=$((screenshot_end - screenshot_start))
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] Screenshot execution completed. End time epoch: $screenshot_end. Duration: $screenshot_duration seconds."
                if [ $? -eq 0 ] && [ -f "$screenshot_path" ]; then
                    connect_flag="true"
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Screenshot saved successfully."
                else
                    echo "[$(date +"%Y-%m-%d %H:%M:%S")] Screenshot capture failed."
                    resolution_flag="错误"
                fi
            else
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] No video track info, skipping screenshot."
                resolution_flag="错误"
            fi
        else
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] ffprobe failed or no output."
            resolution_flag="错误"
        fi

        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Connect flag: $connect_flag"

        # Check for resolution mismatch
        name_resolution=""
        if [[ "$channel_name" =~ \[高清\] ]]; then
            name_resolution="高清"
        elif [[ "$channel_name" =~ \[4K\] ]]; then
            name_resolution="4K"
        elif [[ "$channel_name" =~ \[标清\] ]]; then
            name_resolution="标清"
        fi
        if [ -n "$name_resolution" ] && [ "$name_resolution" != "$resolution_flag" ]; then
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Resolution mismatch at line $((line_number-1)): Channel name '$channel_name' indicates '$name_resolution', but actual resolution is '$resolution_flag'"
            echo "Line $((line_number-1)): Channel '$channel_name', Name Resolution: '$name_resolution', Actual Resolution: '$resolution_flag'" >> "$MISMATCH_LOG"
        fi

        # Update channel name for modified m3u
        new_channel_name="$channel_name"
        if [[ "$channel_name" =~ \[高清\]|\[4K\]|\[标清\] ]]; then
            new_channel_name=$(echo "$channel_name" | sed 's/\[高清\]//g;s/\[4K\]//g;s/\[标清\]//g')
            new_channel_name=$(echo "$new_channel_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            new_channel_name="${new_channel_name}[$resolution_flag]"
        elif [ "$resolution_flag" != "错误" ]; then
            new_channel_name="${channel_name}[$resolution_flag]"
        fi
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Updated channel name for m3u: $new_channel_name"

        # Append to CSV
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Appending to CSV: $counter,\"$channel_name\",\"$video_track\",\"$audio_track\",\"$screenshot_name\",$connect_flag,$resolution_flag"
        echo "$counter,\"$channel_name\",\"$video_track\",\"$audio_track\",\"$screenshot_name\",$connect_flag,$resolution_flag" >> "$CSV_FILE"

        # Append to modified m3u only if connect_flag is true
        if [ "$connect_flag" = "true" ]; then
            new_extinf_line=$(echo "$original_extinf_line" | sed "s/,.*$/,${new_channel_name}/")
            echo "$new_extinf_line" >> "$MODIFIED_M3U"
            echo "$url" >> "$MODIFIED_M3U"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Appended to modified m3u: $new_extinf_line"
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Appended to modified m3u: $url"
        else
            echo "[$(date +"%Y-%m-%d %H:%M:%S")] Skipped channel '$channel_name' from modified m3u due to connect_flag=false"
        fi

        # Update counters
        ((total_channels++))
        if [ "$connect_flag" = "true" ]; then
            ((true_count++))
        else
            ((false_count++))
        fi
        case "$resolution_flag" in
            "高清") ((hd_count++)) ;;
            "4K") ((k4_count++)) ;;
            "标清") ((sd_count++)) ;;
            "其它") ((other_count++)) ;;
            "错误") ((error_count++)) ;;
        esac

        # Channel end
        channel_end=$(date +%s)
        channel_duration=$((channel_end - channel_start))
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Completed processing channel $counter. End time epoch: $channel_end. Channel duration: $channel_duration seconds."
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] ----------------------------------------"

        # Increment counter
        ((counter++))
    else
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] Skipped non-EXTINF line at $line_number: '$line'"
        echo "Line $line_number: $line" >> "$SKIPPED_LINES_LOG"
    fi
done < "$TEMP_FILE"

# Cleanup temp file
rm "$TEMP_FILE"

# Total end
total_end=$(date +%s)
total_duration=$((total_end - total_start))
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Processing complete. Results in $CSV_FILE, screenshots in $SCREENSHOT_DIR, log in $LOG_FILE, skipped lines in $SKIPPED_LINES_LOG, mismatch log in $MISMATCH_LOG, modified m3u in $MODIFIED_M3U"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Script execution ended. End time epoch: $total_end. Total duration: $total_duration seconds."

# Display statistics
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Statistics:"
echo "Total channels: $total_channels"
echo "Connect true: $true_count"
echo "Connect false: $false_count"
echo "高清: $hd_count"
echo "4K: $k4_count"
echo "标清: $sd_count"
echo "其它: $other_count"
echo "错误: $error_count"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] End of script."