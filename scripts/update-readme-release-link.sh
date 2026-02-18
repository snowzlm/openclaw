#!/bin/bash

# 获取当前版本号
VERSION=$(node -p "require('./package.json').version")

# 生成新的 release 链接
NEW_RELEASE_URL="https://github.com/snowzlm/openclaw/releases"

# 更新 README 文件中的 release 链接
sed -i "s|https://github.com/openclaw/openclaw/releases|${NEW_RELEASE_URL}|g" README.md

# 更新 badge 中的链接
sed -i "s|https://img.shields.io/github/v/release/openclaw/openclaw|https://img.shields.io/github/v/release/snowzlm/openclaw|g" README.md

echo "✅ README 已更新为版本 ${VERSION}"
echo "🔗 Release 链接: ${NEW_RELEASE_URL}"