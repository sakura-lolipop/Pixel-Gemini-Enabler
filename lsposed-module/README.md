# GeminiGuard — LSPosed 模块（libxposed API 102）

比 `gemini_guard.sh` 更外科的方案：不动 PartnerSetup 的任何组件，
直接钩掉它对 `PackageManager.setApplicationEnabledSetting` 的禁用调用。
**无论哪个入口（广播 / Job / 未来新增路径）发起，都在最后一跳被拦**，
其余功能 100% 保留。

## 原理

作用域 = `com.google.android.partnersetup`。模块注入该进程后，
hook `android.app.ApplicationPackageManager.setApplicationEnabledSetting(String, int, int)`：

```java
hook(m).intercept((XposedInterface.Chain chain) -> {
    if ("com.google.android.apps.bard".equals(chain.getArg(0))) {
        int state = (Integer) chain.getArg(1);
        // 0=DEFAULT 1=ENABLED 放行；2/3/4=各类 DISABLED 直接吞掉
        if (state != 0 && state != 1) return null;   // 不调 proceed() = 原调用不执行
    }
    return chain.proceed();
});
```

## 安装（二选一）

1. 直接装 `geminiguard.apk`（已签名，12KB），然后在 LSPosed 管理器里
   启用模块（作用域已预置为 `com.google.android.partnersetup`），重启。
2. 自行构建（见下）。

## 验证

重启后，LSPosed 日志中应出现：

```
GeminiGuard: hooked setApplicationEnabledSetting in com.google.android.partnersetup
GeminiGuard: blocked setApplicationEnabledSetting(com.google.android.apps.bard, 2)   ← 拦截发生时
```

若要彻底交给模块，可运行 `../gemini_guard.sh off` 还原 8 个组件；
两者叠加运行也完全兼容（双保险）。

## 构建（无需 Android Studio/Gradle，JDK 11 即可）

依赖四个构建件（Maven Central / Google Maven / GitHub Releases 均可下载）：
`io.github.libxposed:api:102.0.0`(aar，取 classes.jar 作为 d8 的 --lib)、
`com.android.tools:r8:8.3.37`、`com.android.tools.build:aapt2:8.1.4-10154469`(windows)、
`uber-apk-signer:1.3.0`。

```sh
# 1) 编译（libxposed api 102 的类文件是 Java 17 版本，JDK 11 读不了，
#    因此用 stubs/ 下的等签名编译期替身；真 API 由 LSPosed 运行时提供，不打包进 dex）
javac -encoding UTF-8 --release 11 -sourcepath stubs -d out src/me/sakura/geminiguard/GeminiGuard.java
# 2) dex（--lib 指向真 API jar + android.jar 消除 missing-class）
java -cp r8.jar com.android.tools.r8.D8 --release --min-api 33 \
     --lib classes.jar --lib android.jar --output dexout out/me/sakura/geminiguard/GeminiGuard.class
# 3) 打包
aapt2 link -I android.jar --manifest AndroidManifest.xml --min-sdk-version 29 \
     --target-sdk-version 34 -o base.apk
# 4) 注入 classes.dex 与 assets/META-INF/xposed/{java_init.list,scope.list} 后签名
java -jar uber-apk-signer.jar --apks base.apk --overwrite
```

## 文件

- `src/…/GeminiGuard.java` — 全部逻辑（~50 行）
- `assets/META-INF/xposed/java_init.list` — libxposed 入口声明
- `assets/META-INF/xposed/scope.list` + manifest `xposedscope` — 作用域
- `stubs/` — 编译期 API 替身（仅 javac 用，不进产物）
