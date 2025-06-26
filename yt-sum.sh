#!/usr/bin/env bash

# Usage: ./yt-sum.sh <youtube_url>
# Requires: yt-dlp, curl, jq
# Requires: OPENAI_API_KEY env variable
# Optional: set MODEL (default: gpt-4o-mini), MAX_CHARS (default: 8000)

set -euo pipefail

YOUTUBE_URL="${1:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
MODEL="${MODEL:-gpt-4o-mini}"

TRIM_INPUT=false
TRIM_LENGTH=0

# Optional: --trim <number>
if [[ "${2:-}" == "--trim" && -n "${3:-}" && "${3}" =~ ^[0-9]+$ ]]; then
  TRIM_INPUT=true
  TRIM_LENGTH="$3"
fi

SYSTEM_PROMPT="You are a helpful assistant that summarizes transcripts."
USER_PROMPT="Analyze and summarize the transcript from this YouTube video. Extract and explain the main points, critical arguments, and conclusions. Emphasize clarity and logic in presenting the key takeaways."

if [[ -z "$YOUTUBE_URL" ]]; then
  echo "Usage: $0 <youtube_url>"
  exit 1
fi

if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "OPENAI_API_KEY not set"
  exit 1
fi

# Step 1: Get clean filename from video metadata
echo "Fetching video metadata..."
INFO=$(yt-dlp --skip-download --print "%(id)s|%(title)s" "$YOUTUBE_URL")
VIDEO_ID="${INFO%%|*}"
VIDEO_TITLE_RAW="${INFO#*|}"
VIDEO_TITLE_CLEAN=$(echo "$VIDEO_TITLE_RAW" | tr ' /:' '_' | tr -cd '[:alnum:]_')
SRT_FILENAME="${VIDEO_TITLE_CLEAN}_${VIDEO_ID}.en.srt"
SUMMARY_FILENAME="${VIDEO_TITLE_CLEAN}_${VIDEO_ID}_summary.txt"

echo "Downloading subtitles to: $SRT_FILENAME"
yt-dlp \
  --write-auto-subs \
  --sub-langs en \
  --convert-subs srt \
  --skip-download \
  -o "${VIDEO_TITLE_CLEAN}_${VIDEO_ID}.%(ext)s" \
  "$YOUTUBE_URL"

if [[ ! -f "$SRT_FILENAME" ]]; then
  echo "Subtitles not found: $SRT_FILENAME"
  exit 1
fi

# Step 2: Clean the subtitle text
echo "Cleaning subtitle text..."
SUB_TEXT=$(awk 'BEGIN{ORS=" "} /^[0-9]+$/{next} /^[0-9]{2}:[0-9]{2}/{next} NF' "$SRT_FILENAME" | tr -s ' ')

if $TRIM_INPUT; then
  TRIMMED_TEXT="${SUB_TEXT:0:$TRIM_LENGTH}"
  echo "Trimmed transcript to $TRIM_LENGTH characters"
else
  TRIMMED_TEXT="$SUB_TEXT"
  echo "Transcript length: ${#TRIMMED_TEXT} characters (not trimmed)"
fi

if [[ -z "$TRIMMED_TEXT" || "${#TRIMMED_TEXT}" -lt 100 ]]; then
  echo "Transcript is empty or too short to summarize (length: ${#TRIMMED_TEXT})"
  exit 1
fi

# Step 3: Safely encode JSON strings (escape quotes)
json_escape() {
  printf '%s' "$1" | jq -Rsa .
}

SYSTEM_ESCAPED=$(printf '%s' "$SYSTEM_PROMPT" | jq -Rsa .)
USER_ESCAPED=$(printf '%s' "$USER_PROMPT\n\n$TRIMMED_TEXT" | jq -Rsa .)

# Step 4: Call OpenAI API
echo "Summarizing with OpenAI ($MODEL)..."

RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "model": "$MODEL",
  "messages": [
    { "role": "system", "content": $SYSTEM_ESCAPED },
    { "role": "user", "content": $USER_ESCAPED }
  ],
  "temperature": 0.5
}
EOF
)

SUMMARY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')
TOKENS_TOTAL=$(echo "$RESPONSE" | jq -r '.usage.total_tokens // empty')
TOKENS_PROMPT=$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // empty')
TOKENS_COMPLETION=$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // empty')

# Step 5: Print or handle error
if [[ -z "$SUMMARY" ]]; then
  echo "Failed to extract summary. Full API response:"
  echo "$RESPONSE"
  exit 1
fi

# Step 6: Estimate cost (pricing per 1K tokens, in USD)
# Pricing taken from https://platform.openai.com/docs/pricing
COST=0
if [[ "$MODEL" == "gpt-4o" ]]; then
  COST=$(awk "BEGIN { printf \"%.6f\", ($TOKENS_PROMPT * 0.0025 + $TOKENS_COMPLETION * 0.0100) / 1000 }")
elif [[ "$MODEL" == "gpt-4o-mini" ]]; then
  COST=$(awk "BEGIN { printf \"%.6f\", ($TOKENS_PROMPT * 0.00015 + $TOKENS_COMPLETION * 0.00060) / 1000 }")
elif [[ "$MODEL" == "gpt-4-turbo" ]]; then
  COST=$(awk "BEGIN { printf \"%.6f\", ($TOKENS_PROMPT * 0.01 + $TOKENS_COMPLETION * 0.03) / 1000 }")
elif [[ "$MODEL" == "gpt-3.5-turbo" ]]; then
  COST=$(awk "BEGIN { printf \"%.6f\", ($TOKENS_PROMPT * 0.0005 + $TOKENS_COMPLETION * 0.0015) / 1000 }")
fi

# Step 7: Save summary to file
echo "Saving summary to: $SUMMARY_FILENAME"
{
  echo "Video Title: $VIDEO_TITLE_RAW"
  echo "Video URL: $YOUTUBE_URL"
  echo
  echo "$SUMMARY"
} > "$SUMMARY_FILENAME"

# Step 8: Print results
echo -e "\n=== SUMMARY: $VIDEO_TITLE_RAW ===\n$SUMMARY"
echo -e "\n--- Token usage ---"
echo "Prompt:    $TOKENS_PROMPT"
echo "Completion:$TOKENS_COMPLETION"
echo "Total:     $TOKENS_TOTAL"
echo "Estimated cost: \$$COST"

