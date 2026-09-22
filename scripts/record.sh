#!/usr/bin/env bash
# AudioBridge - 用 ffmpeg + BlackHole 聚集裝置錄下會議的雙向音訊
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORDINGS_DIR="$ROOT_DIR/recordings"
RUN_DIR="$ROOT_DIR/.run"
PID_FILE="$RUN_DIR/record.pid"
CURRENT_FILE="$RUN_DIR/current_file"
CONFIG_FILE="$ROOT_DIR/.audiobridge.conf"
LOG_FILE="$RUN_DIR/ffmpeg.log"
PREV_OUTPUT_FILE="$RUN_DIR/prev_output"
MULTI_OUTPUT_DEVICE_NAME="Multi-Output Device"

SCREEN_PID_FILE="$RUN_DIR/screen.pid"
SCREEN_CURRENT_FILE="$RUN_DIR/screen_current_file"
SCREEN_LOG_FILE="$RUN_DIR/screen_ffmpeg.log"
SCREEN_PREV_OUTPUT_FILE="$RUN_DIR/screen_prev_output"

mkdir -p "$RECORDINGS_DIR" "$RUN_DIR"

usage() {
  cat <<EOF
用法: $(basename "$0") <command>

指令（純音訊錄音）:
  list              列出可用的 avfoundation 音訊裝置（用來找出聚集裝置的編號）
  setup             互動式設定要用來錄音的裝置
  start [格式]      開始錄音，格式可選 wav 或 m4a（預設 m4a）
  stop              停止目前的錄音
  status            顯示目前是否正在錄音

指令（螢幕錄影，畫面 + 系統音 + 麥克風）:
  screen list       列出可用的 avfoundation 視訊/螢幕擷取裝置
  screen setup      互動式設定要用來錄螢幕的裝置
  screen start      開始錄螢幕（輸出 mp4）
  screen stop       停止目前的螢幕錄影
  screen status     顯示目前是否正在錄螢幕
EOF
}

require_ffmpeg() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "找不到 ffmpeg，請先安裝：brew install ffmpeg" >&2
    exit 1
  fi
}

list_devices() {
  require_ffmpeg
  echo "可用的 avfoundation 音訊裝置："
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -A 20 "AVFoundation audio devices" || true
}

list_video_devices() {
  require_ffmpeg
  echo "可用的 avfoundation 視訊/螢幕擷取裝置："
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | sed -n '/AVFoundation video devices/,/AVFoundation audio devices/p' \
    | grep -v "AVFoundation audio devices" || true
}

setup_device() {
  list_devices
  echo
  read -rp "請輸入要用來錄音的『音訊輸入』裝置編號（通常是你設定好的聚集裝置）： " idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
    echo "錯誤：請輸入數字編號" >&2
    exit 1
  fi
  local existing_video=""
  if [[ -f "$CONFIG_FILE" ]]; then
    existing_video="$(grep -E '^VIDEO_DEVICE_INDEX=' "$CONFIG_FILE" || true)"
  fi
  {
    echo "AUDIO_DEVICE_INDEX=$idx"
    [[ -n "$existing_video" ]] && echo "$existing_video"
  } > "$CONFIG_FILE"
  echo "已儲存設定到 $CONFIG_FILE"
}

setup_screen() {
  list_video_devices
  echo
  read -rp "請輸入要用來錄螢幕的『視訊』裝置編號（通常是 Capture screen 0）： " vidx
  if ! [[ "$vidx" =~ ^[0-9]+$ ]]; then
    echo "錯誤：請輸入數字編號" >&2
    exit 1
  fi
  local existing_audio=""
  if [[ -f "$CONFIG_FILE" ]]; then
    existing_audio="$(grep -E '^AUDIO_DEVICE_INDEX=' "$CONFIG_FILE" || true)"
  fi
  if [[ -z "$existing_audio" ]]; then
    echo "尚未設定音訊裝置，先幫你設定一次："
    setup_device
    existing_audio="$(grep -E '^AUDIO_DEVICE_INDEX=' "$CONFIG_FILE" || true)"
  fi
  {
    echo "$existing_audio"
    echo "VIDEO_DEVICE_INDEX=$vidx"
  } > "$CONFIG_FILE"
  echo "已儲存設定到 $CONFIG_FILE"
}

switch_output_for_recording() {
  local prev_output_file="$1"
  if ! command -v SwitchAudioSource >/dev/null 2>&1; then
    echo "提醒：找不到 SwitchAudioSource，請手動把系統輸出切到「${MULTI_OUTPUT_DEVICE_NAME}」" >&2
    return
  fi
  local current
  current="$(SwitchAudioSource -c -t output)"
  if [[ "$current" == "$MULTI_OUTPUT_DEVICE_NAME" ]]; then
    return
  fi
  echo "$current" > "$prev_output_file"
  if SwitchAudioSource -s "$MULTI_OUTPUT_DEVICE_NAME" -t output 2>/dev/null; then
    echo "系統輸出已切到「${MULTI_OUTPUT_DEVICE_NAME}」（錄音結束會自動切回「${current}」）"
  else
    echo "提醒：找不到「${MULTI_OUTPUT_DEVICE_NAME}」輸出裝置，請確認已在音訊 MIDI 設定建立，並手動切換系統輸出" >&2
    rm -f "$prev_output_file"
  fi
}

restore_output_after_recording() {
  local prev_output_file="$1"
  if [[ ! -f "$prev_output_file" ]]; then
    return
  fi
  local prev
  prev="$(cat "$prev_output_file")"
  rm -f "$prev_output_file"
  if command -v SwitchAudioSource >/dev/null 2>&1 && SwitchAudioSource -s "$prev" -t output 2>/dev/null; then
    echo "系統輸出已切回「${prev}」"
  else
    echo "提醒：無法自動切回「${prev}」，請手動確認系統輸出" >&2
  fi
}

load_device() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "尚未設定錄音裝置，請先執行: $(basename "$0") setup" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  if [[ -z "${AUDIO_DEVICE_INDEX:-}" ]]; then
    echo "設定檔缺少 AUDIO_DEVICE_INDEX，請重新執行 setup" >&2
    exit 1
  fi
}

load_video_device() {
  load_device
  if [[ -z "${VIDEO_DEVICE_INDEX:-}" ]]; then
    echo "尚未設定螢幕擷取裝置，請先執行: $(basename "$0") screen setup" >&2
    exit 1
  fi
}

start_recording() {
  require_ffmpeg
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "已經在錄音中（PID $(cat "$PID_FILE")）" >&2
    exit 1
  fi

  load_device
  local fmt="${1:-m4a}"
  local timestamp
  timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
  local outfile="$RECORDINGS_DIR/${timestamp}.${fmt}"

  local codec_args=()
  case "$fmt" in
    m4a) codec_args=(-c:a aac -b:a 192k) ;;
    wav) codec_args=(-c:a pcm_s16le) ;;
    *)
      echo "不支援的格式：${fmt}（請用 wav 或 m4a）" >&2
      exit 1
      ;;
  esac

  switch_output_for_recording "$PREV_OUTPUT_FILE"

  echo "開始錄音 -> $outfile"
  # 聚集裝置給出的是 3 個原始聲道（BlackHole 左/右 + 麥克風單聲道），
  # 用 -ac 2 讓 ffmpeg 自動猜聲道配置會把麥克風那軌當成環繞聲道丟掉，
  # 所以這裡用 pan 明確把系統聲音（c0/c1）跟麥克風（c2）混進左右聲道。
  nohup ffmpeg -f avfoundation -i ":${AUDIO_DEVICE_INDEX}" \
    -filter_complex "[0:a]pan=stereo|c0=0.5*c0+0.7*c2|c1=0.5*c1+0.7*c2,alimiter=limit=0.9[aout]" \
    -map "[aout]" -ar 44100 "${codec_args[@]}" "$outfile" >"$LOG_FILE" 2>&1 &
  local pid=$!
  disown
  echo "$pid" > "$PID_FILE"
  echo "$outfile" > "$CURRENT_FILE"

  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "錄音啟動失敗，請檢查 $LOG_FILE" >&2
    rm -f "$PID_FILE" "$CURRENT_FILE"
    restore_output_after_recording "$PREV_OUTPUT_FILE"
    exit 1
  fi
  echo "錄音中（PID ${pid}）。停止請執行: $(basename "$0") stop"
}

stop_recording() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "目前沒有在錄音" >&2
    exit 1
  fi
  local pid
  pid="$(cat "$PID_FILE")"

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "找不到錄音程序（可能已經結束），清除狀態檔"
    rm -f "$PID_FILE" "$CURRENT_FILE"
    restore_output_after_recording "$PREV_OUTPUT_FILE"
    exit 0
  fi

  kill -INT "$pid"
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "警告：程序未正常結束，強制終止" >&2
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  restore_output_after_recording "$PREV_OUTPUT_FILE"

  if [[ -f "$CURRENT_FILE" ]]; then
    echo "錄音已停止，檔案位置：$(cat "$CURRENT_FILE")"
    rm -f "$CURRENT_FILE"
  else
    echo "錄音已停止"
  fi
}

status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "正在錄音（PID $(cat "$PID_FILE")）"
    [[ -f "$CURRENT_FILE" ]] && echo "檔案：$(cat "$CURRENT_FILE")"
  else
    echo "目前沒有在錄音"
  fi
}

start_screen_recording() {
  require_ffmpeg
  if [[ -f "$SCREEN_PID_FILE" ]] && kill -0 "$(cat "$SCREEN_PID_FILE")" 2>/dev/null; then
    echo "已經在錄螢幕中（PID $(cat "$SCREEN_PID_FILE")）" >&2
    exit 1
  fi

  load_video_device
  local timestamp
  timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
  local outfile="$RECORDINGS_DIR/${timestamp}_screen.mp4"

  switch_output_for_recording "$SCREEN_PREV_OUTPUT_FILE"

  echo "開始錄螢幕 -> $outfile"
  # 同一套聲道混音邏輯（見 start_recording 註解），另外用 videotoolbox
  # 硬體編碼成 H.264/mp4，檔案比 QuickTime 預設輸出小很多。
  nohup ffmpeg -f avfoundation -framerate 30 -i "${VIDEO_DEVICE_INDEX}:${AUDIO_DEVICE_INDEX}" \
    -filter_complex "[0:a]pan=stereo|c0=0.5*c0+0.7*c2|c1=0.5*c1+0.7*c2,alimiter=limit=0.9[aout]" \
    -map 0:v -map "[aout]" \
    -c:v h264_videotoolbox -b:v 6M -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 44100 \
    -movflags +faststart \
    "$outfile" >"$SCREEN_LOG_FILE" 2>&1 &
  local pid=$!
  disown
  echo "$pid" > "$SCREEN_PID_FILE"
  echo "$outfile" > "$SCREEN_CURRENT_FILE"

  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "錄螢幕啟動失敗，請檢查 $SCREEN_LOG_FILE" >&2
    rm -f "$SCREEN_PID_FILE" "$SCREEN_CURRENT_FILE"
    restore_output_after_recording "$SCREEN_PREV_OUTPUT_FILE"
    exit 1
  fi
  echo "錄螢幕中（PID ${pid}）。停止請執行: $(basename "$0") screen stop"
}

stop_screen_recording() {
  if [[ ! -f "$SCREEN_PID_FILE" ]]; then
    echo "目前沒有在錄螢幕" >&2
    exit 1
  fi
  local pid
  pid="$(cat "$SCREEN_PID_FILE")"

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "找不到錄螢幕程序（可能已經結束），清除狀態檔"
    rm -f "$SCREEN_PID_FILE" "$SCREEN_CURRENT_FILE"
    restore_output_after_recording "$SCREEN_PREV_OUTPUT_FILE"
    exit 0
  fi

  kill -INT "$pid"
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "警告：程序未正常結束，強制終止" >&2
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$SCREEN_PID_FILE"
  restore_output_after_recording "$SCREEN_PREV_OUTPUT_FILE"

  if [[ -f "$SCREEN_CURRENT_FILE" ]]; then
    echo "錄螢幕已停止，檔案位置：$(cat "$SCREEN_CURRENT_FILE")"
    rm -f "$SCREEN_CURRENT_FILE"
  else
    echo "錄螢幕已停止"
  fi
}

screen_status() {
  if [[ -f "$SCREEN_PID_FILE" ]] && kill -0 "$(cat "$SCREEN_PID_FILE")" 2>/dev/null; then
    echo "正在錄螢幕（PID $(cat "$SCREEN_PID_FILE")）"
    [[ -f "$SCREEN_CURRENT_FILE" ]] && echo "檔案：$(cat "$SCREEN_CURRENT_FILE")"
  else
    echo "目前沒有在錄螢幕"
  fi
}

case "${1:-}" in
  list) list_devices ;;
  setup) setup_device ;;
  start) start_recording "${2:-}" ;;
  stop) stop_recording ;;
  status) status ;;
  screen)
    case "${2:-}" in
      list) list_video_devices ;;
      setup) setup_screen ;;
      start) start_screen_recording ;;
      stop) stop_screen_recording ;;
      status) screen_status ;;
      *) usage; exit 1 ;;
    esac
    ;;
  *) usage; exit 1 ;;
esac
