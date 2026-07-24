# spring boot 模板服务

## TriggerTimerTask 补扫时间变量速记

```text
变量          含义                         是否变化        例子
startTime     当前分钟桶开始时间             固定不变        12:16:00.000
endTime       当前分钟桶结束时间             固定不变        12:17:00.000
now           当前真实时间                   每次 run 都变   12:16:03.200
nextScanMs    下一个还没扫的窗口起点          扫完会推进      12:16:00.000 -> 12:16:04.000
dueEndMs      本轮最多扫描到哪里              每次 run 计算   12:16:04.000
```

例子：

```text
分钟桶:
startTime = 12:16:00.000
endTime   = 12:17:00.000
gapMs     = 1000ms

第一次 run() 晚了:
now        = 12:16:03.200
nextScanMs = 12:16:00.000
dueEndMs   = 12:16:04.000

本轮扫描:
[12:16:00, 12:16:01)
[12:16:01, 12:16:02)
[12:16:02, 12:16:03)
[12:16:03, 12:16:04)

扫完:
nextScanMs = 12:16:04.000

第二次 run():
now        = 12:16:04.200
nextScanMs = 12:16:04.000
dueEndMs   = 12:16:05.000

本轮扫描:
[12:16:04, 12:16:05)

扫完:
nextScanMs = 12:16:05.000
```

一句话记：

```text
now        = 真实时间已经到哪
nextScanMs = 我已经扫到哪
dueEndMs   = 这轮最多允许扫到哪

本轮实际扫描范围 = [nextScanMs, dueEndMs)
```

构建子服务项目模板

## 接入能力

* spring cloud nacos 服务注册
* spring cloud nacos 配置中心
* spring cloud open feign 服务通信
* lombok 简化开发

## 模板使用

1. 复制`bitstorm-svr-tmpl`修改项目名为新项目名称
2. 修改新项目`pom.xml`文件`artifactId`节点为新项目名称 
3. 修改根项目`pom.xml`文件`modules`节点，加入新项目
4. 修改`package`包名，包括 import 的包名 
5. 修改`启动类名称`
