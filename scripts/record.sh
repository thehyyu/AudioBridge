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

mkdir -p "$RECORDINGS_DIR" "$RUN_DIR"

usage() {
  cat <<EOF
用法: $(basename "$0") <command>

指令:
  list              列出可用的 avfoundation 音訊裝置（用來找出聚集裝置的編號）
  setup             互動式設定要用來錄音的裝置
  start [格式]      開始錄音，格式可選 wav 或 m4a（預設 m4a）
  stop              停止目前的錄音
  status            顯示目前是否正在錄音
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
  echo "可用的 avfoundation 裝置："
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -A 20 "AVFoundation audio devices" || true
}

setup_device() {
  list_devices
  echo
  read -rp "請輸入要用來錄音的『音訊輸入』裝置編號（通常是你設定好的聚集裝置）： " idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
    echo "錯誤：請輸入數字編號" >&2
    exit 1
  fi
  echo "AUDIO_DEVICE_INDEX=$idx" > "$CONFIG_FILE"
  echo "已儲存設定到 $CONFIG_FILE"
}

switch_output_for_recording() {
  if ! command -v SwitchAudioSource >/dev/null 2>&1; then
    echo "提醒：找不到 SwitchAudioSource，請手動把系統輸出切到「${MULTI_OUTPUT_DEVICE_NAME}」" >&2
    return
  fi
  local current
  current="$(SwitchAudioSource -c -t output)"
  if [[ "$current" == "$MULTI_OUTPUT_DEVICE_NAME" ]]; then
    return
  fi
  echo "$current" > "$PREV_OUTPUT_FILE"
  if SwitchAudioSource -s "$MULTI_OUTPUT_DEVICE_NAME" -t output 2>/dev/null; then
    echo "系統輸出已切到「${MULTI_OUTPUT_DEVICE_NAME}」（錄音結束會自動切回「${current}」）"
  else
    echo "提醒：找不到「${MULTI_OUTPUT_DEVICE_NAME}」輸出裝置，請確認已在音訊 MIDI 設定建立，並手動切換系統輸出" >&2
    rm -f "$PREV_OUTPUT_FILE"
  fi
}

restore_output_after_recording() {
  if [[ ! -f "$PREV_OUTPUT_FILE" ]]; then
    return
  fi
  local prev
  prev="$(cat "$PREV_OUTPUT_FILE")"
  rm -f "$PREV_OUTPUT_FILE"
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

  switch_output_for_recording

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
    restore_output_after_recording
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
    restore_output_after_recording
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
  restore_output_after_recording

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

case "${1:-}" in
  list) list_devices ;;
  setup) setup_device ;;
  start) start_recording "${2:-}" ;;
  stop) stop_recording ;;
  status) status ;;
  *) usage; exit 1 ;;
esac
