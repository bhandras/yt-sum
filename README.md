# yt-sum

Summarize YouTube videos using their subtitles and the OpenAI API — directly from your terminal.

## Features

- Downloads English auto-generated subtitles (`.srt`) via `yt-dlp`
- Cleans and processes the subtitle text
- Sends the transcript to OpenAI's GPT model for summarization
- Prints the summary, token usage, and estimated cost
- Optional input trimming to fit model context

## Requirements

- `yt-dlp`
- `jq`
- `curl`
- OpenAI API key

## Usage

```bash
export OPENAI_API_KEY="sk-..."
./yt-sum.sh "https://www.youtube.com/watch?v=VIDEO_ID"
```

## Options
- `--trim <length>`: Trims the subtitle text to <length> characters before sending.

- `MODEL=gpt-4o` (or any valid model): Set a different OpenAI model via environment variable.


## Disclaimer

This script was vibe coded with the help of ChatGPT and is provided for educational and research purposes only.  Use it at your own risk. You are solely responsible for ensuring that your usage complies with all applicable laws, YouTube’s Terms of Service, and OpenAI’s usage policies. No guarantees are made regarding accuracy, reliability, or fitness for any purpose. The author assumes no liability for any misuse or resulting consequences.
