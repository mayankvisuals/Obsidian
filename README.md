# Obsidian

Obsidian is a personal photo gallery app that uses your own Telegram bot as a storage backend.  
Photos are encrypted on-device before upload and can be browsed locally with fast indexing and thumbnails.

## Features
- Upload photos to your own Telegram bot
- Client-side encryption before upload
- Local gallery view with thumbnails
- No third-party cloud services involved

## How it works
1. Create your own Telegram bot using BotFather.
2. Paste your bot token inside the app.
3. Send one message to the bot to link your Telegram account.
4. Uploaded photos are encrypted locally and sent to your bot chat.
5. The app keeps a local index to display your gallery.

## Installation
Prebuilt APK files will be provided in the Releases section of this repository.  
Download the latest APK and install it on your Android device.  
You may need to allow installation from unknown sources.

## Notifications (Important)
The bot will send messages for every uploaded photo.  
If you find the notifications annoying, you can turn off notifications for the bot chat in Telegram.  
This is optional, but recommended to avoid constant notification spam.

## Security Notes
This project is experimental and not security-audited.  
The Telegram bot token is stored on-device. If your device is compromised, your data can be at risk.  
Telegram is used only as a transport and storage layer, not as a secure cloud service.

## Limitations
- Depends on Telegram bot availability and rate limits
- Not suitable for large-scale or production use
- No official backup or recovery mechanism if the bot token is lost

## Disclaimer
This is a personal project built for learning and experimentation.  
Use at your own risk.
