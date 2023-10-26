#!/bin/bash
dst="/mnt/media/tv/CBS Sunday Morning With Jane Pauley"
url=$(curl -s https://www.cbsnews.com/sunday-morning/ | grep -oP 'https://www.cbsnews.com/video/sunday-morning-full.*/')
echo "Downloading $url"
