#!/usr/bin/env bash
# latte-audio-switch.sh - 按声卡 profile 自动应用音频路由（扬声器/耳机）
#
# 背景：xiaomi-latte 的耳机与扬声器共用 rt5659 模拟输出，区别只在
#   - 扬声器：tfa9890 功放使能（Amp Switch L/R on）
#   - 耳机：模拟 mixer 开关 + codec_out0 增益（Amp Switch L/R off）
# 插拔由内核 rt5659 JD3 检测上报，WirePlumber 依 jack 自动切换 card profile，
# 本服务监听 profile 变化并应用对应 mixer 路由。
#
# 依赖：pipewire / wireplumber / alsa-utils（amixer）/ 内核 audio-headphone-jack.patch
set -u

CARD="alsa_card.platform-cht-bsw-rt5659"

apply_headphones() {
    amixer -c 0 cset numid=113 -- 0 >/dev/null 2>&1     # codec_out0 Gain 0dB
    amixer -c 0 cset numid=112 on >/dev/null 2>&1       # codec_out0 Switch
    amixer -c 0 cset numid=157 on >/dev/null 2>&1       # DAC1 Playback Switch
    amixer -c 0 cset numid=238 on >/dev/null 2>&1       # DAC1 MIXL DAC1 Switch
    amixer -c 0 cset numid=240 on >/dev/null 2>&1       # DAC1 MIXR DAC1 Switch
    amixer -c 0 cset numid=249 on >/dev/null 2>&1       # Stereo DAC MIXL DAC L1 Switch
    amixer -c 0 cset numid=254 on >/dev/null 2>&1       # Stereo DAC MIXR DAC R1 Switch
    amixer -c 0 cset numid=178 on >/dev/null 2>&1       # Headphone Switch
    amixer -c 0 cset numid=309 on >/dev/null 2>&1       # HPO L Playback Switch
    amixer -c 0 cset numid=310 on >/dev/null 2>&1       # HPO R Playback Switch
    amixer -c 0 cset numid=153 28 >/dev/null 2>&1       # Headphone Playback Volume
    amixer -c 0 cset "name='Amp Switch L'" off >/dev/null 2>&1
    amixer -c 0 cset "name='Amp Switch R'" off >/dev/null 2>&1
}

apply_speaker() {
    amixer -c 0 cset "name='Amp Switch L'" on >/dev/null 2>&1
    amixer -c 0 cset "name='Amp Switch R'" on >/dev/null 2>&1
}

last=""
while true; do
    profile="$(pactl list cards 2>/dev/null \
        | grep -A1 "Name: $CARD" | grep "Active Profile:" | head -1 \
        | sed 's/.*Profile: //')"

    mode="speaker"
    case "$profile" in
        *HeadPhones*|*Headphones*) mode="headphones" ;;
    esac

    if [ "$mode" != "$last" ]; then
        case "$mode" in
            headphones) apply_headphones ;;
            *)          apply_speaker ;;
        esac
        last="$mode"
    fi
    sleep 1
done
