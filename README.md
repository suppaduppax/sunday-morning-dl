# sunday-morning-dl

# Prerequisites
Plex_Token \
Create a `plex-token.txt` file and place the Plex API token inside it

Discord Webhook
Create a `discord-webhook.txt ` file and place the web hook inside it

yt-dlp
Taken from [https://github.com/yt-dlp/yt-dlp/wiki/Installation]
```bash
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp  # Make executable
```

# Crontab
This scripts works best when added to cron. That way it can search for the latest episode. Simply run: 
```bash
./crontab
```
