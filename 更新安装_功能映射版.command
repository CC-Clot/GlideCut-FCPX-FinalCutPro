#!/bin/bash
# GlideCut 功能映射版 一键更新安装
# 用法：双击本文件，或在终端运行 bash "/Users/cc-mac/Developer/GlideCut/更新安装_功能映射版.command"
# 会要求输入一次管理员密码（覆盖 /Applications 必须）

set -e

PROJECT="/Users/cc-mac/Developer/GlideCut"
NEW_APP=$(find "$PROJECT/build" ~/Library/Developer/Xcode/DerivedData/GlideCut-*/Build/Products/Release \
  -maxdepth 1 -name "GlideCut.app" -type d 2>/dev/null | head -1)

# 兜底：从 DerivedData 找
if [ -z "$NEW_APP" ]; then
  NEW_APP=$(find ~/Library/Developer/Xcode/DerivedData/GlideCut-*/Build/Products/Release \
    -maxdepth 1 -name "GlideCut.app" -type d 2>/dev/null | head -1)
fi

if [ -z "$NEW_APP" ] || [ ! -d "$NEW_APP" ]; then
  echo "错误：找不到新构建的 GlideCut.app，请先执行 Release 编译。"
  exit 1
fi

echo "新版本来源：$NEW_APP"

# 1. 退出正在运行的旧版（不删配置）
if pgrep -f "/Applications/GlideCut.app/Contents/MacOS/GlideCut" >/dev/null 2>&1; then
  echo "正在退出运行中的 GlideCut..."
  pkill -f "/Applications/GlideCut.app/Contents/MacOS/GlideCut" || true
  sleep 2
fi

# 2. 备份旧版
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP="$PROJECT/.backup_shift_mapping_20261123/GlideCut_old_$STAMP.app"
if [ -d /Applications/GlideCut.app ]; then
  echo "备份旧版到：$BACKUP"
  cp -R /Applications/GlideCut.app "$BACKUP"
fi

# 3. 覆盖安装（需要管理员密码）
echo "正在覆盖安装到 /Applications（需要输入管理员密码）..."
sudo /bin/rm -rf /Applications/GlideCut.app
sudo cp -R "$NEW_APP" /Applications/GlideCut.app
sudo chown -R root:wheel /Applications/GlideCut.app

echo "安装完成。"
echo ""
echo "=== 校验 ==="
codesign -dvv /Applications/GlideCut.app 2>&1 | grep -E "Authority=|Identifier=" | head -3
echo "新二进制 SHA256："
shasum -a 256 /Applications/GlideCut.app/Contents/MacOS/GlideCut
echo ""
echo "下一步："
echo "  1. 打开 GlideCut，在设置窗口确认「输入监控」「辅助功能」均为已授权。"
echo "  2. 启动 FCP 打开测试项目，按 Docs/Shift滚轮功能映射_验证指南.md 执行步骤 A/B。"
echo "  3. 运行：cd $PROJECT && ./Verification/PanVerifier 60"
echo ""
read -r -p "是否现在启动 GlideCut？[y/N] " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
  open /Applications/GlideCut.app
fi
