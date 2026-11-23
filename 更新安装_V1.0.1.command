#!/bin/bash
# GlideCut V1.0.1 一键更新安装（顶部展示 UI + 关于区四码 + 使用声明）
# 用法：双击本文件，或在终端运行：
#   bash "/Users/cc-mac/Developer/GlideCut/更新安装_V1.0.1.command"
# 会要求输入一次管理员密码（覆盖 /Applications 必须）

set -e

PROJECT="/Users/cc-mac/Developer/GlideCut"
PKG="$PROJECT/发行包/GlideCut-1.0.1.pkg"
AUTHOR_EMAIL="keyframecc@foxmail.com"

if [ ! -f "$PKG" ]; then
  echo "错误：找不到安装包 $PKG"
  exit 1
fi

cat <<'DECLA'

================================================================
  GlideCut 使用声明（安装前请仔细阅读）
================================================================

【使用范围】
  本软件仅供个人学习、研究与自用，免费提供。

【禁止行为】
  未经作者书面许可，不得将本软件或其修改版本用于商业转卖、
  付费分发、捆绑销售、租赁，或以本软件名义收取任何费用；
  不得移除或篡改版权标识与声明。

【免责条款】
  软件按「现状」提供，不附带任何明示或默示担保。因使用或
  无法使用本软件导致的任何直接、间接、附带或后果性损失，
  作者不承担责任。

【知识产权】
  软件的著作权归作者所有；引用第三方组件遵循其各自的许可协议。

【联系方式】
  使用授权、问题反馈、商业合作请联系作者：keyframecc@foxmail.com
  （软件设置窗口的「关于 GlideCut」中可一键复制该邮箱）

================================================================
DECLA

read -r -p "我已阅读并同意上述使用声明。是否继续安装？[y/N] " agree
if [ "$agree" != "y" ] && [ "$agree" != "Y" ]; then
  echo "已取消安装。若需授权或合作，请联系：$AUTHOR_EMAIL"
  exit 0
fi

echo ""
echo "=== GlideCut V1.0.1 更新安装 ==="
echo "安装包：$PKG"
shasum -a 256 "$PKG"

# 1. 退出正在运行的旧版（不删配置）
if pgrep -f "/Applications/GlideCut.app/Contents/MacOS/GlideCut" >/dev/null 2>&1; then
  echo "正在退出运行中的 GlideCut..."
  pkill -f "/Applications/GlideCut.app/Contents/MacOS/GlideCut" || true
  sleep 2
fi

# 2. 备份旧版
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP="$PROJECT/.backup_before_v101_$STAMP"
mkdir -p "$BACKUP"
if [ -d /Applications/GlideCut.app ]; then
  echo "备份旧版到：$BACKUP/GlideCut_old.app"
  cp -R /Applications/GlideCut.app "$BACKUP/GlideCut_old.app"
fi

# 3. 安装新 pkg（需要管理员密码）
echo "正在安装 V1.0.1 到 /Applications（需要输入管理员密码）..."
sudo installer -pkg "$PKG" -target /

echo ""
echo "安装完成。校验："
plutil -extract CFBundleShortVersionString raw -o - /Applications/GlideCut.app/Contents/Info.plist
shasum -a 256 /Applications/GlideCut.app/Contents/MacOS/GlideCut

echo ""
echo "下一步："
echo "  1. 从菜单栏打开「设置…」，确认顶部展示、四个分区边框、关于区四张二维码与邮箱一键复制。"
echo "  2. 在 系统设置 → 隐私与安全性 确认「输入监控」「辅助功能」均已授权。"
echo "  3. 若界面仍是旧的，务必先从菜单栏点「退出 GlideCut」再重新打开。"

read -r -p "是否现在启动 GlideCut？[y/N] " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
  open /Applications/GlideCut.app
fi
