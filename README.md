# CBS Sunday Morning Downloader
Automatically download the latest episode of [CBS Sunday Morning](https://www.cbsnews.com/sunday-morning/) using [yt-dlp](https://github.com/yt-dlp/yt-dlp).

# Prerequisites
### Plex Token
Create a `plex-token.txt` file and place the Plex API token inside it

### Discord Webhook
Create a `discord-webhook.txt` file and place the web hook inside it

### Install yt-dlp
```bash
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp  # Make executable
```
> See https://github.com/yt-dlp/yt-dlp/wiki/Installation

# Crontab
This scripts works best when added to cron. That way it can search for the latest episode automatically. Simply run: 
```bash
./crontab
```
