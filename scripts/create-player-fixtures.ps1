param([Parameter(Mandatory=$true)][string]$Ffmpeg)
$ErrorActionPreference = 'Stop'
$fixturePath = Join-Path (Split-Path $PSScriptRoot -Parent) '.local\media-fixtures'
New-Item -ItemType Directory -Path $fixturePath -Force | Out-Null
& $Ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=640x360:rate=24' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 32 -threads 1 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 48 -c:a aac -b:a 96k -movflags +faststart (Join-Path $fixturePath 'video.mp4')
if ($LASTEXITCODE -ne 0) { throw 'MP4 generation failed' }
& $Ffmpeg -hide_banner -loglevel error -y -i (Join-Path $fixturePath 'video.mp4') -c copy -hls_time 4 -hls_list_size 0 -hls_playlist_type vod -hls_segment_filename (Join-Path $fixturePath 'seg%03d.ts') (Join-Path $fixturePath 'main.m3u8')
if ($LASTEXITCODE -ne 0) { throw 'HLS generation failed' }
