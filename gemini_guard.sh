#!/bin/bash
# ============================================================
# gemini_guard.sh — Pixel Gemini 防隐藏 一键开关
#
# 问题: 在部分国家/地区, 系统组件 Google Partner Setup
#       (com.google.android.partnersetup) 会按服务端下发的地区策略,
#       反复 pm disable Gemini 及其他 Google 应用 (每次开机/配置同步/
#       SIM 变化/应用更新后重新生效), 桌面图标随之消失。
#
# 方案: 不动系统文件、不整包禁用, 只禁用 PartnerSetup 内部 8 个
#       "重禁入口" (5 个广播接收器 + 3 个 JobService, 反编译调用链实证),
#       RLZ provider/遥测、phenotype 元数据服务等其余功能原样保留。
#       纯包管理器配置层操作, 无需 root/框架。
#
# 用法:
#   ./gemini_guard.sh on       恢复所有被策略禁用的 Google 应用 + 禁用 6 个重禁入口
#   ./gemini_guard.sh off      防护关闭: 6 个入口全部恢复原状 (应用保持启用)
#   ./gemini_guard.sh status   查看当前状态
#
# 环境变量:
#   SERIAL=设备序列号     多台设备时指定目标 (单台自动识别)
#   ADB=adb路径           默认取 PATH 中的 adb
#   PKG=包名              默认 com.google.android.partnersetup
#   GEMINI=包名           默认 com.google.android.apps.bard
#
# 依赖: adb (手机开启 USB 调试)。组件状态存于系统 package-restrictions,
#       重启不丢; OTA 大版本后建议 status 复核一次。
# ============================================================
set -u
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"   # Git Bash 路径转换保护 (其他平台无副作用)

ADB="${ADB:-adb}"
PKG="${PKG:-com.google.android.partnersetup}"
GEMINI="${GEMINI:-com.google.android.apps.bard}"
# 反编译交叉引用实证: 禁用 API (setApplicationEnabledSetting /
# setComponentEnabledSetting) 的可达路径 = 5 个广播接收器 + 3 个 JobService。
# RLZ 遥测组件 (RlzPingBroadcastReceiver/RlzPingJobService) 代码上与隐藏无关, 保留。
COMPONENTS=(
  "$PKG/.BootReceiver"
  "$PKG/.GservicesChangedReceiver"
  "$PKG/.PhoneStateReceiver"
  "$PKG/.PhenotypeBroadcastReceiver"
  "$PKG/com.google.android.libraries.phenotype.client.stable.PhenotypeUpdateBackgroundBroadcastReceiver"
  "$PKG/.InstalledAppJobService"
  "$PKG/.AppHidingJobService"
  "$PKG/.PhenotypeJobService"
)

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

pick_serial() {
  [ -n "${SERIAL:-}" ] && { echo "$SERIAL"; return; }
  local lines n
  lines=$("$ADB" devices | tail -n +2 | grep -E 'device$' | awk '{print $1}')
  n=$(echo "$lines" | grep -c .)
  if [ "$n" -eq 1 ]; then echo "$lines"; return; fi
  echo "[!] $([ "$n" -eq 0 ] && echo '没有在线设备' || echo '多台设备, 请用 SERIAL=xxx 指定'):" >&2
  "$ADB" devices >&2
  exit 2
}

SER=$(pick_serial) || exit 2
# Windows adb 高频调用偶发空返回/服务抖动, 失败自动重试
devsh() {
  local i out=""
  for i in 1 2 3 4; do
    out=$("$ADB" -s "$SER" shell -T "$*" 2>&1 | tr -d '\r')
    case "$out" in
      ""|*"adb:"*|*"daemon not"*|*"device offline"*|*"not found"*) sleep 0.$((i*3)); continue ;;
      *) printf '%s\n' "$out"; return 0 ;;
    esac
  done
  printf '%s\n' "$out"
  return 1
}

refresh_disabled() {
  DISABLED=$(devsh "dumpsys package $PKG" | sed -n '/disabledComponents:/,/enabledComponents:/p')
}
is_disabled() { echo "$DISABLED" | grep -qF "$1"; }
# "pkg/.Cls" -> "pkg.Cls"; "pkg/a.b.Cls" -> "a.b.Cls"  (dumpsys 列出的是去包前缀类名)
class_of() {
  local c="${1#"$PKG"/}"
  case "$c" in
    .*) echo "$PKG$c";;
    *)  echo "$c";;
  esac
}

pkg_state() {
  devsh "dumpsys package $1" | grep -m1 'User 0:' | sed -E 's/.* enabled=([0-9]+).*/\1/'
}
state_name() {
  case "$1" in
    0) echo "默认(启用)";; 1) echo "启用";; 2) echo "禁用(系统)";;
    3) echo "禁用(用户)";; 4) echo "禁用直到使用";; *) echo "未知($1)";;
  esac
}
gemini_state() { pkg_state "$GEMINI"; }
gemini_caller() {
  devsh "dumpsys package $GEMINI" | grep -m1 lastDisabledCaller | sed 's/.*lastDisabledCaller: //'
}
guard_count() {
  local n=0 c cls
  for c in "${COMPONENTS[@]}"; do cls=$(class_of "$c"); is_disabled "$cls" && n=$((n+1)); done
  echo "$n"
}
# 被 PartnerSetup 禁过的应用 (历史证据, 全机扫描 lastDisabledCaller)
victim_packages() {
  devsh "dumpsys package" | awk '/Package \[/{gsub(/[\[\]]/," ");p=$2}
    /lastDisabledCaller: '"$PKG"'/ && p!="" {print p}' | sort -u
}
installed_packages() { devsh "pm list packages" | sed 's/^package://'; }

cmd_status() {
  refresh_disabled
  local gs n
  gs=$(gemini_state); n=$(guard_count)
  echo "设备: $SER"
  echo "$GEMINI: $(state_name "$gs")   lastDisabledCaller: $(gemini_caller)"
  [ "$n" -eq "${#COMPONENTS[@]}" ] && echo "防护: $n/${#COMPONENTS[@]} 已禁用 [防护中]" \
    || echo "防护: $n/${#COMPONENTS[@]} 已禁用 [未防护]"
  local c cls
  for c in "${COMPONENTS[@]}"; do
    cls=$(class_of "$c")
    if is_disabled "$cls"; then echo "  已禁  $cls"; else echo "  启用  $cls"; fi
  done
}

cmd_on() {
  refresh_disabled
  local c cls out st v
  echo "== 开启防护 ($SER) =="
  echo "-- 恢复被地区策略禁用的应用 --"
  local inst; inst=$(installed_packages)
  for v in $(victim_packages); do
    if ! echo "$inst" | grep -qx "$v"; then echo "  跳过  $v (未安装)"; continue; fi
    st=$(pkg_state "$v")
    case "$st" in
      0|1) echo "  已启用  $v";;
      *)   devsh "pm enable $v" >/dev/null && echo "  新启用  $v (原: $(state_name "$st"))";;
    esac
  done
  echo "-- 禁用 $PKG 重禁入口 --"
  for c in "${COMPONENTS[@]}"; do
    cls=$(class_of "$c")
    if is_disabled "$cls"; then
      echo "  已禁  $cls"
    else
      out=$(devsh "pm disable $c" | head -1)
      echo "  新禁  $cls   ${out}"
    fi
  done
  st=$(gemini_state)
  if [ "$st" != "1" ] && [ "$st" != "0" ]; then
    devsh "pm enable $GEMINI" >/dev/null
    echo "  [恢复] $GEMINI 已重新启用"
  fi
  refresh_disabled
  echo "结果: $(guard_count)/${#COMPONENTS[@]} 已禁用; Gemini=$(state_name "$(gemini_state)")"
  [ "$(guard_count)" -eq "${#COMPONENTS[@]}" ] && echo "[OK] 防护生效" || echo "[!] 有入口未禁成, 检查上方输出"
}

cmd_off() {
  local c out
  echo "== 关闭防护/恢复原状 ($SER) =="
  for c in "${COMPONENTS[@]}"; do
    out=$(devsh "pm enable $c" | head -1)
    echo "  恢复  $(class_of "$c")   ${out}"
  done
  devsh "pm enable $GEMINI" >/dev/null
  refresh_disabled
  echo "结果: $(guard_count)/${#COMPONENTS[@]} 已禁用; Gemini=$(state_name "$(gemini_state)")"
  echo "注意: 入口已恢复, 开机/配置同步/换SIM/应用更新后应用可能再次被自动隐藏"
}

case "${1:-}" in
  on)     cmd_on;;
  off)    cmd_off;;
  status) cmd_status;;
  *)      usage; exit 1;;
esac
