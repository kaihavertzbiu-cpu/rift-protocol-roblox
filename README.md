# RIFT PROTOCOL

Roblox 动作 RPG 垂直切片，围绕破韧、处决、Rift Surge 和 Overdrive 组织战斗循环，结合装备与成长系统。

![宣传插画，非实时游戏截图](docs/promotional-art.webp)

## 打开

在 Roblox Studio 打开根目录 `RIFT_PROTOCOL_WORKING.rbxlx`，使用 Play 验证当前工程。此文件为当前本地主工程，不使用旧 outputs 或诊断副本。

## 可读源码

`src/` 中的 16 个 Lua 文件直接从这份 Studio 工程导出，并按实例路径分类。场景、对象属性和其他资产仍由主工程保存；不是只有脚本的空场景。

修改源码后执行 `python scripts/build.py`，生成 `build/RIFT_PROTOCOL_EDITED.rbxlx`，不会覆盖主工程。重新打开生成副本，在 Studio 中验证后再决定是否采用。本工具只是同步脚本，不声称自动测试或发布游戏。

## 说明

已有展示入口：[Roblox RIFT PROTOCOL](https://www.roblox.com/games/73846281614199/RIFT-PROTOCOL)。当前本地构建与云端构建不自动等同；本轮没有发布或重新进行完整 Play Test。

画面资产按 Roblox 内容 ID 引用，复制到其他体验时要核对资产归属和权限。封面是 AI 辅助的宣传插画。具体源码及个人制作中使用了 AI 辅助，不表示插画全部手绘。

本包不包含 API Key、Open Cloud 发布配置、历史工程、自动发布工具或私人资料。

## 上传 GitHub

解压本项目的 ZIP。把解压后的文件和目录作为仓库内容上传，README.md 应在仓库根目录；不要只上传 ZIP 本身。项目之间分别建仓库。

也可以在解压目录打开终端执行（将 REPOSITORY_URL 替换成自己的 GitHub 仓库地址）：

```sh
git init
git add .
git commit -m "Initial project source"
git branch -M main
git remote add origin REPOSITORY_URL
git push -u origin main
```

这些步骤需要你自己的 GitHub 账号和仓库；本包没有账号令牌或自动发布脚本。
