# 听见非遗 比赛提交工程

版本：R37 / v0.6.4；平台：安路 EG4S20BG256，M0 底板；开发工具：TD 6.2.1（6.2.168.116）。

## 文件用途

- `fpga/`：完整源码、IP 依赖、ROM 数据、管脚与时序约束、TD 工程。
- `tools/configure_project.py`：解压后配置本机工程路径，编译前必须执行。
- `tools/build.ps1`：完整编译脚本。
- `firmware/TINGJIAN_R37_0_6_4_NATIVE_CLEAR.bit`：原 R37 发布固件，可直接使用原已验证的下载方式下载。
- `tf_card/TINGJIAN/ASSETS.BIN`：配套 V8 白底照片和音频资源，运行必需。
- `RESOURCE_SOURCES.md`：实际配套媒体的来源、署名及第三方归属。

## 直接运行

TF 卡使用 FAT32。将 `tf_card` 中的整个 `TINGJIAN` 文件夹复制到 TF 卡根目录，使路径为 `卡盘符:/TINGJIAN/ASSETS.BIN`。已经使用同版本资源的卡无需重复复制。断电插卡，接好原供电及 HDMI，下载 firmware 中的 bit。bit 为原发布文件，没有用此次整理副本重新生成固件。仅 RAM 下载不会在断电后保留；上电自启动需按板卡流程固化 Flash。

## 源码编译

将整个文件夹解压到英文路径，在本文件所在目录运行：

```powershell
python tools/configure_project.py
```

然后用 TD 打开 `fpga/project/Tingjian.al`，顶层 `top`，对应源文件 `fpga/rtl/tj_top.v`。也可使用命令行完整构建：

```powershell
powershell -ExecutionPolicy Bypass -File tools/build.ps1 -TdExe "E:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe"
```

按实际安装位置修改 TdExe。新编译输出位于 `fpga/project/Tingjian_Runs`。不要重新生成 IP 覆盖随包配套文件；重新生成的固件须重新检查布局布线时序及上板效果。

源码整理副本已通过 TD 综合，综合资源报告与原 R37 一致；此结论不替代新固件的布局布线与板级验证。随包 bit 是原发布固件。

## 版本与内容说明

本包仅保留现行实现、编译所需依赖、固件及运行资源；不含 GitHub 上传指南、旧版工程、实验候选、日志、软件安装包或编译缓存。`.hex` 为显示和波形需要的数据，不能作为无用文件删除。

功能：四乐器认知与试听、结构细节、全屏展示、循环展播及转场、局部取景、亮度/对比度调节、实时总波形、55 秒预混合奏与声部包络显示。HDMI 输出 1920×1080、约30.303 Hz。

第三方 IP、例程与媒体保留各自权利；本包用于比赛工程提交，不代表其中所有依赖都已取得公开再分发许可。

## 六键操作

普通页面：KEY0确认/播放暂停，KEY1下一项，KEY2上一项，KEY3返回，KEY4全屏，KEY5显示设置。设置中KEY0选参数、KEY1/2增减、KEY3关闭，亮度/对比度默认4/4。

局部取景页面：KEY0上、KEY1下、KEY2左、KEY3右、KEY4放大；KEY5短按缩小、长按约0.8秒返回。实际操作以页面提示为准。

合奏KEY0暂停/继续及结束后重播，KEY3返回；不提供实时五轨静音、独奏或混音控制。
